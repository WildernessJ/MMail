import Foundation

// Pragmatic MIME helpers: RFC 2047 header decoding, outgoing message building,
// and a minimal text-part extractor for incoming messages.
enum MIME {

    // MARK: RFC 2047 encoded-word header decoding ("=?utf-8?B?...?=")

    static func decodeHeader(_ input: String) -> String {
        guard input.contains("=?") else { return input }
        var result = ""
        var rest = Substring(input)
        while let start = rest.range(of: "=?") {
            result += rest[rest.startIndex..<start.lowerBound]
            let after = rest[start.upperBound...]
            // charset?enc?text?=
            guard let q1 = after.range(of: "?"),
                  let q2 = after[q1.upperBound...].range(of: "?"),
                  let end = after[q2.upperBound...].range(of: "?=") else {
                result += "=?"; rest = after; continue
            }
            let charset = String(after[after.startIndex..<q1.lowerBound])
            let enc = String(after[q1.upperBound..<q2.lowerBound]).uppercased()
            let text = String(after[q2.upperBound..<end.lowerBound])
            if let decoded = decodeWord(text, encoding: enc, charset: charset) {
                result += decoded
            } else {
                result += text
            }
            rest = after[end.upperBound...]
        }
        result += rest
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeWord(_ text: String, encoding: String, charset: String) -> String? {
        let data: Data?
        if encoding == "B" {
            data = Data(base64Encoded: text)
        } else { // "Q" — quoted-printable variant (underscore = space)
            data = quotedPrintableData(text.replacingOccurrences(of: "_", with: " "), underscoreSpace: true)
        }
        guard let d = data else { return nil }
        return string(from: d, charset: charset)
    }

    // MARK: Outgoing message

    static func buildMessage(from: String, fromName: String?, to: String, cc: String = "",
                             subject: String, body: String, date: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        let dateStr = df.string(from: date)
        let messageID = "<\(UUID().uuidString)@mmail.local>"
        let fromHeader: String
        if let name = fromName, !name.isEmpty {
            fromHeader = "\(encodeWordIfNeeded(name)) <\(from)>"
        } else {
            fromHeader = from
        }
        let bodyData = Data(body.utf8)
        let encodedBody = bodyData.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn])

