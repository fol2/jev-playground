import Foundation

/// A JSON value that keeps its object keys in order. Foundation's dictionaries do not, and the order of a
/// state's fields and a question's options is part of what Jev reads. Parsing is strict (no duplicate keys,
/// no NaN or Infinity); `text()` writes the same bytes as Python's `json.dumps`, so the offline tools that
/// replaced the Python ones send Jev exactly what those sent.
indirect enum JSON: Equatable {
    case null, bool(Bool), int(Int), double(Double), string(String), array([JSON]), object([(String, JSON)])

    struct ParseError: Error, CustomStringConvertible { let description: String }

    static func == (a: JSON, b: JSON) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.int(x), .int(y)): return x == y
        case let (.double(x), .double(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.array(x), .array(y)): return x == y
        case let (.object(x), .object(y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    static func parse(_ text: String) throws -> JSON {
        var parser = Parser(bytes: Array(text.utf8))
        parser.space()
        let value = try parser.value()
        parser.space()
        guard parser.at == parser.bytes.count else { throw ParseError(description: "trailing data after the JSON value") }
        return value
    }

    subscript(key: String) -> JSON? {
        if case let .object(pairs) = self { return pairs.first { $0.0 == key }?.1 }
        return nil
    }

    var string: String? { if case let .string(s) = self { return s }; return nil }
    var pairs: [(String, JSON)]? { if case let .object(p) = self { return p }; return nil }
    var items: [JSON]? { if case let .array(a) = self { return a }; return nil }
    /// A number, not a boolean (JSON keeps them apart; Python's `True == 1` does not).
    var number: Double? {
        switch self {
        case let .int(i): return Double(i)
        case let .double(d): return d
        default: return nil
        }
    }

    /// No NaN or infinity anywhere: what Python's `json.dumps(..., allow_nan=False)` accepts.
    var isFinite: Bool {
        switch self {
        case let .double(d): return d.isFinite
        case let .array(a): return a.allSatisfy(\.isFinite)
        case let .object(p): return p.allSatisfy { $0.1.isFinite }
        default: return true
        }
    }

    /// The object with `key` set: replaced where it stands, else added at the end (Python's `{**d, key: v}`).
    func setting(_ key: String, _ value: JSON) -> JSON {
        guard case var .object(p) = self else { return self }
        if let i = p.firstIndex(where: { $0.0 == key }) { p[i].1 = value } else { p.append((key, value)) }
        return .object(p)
    }

    /// Python's `json.dumps(value, sort_keys=sorted, ensure_ascii=ascii)`: ", " and ": " separators.
    func text(sorted: Bool = false, ascii: Bool = true) -> String {
        switch self {
        case .null: return "null"
        case let .bool(b): return b ? "true" : "false"
        case let .int(i): return String(i)
        case let .double(d): return JSON.pythonRepr(d)
        case let .string(s): return JSON.quoted(s, ascii: ascii)
        case let .array(a): return "[" + a.map { $0.text(sorted: sorted, ascii: ascii) }.joined(separator: ", ") + "]"
        case let .object(p):
            let ordered = sorted ? p.sorted { $0.0.unicodeScalars.lexicographicallyPrecedes($1.0.unicodeScalars) } : p
            return "{" + ordered.map { JSON.quoted($0.0, ascii: ascii) + ": " + $0.1.text(sorted: sorted, ascii: ascii) }
                .joined(separator: ", ") + "}"
        }
    }

    static func quoted(_ s: String, ascii: Bool) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 || (ascii && scalar.value > 0x7E) {
                    // Python writes astral characters as a lower-case surrogate pair.
                    for unit in String(scalar).utf16 { out += String(format: "\\u%04x", unit) }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Python's float repr: the shortest digits that round-trip (Swift finds the same ones), placed as
    /// Python places them: an exponent below 1e-4 and from 1e16, and ".0" on a whole number.
    static func pythonRepr(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        if d == 0 { return d.sign == .minus ? "-0.0" : "0.0" }
        var text = "\(abs(d))"
        var exponent = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            exponent = Int(text[text.index(after: e)...])!
            text = String(text[..<e])
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0]), fraction = parts.count > 1 ? String(parts[1]) : ""
        var digits = Array(whole + fraction)
        var point = whole.count + exponent  // value = 0.digits × 10^point
        while digits.first == "0" { digits.removeFirst(); point -= 1 }
        while digits.last == "0" { digits.removeLast() }
        let sign = d < 0 ? "-" : ""
        if point <= -4 || point > 16 {
            let mantissa = digits.count == 1 ? String(digits) : String(digits[0]) + "." + String(digits[1...])
            let e = point - 1
            return sign + mantissa + "e" + (e < 0 ? "-" : "+") + (abs(e) < 10 ? "0" : "") + String(abs(e))
        }
        if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + String(digits) }
        if point < digits.count { return sign + String(digits[..<point]) + "." + String(digits[point...]) }
        return sign + String(digits) + String(repeating: "0", count: point - digits.count) + ".0"
    }
}

private struct Parser {
    let bytes: [UInt8]
    var at = 0

