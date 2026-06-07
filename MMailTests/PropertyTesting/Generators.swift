import Foundation
@testable import MMail

/// A value generator: produces a `T` from a seeded RNG and knows how to shrink
/// a value toward simpler candidates. `shrink` returns strictly-simpler
/// variants of its argument (never the argument itself, never an infinite
/// chain) so the `forAll` runner can minimize a failing input.
struct Gen<T> {
    let generate: (inout SplitMix64) -> T
    /// Candidate simplifications of a value, ordered simplest-first.
    var shrink: (T) -> [T] = { _ in [] }

    func map<U>(_ transform: @escaping (T) -> U) -> Gen<U> {
        // Mapped generators drop shrinking (the inverse is unknown); compose at
        // the source type instead when shrinking matters.
        Gen<U>(generate: { rng in transform(self.generate(&rng)) })
    }
}

// MARK: - Primitive generators

extension Gen where T == Int {
    /// Non-negative ints in `0..<bound`, shrinking toward 0.
    static func intNonNegative(below bound: Int = 1000) -> Gen<Int> {
        Gen<Int>(
            generate: { rng in Int(rng.next() % UInt64(bound)) },
            shrink: { n in
                guard n > 0 else { return [] }
                var out: [Int] = [0]
                if n > 1 { out.append(n / 2) }
                if n - 1 != n / 2 && n - 1 > 0 { out.append(n - 1) }
                return out
            }
        )
    }
}

extension Gen where T == Bool {
    static var bool: Gen<Bool> {
        Gen<Bool>(generate: { rng in rng.next() & 1 == 0 })
    }
}

extension Gen where T == String {
    /// Arbitrary unicode/bytes-as-text string: a mix of ASCII punctuation,
    /// whitespace, control-ish chars, multibyte scalars, and the `=?` marker so
    /// MIME slow paths are exercised. Shrinks by removing characters.
    static var arbitrary: Gen<String> {
        let alphabet: [Character] = Array(
            "abc XYZ 0=?<>@,;\"'\\\n\t" + "éあ💥\u{0000}\u{FFFD}/:."
        )
        return Gen<String>(
            generate: { rng in
                let len = Int(rng.next() % 24)
                var s = ""
                for _ in 0..<len {
                    s.append(alphabet[Int(rng.next() % UInt64(alphabet.count))])
                }
                return s
            },
            shrink: shrinkString
        )
    }

    /// Arbitrary string guaranteed to contain NO `=?` substring anywhere — the
    /// `decodeHeader` fast-path passthrough property requires this invariant
    /// (any `=?` mid-string takes the slow path and trims). Built from an
    /// alphabet that excludes `=` and `?` entirely, so `=?` can never appear.
    static var noEncodedWord: Gen<String> {
        let alphabet: [Character] = Array(
            "abc XYZ 0<>@,;\"'\\\n\t" + "éあ💥\u{FFFD}/:.-_ "
        )
        precondition(!alphabet.contains("=") && !alphabet.contains("?"))
        return Gen<String>(
            generate: { rng in
                let len = Int(rng.next() % 24)
                var s = ""
                for _ in 0..<len {
                    s.append(alphabet[Int(rng.next() % UInt64(alphabet.count))])
                }
                return s
            },
            shrink: { s in shrinkString(s).filter { !$0.contains("=?") } }
        )
    }

    /// Generic string shrink: try the empty string, the two halves, and each
    /// one-character-removed variant.
    static func shrinkString(_ s: String) -> [String] {
        guard !s.isEmpty else { return [] }
        var out: [String] = [""]
        let chars = Array(s)
        if chars.count > 1 {
            out.append(String(chars[0..<chars.count / 2]))
            out.append(String(chars[chars.count / 2..<chars.count]))
        }
        for i in chars.indices {
            var c = chars
            c.remove(at: i)
            out.append(String(c))
        }
        // De-dup while keeping order; drop the original.
        var seen = Set<String>()
        return out.filter { $0 != s && seen.insert($0).inserted }
    }
}

