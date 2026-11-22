/// Minimal parser for classic `Localizable.strings` files
/// (`"key" = "value";` with `/* */` and `//` comments). Used by the tests that
/// keep es.lproj and en.lproj in sync (CLAUDE.md, rule 9).
public enum StringsFile {
    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let line: Int
        public let message: String
        public var description: String { "line \(line): \(message)" }
    }

    public static func parse(_ text: String) throws -> [String: String] {
        var result: [String: String] = [:]
        let chars = Array(text.unicodeScalars)
        var i = 0
        var line = 1

        func peek(_ offset: Int = 0) -> Unicode.Scalar? {
            i + offset < chars.count ? chars[i + offset] : nil
        }
        func fail(_ m: String) -> ParseError { ParseError(line: line, message: m) }

        func skipTrivia() throws {
            while let c = peek() {
                if c == "\n" { line += 1; i += 1 }
                else if c == " " || c == "\t" || c == "\r" || c == "\u{FEFF}" { i += 1 }
                else if c == "/" && peek(1) == "*" {
                    i += 2
                    while true {
                        guard let d = peek() else { throw fail("unterminated comment") }
                        if d == "*" && peek(1) == "/" { i += 2; break }
                        if d == "\n" { line += 1 }
                        i += 1
                    }
                } else if c == "/" && peek(1) == "/" {
                    while let d = peek(), d != "\n" { i += 1 }
                } else { return }
            }
        }

        func quoted() throws -> String {
            guard peek() == "\"" else { throw fail("expected '\"'") }
            i += 1
            var s = String.UnicodeScalarView()
            while true {
                guard let c = peek() else { throw fail("unterminated string") }
                i += 1
                if c == "\"" { return String(s) }
                if c == "\n" { line += 1 }
                if c == "\\" {
                    guard let e = peek() else { throw fail("bad escape") }
                    i += 1
                    switch e {
                    case "n": s.append("\n")
                    case "t": s.append("\t")
                    case "r": s.append("\r")
                    case "\"": s.append("\"")
                    case "\\": s.append("\\")
                    default: s.append(e)
                    }
                } else {
                    s.append(c)
                }
            }
        }

        while true {
            try skipTrivia()
            if peek() == nil { break }
            let keyLine = line
            let key = try quoted()
            try skipTrivia()
            guard peek() == "=" else { throw fail("expected '=' after \"\(key)\"") }
            i += 1
            try skipTrivia()
            let value = try quoted()
            try skipTrivia()
            guard peek() == ";" else { throw fail("expected ';' after \"\(key)\"") }
            i += 1
            if result[key] != nil {
                throw ParseError(line: keyLine, message: "duplicate key \"\(key)\"")
            }
            result[key] = value
        }
        return result
    }

    /// Format specifiers in order (`%@`, `%d`, `%ld`, `%1$@`…), so a
    /// translation cannot silently drop or reorder an argument type.
    public static func formatSpecifiers(in value: String) -> [String] {
        var out: [String] = []
        let s = Array(value)
        var i = 0
        while i < s.count {
            if s[i] == "%" {
                if i + 1 < s.count, s[i + 1] == "%" { i += 2; continue }
                var j = i + 1
                var spec = "%"
                while j < s.count, s[j].isNumber || s[j] == "$" || s[j] == "." || s[j] == "l" {
                    if s[j] == "l" { spec.append("l") }
                    j += 1
                }
                if j < s.count { spec.append(s[j]) }
                out.append(spec)
                i = j + 1
            } else {
                i += 1
            }
        }
        return out.sorted()
    }
}
