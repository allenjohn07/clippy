import Foundation

/// Decides whether copied text is worth recording at all.
enum TextFilter {
    /// Characters that render as nothing: zero-width space/joiners, word joiner, BOM, soft hyphen.
    private static let invisible = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}\u{00AD}")

    /// True if the text has at least one visible character.
    static func isMeaningful(_ s: String) -> Bool {
        s.unicodeScalars.contains { c in
            !CharacterSet.whitespacesAndNewlines.contains(c)
                && !CharacterSet.controlCharacters.contains(c)
                && !invisible.contains(c)
        }
    }

    /// True if the text is just one web/file URL (what browsers put next to a copied image).
    static func isSingleURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: { $0.isWhitespace }), let scheme = URL(string: t)?.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "file"].contains(scheme)
    }
}

/// Heuristics for text that is probably a password, API key or token. A false positive just
/// means one copy isn't saved in history, so this leans towards skipping.
enum SecretFilter {
    private static let knownFormats: [NSRegularExpression] = [
        #"^gh[pousr]_[A-Za-z0-9]{30,}$"#,                         // GitHub tokens
        #"^github_pat_[A-Za-z0-9_]{40,}$"#,                       // GitHub fine-grained tokens
        #"^sk-[A-Za-z0-9_\-]{20,}$"#,                             // OpenAI / Anthropic / Stripe-style keys
        #"^(AKIA|ASIA)[0-9A-Z]{16}$"#,                            // AWS access keys
        #"^xox[abposr]-[A-Za-z0-9\-]{10,}$"#,                     // Slack tokens
        #"^eyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]+$"#,  // JWTs
        #"^AIza[0-9A-Za-z_\-]{35}$"#,                             // Google API keys
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let email = try! NSRegularExpression(pattern: #"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#)
    private static let fileName = try! NSRegularExpression(pattern: #"\.[A-Za-z][A-Za-z0-9]{1,4}$"#)

    static func looksLikeSecret(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Private keys are multi-line, so check them first.
        if s.hasPrefix("-----BEGIN") && s.contains("PRIVATE KEY-----") { return true }

        // Everything else: a single "word" with no spaces.
        guard !s.isEmpty, !s.contains(where: { $0.isWhitespace }) else { return false }
        let range = NSRange(s.startIndex..., in: s)
        if knownFormats.contains(where: { $0.firstMatch(in: s, range: range) != nil }) { return true }

        guard (8...64).contains(s.count) else { return false }
        if s.contains("://") || s.lowercased().hasPrefix("www.") { return false }          // URL
        if email.firstMatch(in: s, range: range) != nil { return false }                   // email
        if s.hasPrefix("/") || s.hasPrefix("~/") || s.hasPrefix("./") { return false }    // path
        if s.allSatisfy({ $0.isNumber || ".,-+:".contains($0) }) { return false }          // number/date

        var lower = false, upper = false, digit = false, strongSymbol = false
        for c in s {
            if c.isLowercase { lower = true }
            else if c.isUppercase { upper = true }
            else if c.isNumber { digit = true }
            else if !"_-.".contains(c) { strongSymbol = true }   // _ - . are common in names/IDs
        }
        let classes = [lower, upper, digit, strongSymbol].filter { $0 }.count

        // Typical password: a real symbol plus at least two other kinds of character.
        if strongSymbol && classes >= 3 { return true }
        // Long random-looking token (no symbols) — but not something like "Report_2024.pdf".
        if classes >= 3 && s.count >= 16 && fileName.firstMatch(in: s, range: range) == nil { return true }
        return false
    }
}
