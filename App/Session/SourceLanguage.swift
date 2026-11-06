import Foundation
import CaptionCore

/// A source-language choice, shared by preference validation and the picker.
struct SourceLanguage: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    var id: String { code }
}

enum SourceLanguageCatalog {
    static let defaultCode = "ja"
    static let automatic = SourceLanguage(code: "auto", name: "自動偵測")

    // Read the pinned engine's list once. The four preferred languages only
    // affect presentation order; all other engine languages remain available.
    private static let supported = WhisperEngine.supportedLanguages
    static let preferred: [SourceLanguage] = [
        SourceLanguage(code: "ja", name: "日本語"),
        SourceLanguage(code: "fr", name: "Français"),
        SourceLanguage(code: "en", name: "English"),
        SourceLanguage(code: "zh", name: "中文（普通話）")
    ].filter { supported[$0.code] != nil }

    static let other: [SourceLanguage] = {
        let preferredCodes = Set(preferred.map(\.code))
        return supported.keys.sorted().filter { !preferredCodes.contains($0) }
            .map { SourceLanguage(code: $0, name: supported[$0]!.capitalized) }
    }()

    static let all = preferred + [automatic] + other

    /// Persist engine language codes, not translated labels or locale IDs.
    /// For example, " EN " is accepted as "en"; unsupported values are rejected.
    static func normalizedCode(_ candidate: String?) -> String? {
        guard let code = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              code == automatic.code || supported[code] != nil else { return nil }
        return code
    }

    static func validatedCode(_ candidate: String?) -> String {
        normalizedCode(candidate) ?? defaultCode
    }

    /// nil asks Whisper to detect the language and still transcribe the source.
    /// Chinese uses Whisper's "zh" code. This app does not convert the written
    /// script; Whisper does not guarantee simplified/traditional output or all
    /// Chinese dialects. This choice is presented to users as Mandarin.
    static func engineLanguage(for code: String) -> String? {
        let valid = validatedCode(code)
        return valid == automatic.code ? nil : valid
    }
}