extension Gen where T == Data {
    /// Arbitrary bytes including empty and truncated-MIME-looking content.
    static var arbitrary: Gen<Data> {
        let snippets: [[UInt8]] = [
            Array("Content-Type: text/plain\r\n\r\nhi".utf8),
            Array("Content-Type: multipart/mixed; boundary=\"x\"\r\n".utf8),
            Array("=?utf-8?B?".utf8),
            Array("Content-Transfer-Encoding: base64\r\n\r\n!!!notbase64".utf8)
        ]
        return Gen<Data>(
            generate: { rng in
                // ~25% of the time, prefix a truncated MIME snippet.
                var bytes: [UInt8] = []
                if rng.next() % 4 == 0 {
                    bytes = snippets[Int(rng.next() % UInt64(snippets.count))]
                }
                let len = Int(rng.next() % 40)
                for _ in 0..<len { bytes.append(UInt8(rng.next() % 256)) }
                return Data(bytes)
            },
            shrink: { d in
                guard !d.isEmpty else { return [] }
                return [Data(), d.prefix(d.count / 2)]
            }
        )
    }
}

// MARK: - URL generator (http/https only)

extension Gen where T == URL {
    /// An `http`/`https` URL whose query mixes tracking keys (from
    /// `Privacy.trackingParams`) with arbitrary non-tracking keys. mailto/file/
    /// opaque URLs are out of scope per the spec.
    static var httpURL: Gen<URL> {
        let trackingKeys = Array(Privacy.trackingParams)
        let nonTrackingKeys = ["q", "id", "page", "ref_legit", "lang", "v", "x"]
        let hosts = ["example.com", "a.test", "sub.domain.co.uk"]
        let paths = ["", "/", "/path", "/a/b/c", "/p%20s"]
        let schemes = ["http", "https"]
        return Gen<URL>(
            generate: { rng in
                let scheme = schemes[Int(rng.next() % UInt64(schemes.count))]
                let host = hosts[Int(rng.next() % UInt64(hosts.count))]
                let path = paths[Int(rng.next() % UInt64(paths.count))]
                var comps = URLComponents()
                comps.scheme = scheme
                comps.host = host
                comps.path = path
                var items: [URLQueryItem] = []
                let count = Int(rng.next() % 6)
                for _ in 0..<count {
                    let pickTracking = rng.next() % 2 == 0
                    let name: String
                    if pickTracking {
                        name = trackingKeys[Int(rng.next() % UInt64(trackingKeys.count))]
                    } else {
                        name = nonTrackingKeys[Int(rng.next() % UInt64(nonTrackingKeys.count))]
                    }
                    let val = "v\(rng.next() % 1000)"
                    items.append(URLQueryItem(name: name, value: val))
                }
                if !items.isEmpty { comps.queryItems = items }
                return comps.url ?? URL(string: "https://example.com")!
            },
            shrink: { _ in [] }
        )
    }
}

// MARK: - Email generator (small id pool so duplicates occur)

extension Gen where T == Email {
    /// An `Email` varying only by `id`, drawn from a small pool so duplicate ids
    /// occur frequently (the dedup property needs collisions). Shrinking is
    /// handled at the `[Email]` level.
    static func email(idPool: [String] = ["a", "b", "c", "d"]) -> Gen<Email> {
        Gen<Email>(
            generate: { rng in
                let id = idPool[Int(rng.next() % UInt64(idPool.count))]
                return Email(id: id, account: "acct", from: "you",
                             subject: "s", preview: "p", body: "b",
                             time: "t", day: "today", folder: "inbox")
            }
        )
    }
}