    func fail(_ why: String) -> JSON.ParseError { JSON.ParseError(description: "\(why) at byte \(at)") }

    mutating func space() {
        while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
    }

    mutating func value() throws -> JSON {
        guard at < bytes.count else { throw fail("unexpected end") }
        switch bytes[at] {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): return try word("true", .bool(true))
        case UInt8(ascii: "f"): return try word("false", .bool(false))
        case UInt8(ascii: "n"): return try word("null", .null)
        case UInt8(ascii: "N"), UInt8(ascii: "I"): throw fail("non-finite JSON constant")
        default: return try number()
        }
    }

    mutating func word(_ w: String, _ v: JSON) throws -> JSON {
        let w = Array(w.utf8)
        guard at + w.count <= bytes.count, Array(bytes[at..<at + w.count]) == w else { throw fail("invalid literal") }
        at += w.count
        return v
    }

    mutating func object() throws -> JSON {
        at += 1
        var pairs: [(String, JSON)] = []
        var keys = Set<String>()
        space()
        if at < bytes.count, bytes[at] == UInt8(ascii: "}") { at += 1; return .object(pairs) }
        while true {
            space()
            guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") else { throw fail("expected a key") }
            let key = try string()
            guard keys.insert(key).inserted else { throw JSON.ParseError(description: "duplicate JSON key: " + key) }
            space()
            guard at < bytes.count, bytes[at] == UInt8(ascii: ":") else { throw fail("expected ':'") }
            at += 1
            space()
            pairs.append((key, try value()))
            space()
            guard at < bytes.count else { throw fail("unexpected end") }
            if bytes[at] == UInt8(ascii: ",") { at += 1; continue }
            guard bytes[at] == UInt8(ascii: "}") else { throw fail("expected ',' or '}'") }
            at += 1
            return .object(pairs)
        }
    }

    mutating func array() throws -> JSON {
        at += 1
        var items: [JSON] = []
        space()
        if at < bytes.count, bytes[at] == UInt8(ascii: "]") { at += 1; return .array(items) }
        while true {
            space()
            items.append(try value())
            space()
            guard at < bytes.count else { throw fail("unexpected end") }
            if bytes[at] == UInt8(ascii: ",") { at += 1; continue }
            guard bytes[at] == UInt8(ascii: "]") else { throw fail("expected ',' or ']'") }
            at += 1
            return .array(items)
        }
    }

    mutating func hex4() throws -> UInt32 {
        guard at + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[at..<at + 4], as: UTF8.self), radix: 16) else {
            throw fail("invalid \\u escape")
        }
        at += 4
        return v
    }

    mutating func string() throws -> String {
        at += 1
        var out: [UInt8] = []
        while at < bytes.count {
            let b = bytes[at]
            at += 1
            switch b {
            case UInt8(ascii: "\""): return String(decoding: out, as: UTF8.self)
            case 0..<0x20: throw fail("control character in a string")
            case UInt8(ascii: "\\"):
                guard at < bytes.count else { throw fail("unexpected end") }
                let e = bytes[at]
                at += 1
                switch e {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800..<0xDC00).contains(code) {
                        guard at + 2 <= bytes.count, bytes[at] == UInt8(ascii: "\\"), bytes[at + 1] == UInt8(ascii: "u") else {
                            throw fail("unpaired surrogate")
                        }
                        at += 2
                        let low = try hex4()
                        guard (0xDC00..<0xE000).contains(low) else { throw fail("unpaired surrogate") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw fail("unpaired surrogate") }
                    out.append(contentsOf: Array(String(scalar).utf8))
                default: throw fail("invalid escape")
                }
            default: out.append(b)
            }
        }
        throw fail("unterminated string")
    }

    mutating func number() throws -> JSON {
        let start = at
        func digits() -> Int { let s = at; while at < bytes.count, (0x30...0x39).contains(bytes[at]) { at += 1 }; return at - s }
        if at < bytes.count, bytes[at] == UInt8(ascii: "-") { at += 1 }
        guard at < bytes.count else { throw fail("invalid number") }
        if bytes[at] == UInt8(ascii: "0") { at += 1 } else if digits() == 0 {
            throw at < bytes.count && bytes[at] == UInt8(ascii: "I") ? fail("non-finite JSON constant") : fail("invalid value")
        }
        var real = false
        if at < bytes.count, bytes[at] == UInt8(ascii: ".") {
            at += 1
            real = true
            guard digits() > 0 else { throw fail("invalid number") }
        }
        if at < bytes.count, bytes[at] == UInt8(ascii: "e") || bytes[at] == UInt8(ascii: "E") {
            at += 1
            real = true
            if at < bytes.count, bytes[at] == UInt8(ascii: "+") || bytes[at] == UInt8(ascii: "-") { at += 1 }
            guard digits() > 0 else { throw fail("invalid number") }
        }
        let text = String(decoding: bytes[start..<at], as: UTF8.self)
        // A whole number too large for Int becomes a Double (maybe infinite), which isFinite then refuses.
        if !real, let i = Int(text) { return .int(i) }
        return .double(Double(text) ?? (text.hasPrefix("-") ? -.infinity : .infinity))
    }
}
