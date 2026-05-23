import Foundation
import NIO
import NIOCore
import NIOPosix
import NIOSSL
import NIOIMAP
import NIOIMAPCore

enum MailError: LocalizedError {
    case notConnected
    case connectFailed(String)
    case commandFailed(String)
    case noResult

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected."
        case .connectFailed(let m): return "Connection failed: \(m)"
        case .commandFailed(let m): return "Server rejected the command: \(m)"
        case .noResult: return "No response from server."
        }
    }
}

struct IMAPMessage {
    var uid: UInt32
    var subject: String
    var fromName: String
    var fromEmail: String
    var date: Date
    var seen: Bool
    var flagged: Bool
}

// NIO-free flag kind so the app layer doesn't import NIOIMAPCore.
enum MailFlagKind { case seen, flagged, deleted }

// Collects responses per command, matching the FIFO of issued tags.
final class IMAPResponseHandler: ChannelInboundHandler {
    typealias InboundIn = Response

    private struct Pending { let tag: String; let promise: EventLoopPromise<[Response]>; var acc: [Response] }
    private var queue: [Pending] = []

    func enqueue(tag: String, promise: EventLoopPromise<[Response]>) {
        queue.append(Pending(tag: tag, promise: promise, acc: []))
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = unwrapInboundIn(data)
        guard !queue.isEmpty else { return } // greeting / unsolicited
        switch response {
        case .tagged:
            var head = queue.removeFirst()
            head.acc.append(response)
            head.promise.succeed(head.acc)
        case .fatal(let text):
            let head = queue.removeFirst()
            head.promise.fail(MailError.commandFailed("\(text)"))
        default:
            queue[0].acc.append(response)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        failAll(error)
        context.close(promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        failAll(MailError.notConnected)
        context.fireChannelInactive()
    }
    private func failAll(_ error: Error) {
        let pending = queue; queue.removeAll()
        pending.forEach { $0.promise.fail(error) }
    }
}

final class IMAPService {
    private let host: String
    private let port: Int
    private let security: ConnectionSecurity
    private let username: String
    private let password: String

    private static let group = MultiThreadedEventLoopGroup.singleton
    private let collector = IMAPResponseHandler()
    private var channel: Channel?
    private var tagCounter = 0

    init(config: MailAccountConfig, password: String) {
        self.host = config.imapHost
        self.port = config.imapPort
        self.security = config.imapSecurity
        self.username = config.imapUsername
        self.password = password
    }

    private func nextTag() -> String { tagCounter += 1; return "a\(String(format: "%04d", tagCounter))" }

    // MARK: Connection

    func connectAndLogin() async throws {
        let bootstrap = ClientBootstrap(group: Self.group)
            .channelInitializer { [security, host, collector] channel in
                do {
                    var handlers: [ChannelHandler] = []
                    if security == .tls {
                        let ctx = try NIOSSLContext(configuration: TLSConfiguration.makeClientConfiguration())
                        handlers.append(try NIOSSLClientHandler(context: ctx, serverHostname: host))
                    }
                    handlers.append(IMAPClientHandler())
                    handlers.append(collector)
                    return channel.pipeline.addHandlers(handlers)
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
        do {
            self.channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            throw MailError.connectFailed(error.localizedDescription)
        }

        if security == .startTLS {
            _ = try await send(.startTLS)
            guard let channel = self.channel else { throw MailError.notConnected }
            let ctx = try NIOSSLContext(configuration: TLSConfiguration.makeClientConfiguration())
            let ssl = try NIOSSLClientHandler(context: ctx, serverHostname: host)
            try await channel.pipeline.addHandler(ssl, position: .first).get()
        }

        _ = try await send(.login(username: username, password: password))
    }

    func disconnect() async {
        if let channel = self.channel {
            _ = try? await send(.logout)
            try? await channel.close().get()
        }
        self.channel = nil
    }

    // MARK: Commands

    func selectInbox() async throws -> Int {
        let responses = try await send(.select(.inbox))
        for r in responses {
            if case .untagged(.mailboxData(.exists(let n))) = r { return n }
        }
        return 0
    }

    func fetchRecent(limit: Int, total: Int) async throws -> [IMAPMessage] {
        guard total > 0 else { return [] }
        let hi = UInt32(total)
        let lo = UInt32(max(1, total - limit + 1))
        let range = MessageIdentifierRange<SequenceNumber>(SequenceNumber(rawValue: lo)...SequenceNumber(rawValue: hi))
        let responses = try await send(.fetch(.range(range), [.uid, .flags, .envelope, .internalDate], []))
        return parseMessages(responses).sorted { $0.date > $1.date }
    }

    func fetchBody(uid: UInt32) async throws -> String {
        let range = MessageIdentifierRange<UID>(UID(rawValue: uid)...UID(rawValue: uid))
        let responses = try await send(.uidFetch(.range(range), [.bodySection(peek: true, .complete, nil)], []))
        var raw = ByteBuffer()
        for r in responses {
            if case .fetch(.streamingBytes(var chunk)) = r {
                raw.writeBuffer(&chunk)
            }
        }
        let data = Data(raw.readableBytesView)
        return MIME.extractText(from: data)
    }

    func store(uid: UInt32, _ kind: MailFlagKind, add: Bool) async throws {
        let flag: Flag = kind == .seen ? .seen : (kind == .flagged ? .flagged : .deleted)
        let range = MessageIdentifierRange<UID>(UID(rawValue: uid)...UID(rawValue: uid))
        let storeFlags: StoreFlags = add ? .add(silent: true, list: [flag]) : .remove(silent: true, list: [flag])
        _ = try await send(.uidStore(.range(range), [], .flags(storeFlags)))
    }

    // MARK: Plumbing

    private func send(_ command: NIOIMAPCore.Command) async throws -> [Response] {
        guard let channel = self.channel else { throw MailError.notConnected }
        let tag = nextTag()
        let promise = channel.eventLoop.makePromise(of: [Response].self)
        try await channel.eventLoop.submit { [collector] in
            collector.enqueue(tag: tag, promise: promise)
        }.get()
        let message = IMAPClientHandler.Message.part(.tagged(TaggedCommand(tag: tag, command: command)))
        channel.writeAndFlush(message, promise: nil)
        let responses = try await promise.futureResult.get()
        if let last = responses.last, case .tagged(let tagged) = last {
            if case .ok = tagged.state { return responses }
            throw MailError.commandFailed("\(tagged.state)")
        }
        return responses
    }

    private func parseMessages(_ responses: [Response]) -> [IMAPMessage] {
        var out: [IMAPMessage] = []
        var uid: UInt32 = 0
        var subject = ""
        var fromName = ""
        var fromEmail = ""
        var date = Date()
        var seen = false
        var flagged = false

        func reset() { uid = 0; subject = ""; fromName = ""; fromEmail = ""; date = Date(); seen = false; flagged = false }

        for r in responses {
            guard case .fetch(let fr) = r else { continue }
            switch fr {
            case .start, .startUID:
                reset()
            case .simpleAttribute(let attr):
                switch attr {
                case .uid(let u):
                    uid = u.rawValue
                case .flags(let flags):
                    seen = flags.contains(.seen)
                    flagged = flags.contains(.flagged)
                case .envelope(let env):
                    if let s = env.subject { subject = MIME.decodeHeader(String(buffer: s)) }
                    if let first = env.from.first, case .singleAddress(let addr) = first {
                        if let pn = addr.personName { fromName = MIME.decodeHeader(String(buffer: pn)) }
                        let mailbox = addr.mailbox.map { String(buffer: $0) } ?? ""
                        let hostPart = addr.host.map { String(buffer: $0) } ?? ""
                        if !mailbox.isEmpty { fromEmail = hostPart.isEmpty ? mailbox : "\(mailbox)@\(hostPart)" }
                    }
                    if let d = env.date, let parsed = Self.parseRFC2822(String(d)) { date = parsed }
                case .internalDate(let serverDate):
                    if let built = Self.dateFrom(serverDate.components) { date = built }
                default:
                    break
                }
            case .finish:
                if uid > 0 {
                    out.append(IMAPMessage(uid: uid, subject: subject, fromName: fromName,
                                           fromEmail: fromEmail, date: date, seen: seen, flagged: flagged))
                }
            default:
                break
            }
        }
        return out
    }

    private static func parseRFC2822(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z",
                    "EEE, d MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm Z"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func dateFrom(_ c: ServerMessageDate.Components) -> Date? {
        var comps = DateComponents()
        comps.year = c.year; comps.month = c.month; comps.day = c.day
        comps.hour = c.hour; comps.minute = c.minute; comps.second = c.second
        comps.timeZone = TimeZone(secondsFromGMT: c.zoneMinutes * 60)
        return Calendar(identifier: .gregorian).date(from: comps)
    }
}