extension Gen where T == [Email] {
    /// A list of emails with frequently-repeated ids. Shrinks by removing
    /// elements.
    static var emailList: Gen<[Email]> {
        let elem = Gen<Email>.email()
        return Gen<[Email]>(
            generate: { rng in
                let len = Int(rng.next() % 12)
                return (0..<len).map { _ in elem.generate(&rng) }
            },
            shrink: { list in
                guard !list.isEmpty else { return [] }
                var out: [[Email]] = [[]]
                if list.count > 1 { out.append(Array(list.dropLast())) }
                // Remove each single element.
                for i in list.indices {
                    var c = list
                    c.remove(at: i)
                    out.append(c)
                }
                return out
            }
        )
    }
}

// MARK: - Recipient-field generators

/// One generated recipient entry plus the metadata a property needs to assert
/// on it (the embedded address and the display name).
struct RecipientEntry {
    let display: String   // display-name text (may be empty)
    let address: String   // local@domain
    let rendered: String  // the actual field fragment, e.g. "Name <a@b.com>"
}

extension Gen where T == String {
    /// CONSTRAINED recipient field: clean `Name <addr>` entries joined by `,`/`;`
    /// where display names contain neither `@` nor `<`/`>`, and every address
    /// contains `@`. Used by the extraction-correctness property.
    static var constrainedRecipientField: Gen<String> {
        Gen<String>(
            generate: { rng in
                let entries = constrainedEntries(&rng)
                return joinEntries(entries.map { $0.rendered }, &rng)
            },
            shrink: shrinkString
        )
    }

    /// Same as above but exposes the structured entries for assertions.
    static func constrainedEntries(_ rng: inout SplitMix64) -> [RecipientEntry] {
        // Display names and address local-parts are kept textually disjoint so a
        // correct extraction never produces a result that incidentally
        // *contains* the display text (e.g. local "carol_99" contains "carol").
        let names = ["Alice", "Bob Jones", "Director", "", "Team Lead"]
        let locals = ["u1", "x.y", "z99", "team-box"]
        let domains = ["x.com", "mail.org", "sub.co.uk"]
        let count = 1 + Int(rng.next() % 4)
        var out: [RecipientEntry] = []
        for _ in 0..<count {
            let name = names[Int(rng.next() % UInt64(names.count))]
            let local = locals[Int(rng.next() % UInt64(locals.count))]
            let domain = domains[Int(rng.next() % UInt64(domains.count))]
            let address = "\(local)@\(domain)"
            let rendered = name.isEmpty ? "\(address)" : "\(name) <\(address)>"
            out.append(RecipientEntry(display: name, address: address, rendered: rendered))
        }
        return out
    }

    /// UNCONSTRAINED recipient field: display names with arbitrary `<`/`>` in any
    /// order (including a `>` before any `<`, which triggers the documented
    /// backwards-range crash). Used by the crash-freedom property. Do NOT
    /// constrain this to hide the defect.
    static var unconstrainedRecipientField: Gen<String> {
        // Fragments deliberately include `>`-before-`<`, lone brackets, bare
        // addresses, and empty pieces.
        let fragments = [
            "3>2 Name <a@x.com>",     // the documented crash trigger
            ">leading <b@y.org>",
            "<<weird>> <c@z.net>",
            "plain@addr.com",
            "No Brackets Here",
            "Name > <d@q.com>",
            "><><><",
            "Name <e@e.com",          // unterminated `<`
            "Name e@e.com>",          // stray closing `>`
            "",
            "a > b > c <f@f.com>"
        ]
        return Gen<String>(
            generate: { rng in
                let count = 1 + Int(rng.next() % 5)
                let picked = (0..<count).map { _ in
                    fragments[Int(rng.next() % UInt64(fragments.count))]
                }
                return joinEntries(picked, &rng)
            },
            shrink: shrinkString
        )
    }

    /// Join rendered entries with a randomly-chosen `,` or `;` between each.
    static func joinEntries(_ pieces: [String], _ rng: inout SplitMix64) -> String {
        guard !pieces.isEmpty else { return "" }
        var s = pieces[0]
        for p in pieces.dropFirst() {
            s += (rng.next() % 2 == 0 ? "," : ";") + p
        }
        return s
    }
}
