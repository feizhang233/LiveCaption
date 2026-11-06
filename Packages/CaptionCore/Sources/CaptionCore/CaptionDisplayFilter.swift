import Foundation

/// Optional presentation-only filtering. Keep the original CaptionSegment for
/// history storage and exports: hesitation words can carry meaning in context.
public enum CaptionDisplayFilter {
    /// Removes a small set of hesitation tokens only when explicitly separated
    /// by whitespace or punctuation. Unknown/automatic languages are unchanged;
    /// for example, English “um” is a meaningful German preposition.
    /// An empty result means the current cue contains only these fillers.
    public static func text(_ text: String, language: String?, hideFillers: Bool) -> String {
        guard hideFillers, let language = supportedLanguage(language) else { return text }
        let pieces = split(text)
        let removed = Set(pieces.indices.filter { !pieces[$0].separator && isFiller(pieces[$0].text, language: language) })
        guard !removed.isEmpty else { return text }
        let kept = pieces.indices.filter { !pieces[$0].separator && !removed.contains($0) }
        guard let first = kept.first, let last = kept.last else { return "" }

        func joined(_ range: Range<Int>) -> String { pieces[range].map(\.text).joined() }
        func containsRemoved(_ range: Range<Int>) -> Bool { range.contains { removed.contains($0) } }
        var result = containsRemoved(0..<first) ? "" : joined(0..<first)
        result += pieces[first].text
        for (left, right) in zip(kept, kept.dropFirst()) {
            let between = (left + 1)..<right
            if containsRemoved(between) {
                result += punctuation(in: pieces[between])
                // Preserve word boundaries in Latin scripts; Japanese/Chinese
                // do not acquire artificial spaces when a filler is removed.
                if language == "en" || language == "fr" || pieces[between].contains(where: { $0.text.contains(where: \.isWhitespace) }) {
                    result += " "
                }
            } else {
                result += joined(between)
            }
            result += pieces[right].text
        }
        let suffix = (last + 1)..<pieces.endIndex
        result += containsRemoved(suffix) ? punctuation(in: pieces[suffix]) : joined(suffix)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Piece {
        var text: String
        let separator: Bool
    }

    // Quotes, apostrophes, parentheses and hyphens deliberately are not
    // boundaries. Quoted vocabulary and compounds must not be silently edited.
    private static let separators = Set<Character>(",，、.。!?！？…:：;；")
    private static let softPunctuation = Set<Character>(",，、…")
    private static let expressions: [String: NSRegularExpression] = [
        "en": "(?:u+h+|u+m+|uhm+|h+m{2,}|erm+)",
        "fr": "(?:euh+|heu+h*)",
        "ja": "(?:え[ー〜～]+と?|あの[ー〜～]+|あ[ー〜～]+|う[ー〜～]+ん)"
    ].compactMapValues { try? NSRegularExpression(pattern: "\\A(?:" + $0 + ")\\z") }

    private static func split(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        for character in text {
            let separator = character.isWhitespace || separators.contains(character)
            if pieces.last?.separator == separator {
                pieces[pieces.count - 1].text.append(character)
            } else {
                pieces.append(Piece(text: String(character), separator: separator))
            }
        }
        return pieces
    }

    private static func supportedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let base = language.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        guard let base, ["en", "fr", "ja", "zh"].contains(base) else { return nil }
        return base
    }

    private static func isFiller(_ word: String, language: String) -> Bool {
        let word = word.lowercased()
        switch language {
        case "en", "fr":
            return matches(word, language: language)
        case "ja":
            // Do not remove はい, うん, まあ, or the demonstrative あの.
            return ["えっと", "ええっと", "ええと", "あのう"].contains(word)
                || matches(word, language: language)
        case "zh":
            // Keep 啊/呢/吧 in sentences, 那個, 就是, and Cantonese 唔.
            return word == "嗯" || word == "呃"
        default:
            return false
        }
    }

    private static func matches(_ word: String, language: String) -> Bool {
        expressions[language]?.firstMatch(in: word, range: NSRange(word.startIndex..<word.endIndex, in: word)) != nil
    }

    private static func punctuation(in pieces: ArraySlice<Piece>) -> String {
        for piece in pieces where piece.separator {
            let punctuation = piece.text.filter { !$0.isWhitespace && !softPunctuation.contains($0) }
            // Ellipses belong to the hesitation; retain an actual sentence stop.
            if punctuation.count > 1 && punctuation.allSatisfy({ $0 == "." }) { continue }
            if !punctuation.isEmpty { return punctuation }
        }
        return ""
    }
}