        var headers: [String] = []
        headers.append("From: \(fromHeader)")
        headers.append("To: \(to)")
        if !cc.trimmingCharacters(in: .whitespaces).isEmpty { headers.append("Cc: \(cc)") }
        headers.append("Subject: \(encodeWordIfNeeded(subject))")
        headers.append("Date: \(dateStr)")
        headers.append("Message-ID: \(messageID)")
        headers.append("MIME-Version: 1.0")
        headers.append("Content-Type: text/plain; charset=utf-8")
        headers.append("Content-Transfer-Encoding: base64")
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + encodedBody + "\r\n"
    }

    private static func encodeWordIfNeeded(_ s: String) -> String {
        if s.allSatisfy({ $0.isASCII }) { return s }
        let b64 = Data(s.utf8).base64EncodedString()
        return "=?utf-8?B?\(b64)?="
    }

    // MARK: Incoming text extraction

    static func extractText(from data: Data) -> String {
        let (headers, body) = splitHeadersBody(data)
        let contentType = headers["content-type"] ?? "text/plain"
        let encoding = (headers["content-transfer-encoding"] ?? "").lowercased()

        if contentType.lowercased().contains("multipart/"),
           let boundary = parameter("boundary", in: contentType) {
            return extractFromMultipart(body, boundary: boundary)
        }

        let decoded = decodeBody(body, encoding: encoding)
        let charset = parameter("charset", in: contentType) ?? "utf-8"
        var text = string(from: decoded, charset: charset) ?? String(decoding: decoded, as: UTF8.self)
        if contentType.lowercased().contains("text/html") { text = stripHTML(text) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFromMultipart(_ body: Data, boundary: String) -> String {
        let parts = splitParts(body, boundary: boundary)
        // Prefer text/plain, then text/html.
        var htmlFallback: String?
        for part in parts {
            let (h, b) = splitHeadersBody(part)
            let ct = (h["content-type"] ?? "text/plain").lowercased()
            let enc = (h["content-transfer-encoding"] ?? "").lowercased()
            if ct.contains("multipart/"), let inner = parameter("boundary", in: h["content-type"] ?? "") {
                let nested = extractFromMultipart(b, boundary: inner)
                if !nested.isEmpty { return nested }
                continue
            }
            let decoded = decodeBody(b, encoding: enc)
            let charset = parameter("charset", in: h["content-type"] ?? "") ?? "utf-8"
            let text = string(from: decoded, charset: charset) ?? String(decoding: decoded, as: UTF8.self)
            if ct.contains("text/plain") {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if ct.contains("text/html"), htmlFallback == nil {
                htmlFallback = stripHTML(text)
            }
        }
        return (htmlFallback ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Low-level parsing

    private static func splitHeadersBody(_ data: Data) -> (headers: [String: String], body: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let sep = text.range(of: "\r\n\r\n") ?? text.range(of: "\n\n")
        guard let sep else { return ([:], data) }
        let headerText = String(text[text.startIndex..<sep.lowerBound])
        let bodyText = String(text[sep.upperBound...])
        return (parseHeaders(headerText), Data(bodyText.utf8))
    }

    private static func parseHeaders(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        var currentKey: String?
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let first = line.first, first == " " || first == "\t", let key = currentKey {
                map[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[line.startIndex..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                map[key] = value
                currentKey = key
            }
        }
        return map
    }

    private static func parameter(_ name: String, in header: String) -> String? {
        for piece in header.split(separator: ";") {
            let kv = piece.trimmingCharacters(in: .whitespaces)
            let lower = kv.lowercased()
            if lower.hasPrefix(name.lowercased() + "=") {
                var v = String(kv.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 { v = String(v.dropFirst().dropLast()) }
                return v
            }
        }
        return nil
    }

    private static func splitParts(_ body: Data, boundary: String) -> [Data] {
        let delimiter = Data(("--" + boundary).utf8)
        var parts: [Data] = []
        var search = body.startIndex
        var ranges: [Range<Data.Index>] = []
        while let r = body.range(of: delimiter, in: search..<body.endIndex) {
            ranges.append(r)
            search = r.upperBound
        }
        for i in 0..<ranges.count {
            let start = ranges[i].upperBound
            let end = (i + 1 < ranges.count) ? ranges[i + 1].lowerBound : body.endIndex
            guard start < end else { continue }
            var chunk = body.subdata(in: start..<end)
            // Strip leading CRLF and trailing CRLF before next boundary.
            while chunk.first == 0x0D || chunk.first == 0x0A { chunk.removeFirst() }
            while chunk.last == 0x0D || chunk.last == 0x0A { chunk.removeLast() }
            if !chunk.isEmpty { parts.append(chunk) }
        }
        return parts
    }

    private static func decodeBody(_ data: Data, encoding: String) -> Data {
        switch encoding {
        case "base64":
            let s = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            return Data(base64Encoded: s) ?? data
        case "quoted-printable":
            return quotedPrintableData(String(decoding: data, as: UTF8.self), underscoreSpace: false) ?? data
        default:
            return data
        }
    }

    private static func quotedPrintableData(_ s: String, underscoreSpace: Bool) -> Data? {
        var out = [UInt8]()
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "=" {
                if i + 1 < chars.count && chars[i + 1] == "\n" { i += 2; continue }
                if i + 2 < chars.count && chars[i + 1] == "\r" { i += 3; continue }
                if i + 2 < chars.count, let byte = UInt8(String(chars[i + 1...i + 2]), radix: 16) {
                    out.append(byte); i += 3; continue
                }
                out.append(0x3D); i += 1
            } else if c == "_" && underscoreSpace {
                out.append(0x20); i += 1
            } else {
                out.append(contentsOf: Array(String(c).utf8)); i += 1
            }
        }
        return Data(out)
    }

    private static func string(from data: Data, charset: String) -> String? {
        switch charset.lowercased() {
        case "utf-8", "utf8", "us-ascii", "ascii":
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        case "iso-8859-1", "latin1", "iso8859-1":
            return String(data: data, encoding: .isoLatin1)
        case "windows-1252", "cp1252":
            return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
        default:
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html
        for (tag, repl) in [("<br>", "\n"), ("<br/>", "\n"), ("<br />", "\n"), ("</p>", "\n\n"), ("</div>", "\n")] {
            text = text.replacingOccurrences(of: tag, with: repl, options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (e, r) in entities { text = text.replacingOccurrences(of: e, with: r) }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
}
