import Foundation
import NIO
import NIOCore
import NIOPosix
import NIOSSL

struct SMTPResponse {
    let code: Int
    let lines: [String]
    var ok: Bool { (200..<400).contains(code) }
}

// Parses SMTP replies (handles multi-line "250-foo\r\n250 bar\r\n").
final class SMTPResponseDecoder: ByteToMessageDecoder {
    typealias InboundOut = SMTPResponse
    private var pending: [String] = []

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        var producedSomething = false
        while let crlf = buffer.readableBytesView.firstRange(of: [0x0D, 0x0A]) {
            let lineLength = crlf.lowerBound - buffer.readableBytesView.startIndex
            let lineBytes = buffer.readBytes(length: lineLength) ?? []
            buffer.moveReaderIndex(forwardBy: 2) // consume CRLF
            let line = String(decoding: lineBytes, as: UTF8.self)
            pending.append(line)
            // A final line has a space as the 4th character; a dash means more follow.
            if line.count >= 4 {
                let idx = line.index(line.startIndex, offsetBy: 3)
                if line[idx] == " " {
                    let code = Int(line.prefix(3)) ?? 0
                    context.fireChannelRead(wrapInboundOut(SMTPResponse(code: code, lines: pending)))
                    pending.removeAll()
                    producedSomething = true
                }
            }
        }
        return producedSomething ? .continue : .needMoreData
    }
}

final class SMTPResponseHandler: ChannelInboundHandler {
    typealias InboundIn = SMTPResponse
    private var buffered: [SMTPResponse] = []
    private var waiters: [EventLoopPromise<SMTPResponse>] = []

    func await(promise: EventLoopPromise<SMTPResponse>) {
        if !buffered.isEmpty { promise.succeed(buffered.removeFirst()) }
        else { waiters.append(promise) }
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let resp = unwrapInboundIn(data)
        if !waiters.isEmpty { waiters.removeFirst().succeed(resp) }
        else { buffered.append(resp) }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        waiters.forEach { $0.fail(error) }; waiters.removeAll(); context.close(promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        waiters.forEach { $0.fail(MailError.notConnected) }; waiters.removeAll(); context.fireChannelInactive()
    }
}

final class SMTPService {
    private let host: String
    private let port: Int
    private let security: ConnectionSecurity
    private let username: String
    private let password: String

    private static let group = MultiThreadedEventLoopGroup.singleton
    private let handler = SMTPResponseHandler()
    private var channel: Channel?

    init(config: MailAccountConfig, password: String) {
        self.host = config.smtpHost
        self.port = config.smtpPort
        self.security = config.smtpSecurity
        self.username = config.smtpUsername
        self.password = password
    }

    /// Connects, authenticates, sends one message, and disconnects.
    /// `progress` reports the DATA upload fraction (0...1) for large messages.
    func send(from: String, fromName: String?, recipients: [String], message: String,
              progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await connect()
        defer { Task { await self.close() } }

        _ = try await expect([220])                      // greeting
        try await ehlo()
        if security == .startTLS {
            _ = try await command("STARTTLS", expect: [220])
            guard let channel = self.channel else { throw MailError.notConnected }
            let ctx = try NIOSSLContext(configuration: TLSConfiguration.makeClientConfiguration())
            let ssl = try NIOSSLClientHandler(context: ctx, serverHostname: host)
            try await channel.pipeline.addHandler(ssl, position: .first).get()
            try await ehlo()
        }
        try await authenticate()

        _ = try await command("MAIL FROM:<\(from)>", expect: [250])
        for rcpt in recipients {
            _ = try await command("RCPT TO:<\(rcpt)>", expect: [250, 251])
        }
        _ = try await command("DATA", expect: [354])
        _ = try await sendData(message, progress: progress)
        _ = try await command("QUIT", expect: [221, 250])
    }

    // MARK: Connection

    private func connect() async throws {
        let bootstrap = ClientBootstrap(group: Self.group)
            .channelInitializer { [security, host, handler] channel in
                do {
                    var handlers: [ChannelHandler] = []
                    if security == .tls {
                        let ctx = try NIOSSLContext(configuration: TLSConfiguration.makeClientConfiguration())
                        handlers.append(try NIOSSLClientHandler(context: ctx, serverHostname: host))
                    }
                    handlers.append(ByteToMessageHandler(SMTPResponseDecoder()))
                    handlers.append(handler)
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
    }

    private func close() async {
        if let channel = self.channel { try? await channel.close().get() }
        self.channel = nil
    }

    private func ehlo() async throws {
        // Identify with the sender's domain rather than "localhost", which some
        // submission servers and spam filters penalize.
        let host = username.split(separator: "@").last.map(String.init) ?? "localhost"
        _ = try await command("EHLO \(host)", expect: [250])
    }

    private func authenticate() async throws {
        _ = try await command("AUTH LOGIN", expect: [334])
        _ = try await command(Data(username.utf8).base64EncodedString(), expect: [334])
        _ = try await command(Data(password.utf8).base64EncodedString(), expect: [235])
    }

    // MARK: Plumbing

    @discardableResult
    private func command(_ line: String, expect codes: [Int]) async throws -> SMTPResponse {
        try await writeLine(line + "\r\n")
        return try await expect(codes)
    }

    @discardableResult
    private func sendData(_ message: String, progress: (@Sendable (Double) -> Void)? = nil) async throws -> SMTPResponse {
        // Dot-stuff and terminate with <CRLF>.<CRLF>.
        let normalized = message.replacingOccurrences(of: "\r\n", with: "\n")
        let stuffed = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(".") ? "." + $0 : String($0) }
            .joined(separator: "\r\n")
        let payload = Array((stuffed + "\r\n.\r\n").utf8)
        guard let channel = self.channel else { throw MailError.notConnected }
        let total = payload.count
        let chunk = 64 * 1024
        var sent = 0
        while sent < total {
            let end = Swift.min(sent + chunk, total)
            var buf = channel.allocator.buffer(capacity: end - sent)
            buf.writeBytes(payload[sent..<end])
            try await channel.writeAndFlush(buf).get()
            sent = end
            progress?(Double(sent) / Double(total))
        }
        return try await expect([250])
    }

    private func writeLine(_ s: String) async throws {
        guard let channel = self.channel else { throw MailError.notConnected }
        var buf = channel.allocator.buffer(capacity: s.utf8.count)
        buf.writeString(s)
        try await channel.writeAndFlush(buf).get()
    }

    @discardableResult
    private func expect(_ codes: [Int]) async throws -> SMTPResponse {
        guard let channel = self.channel else { throw MailError.notConnected }
        let promise = channel.eventLoop.makePromise(of: SMTPResponse.self)
        try await channel.eventLoop.submit { [handler] in handler.await(promise: promise) }.get()
        let resp = try await promise.futureResult.get()
        guard codes.contains(resp.code) else {
            throw MailError.commandFailed("\(resp.code) \(resp.lines.last ?? "")")
        }
        return resp
    }
}
