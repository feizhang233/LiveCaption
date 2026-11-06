import CaptionCore
import Foundation

@main struct SourceLanguagePreferencesChecks {
    @MainActor static func main() async throws {
        let suite = "LiveCaption.SourceLanguageChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let models = ModelStore(storageURL: directory, defaults: defaults)
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw Failure(message: message) }
        }
        try check(SourceLanguageCatalog.preferred.map(\.code) == ["ja", "fr", "en", "zh"], "Preferred source languages")
        try check(Set(SourceLanguageCatalog.all.map(\.code)).count == SourceLanguageCatalog.all.count, "No duplicate choices")
        try check(SourceLanguageCatalog.all.count == WhisperEngine.supportedLanguages.count + 1, "Retain every engine language plus auto")

        // Session settings must use the injected store too, rather than reading
        // or mutating the running app's standard preferences during a test.
        let preferenceKeys: Set<String> = [
            "theme", "captionFontSize", "captionLines", "captionInk", "captionTypeface", "captionBackground", "captionOpacity",
            "captionHideFillerWords", "captionAutoShowOverlay", "captionSource", "sourceLanguageCode"
        ]
        func standardPreferences() -> NSDictionary {
            NSDictionary(dictionary: UserDefaults.standard.dictionaryRepresentation().filter { preferenceKeys.contains($0.key) })
        }
        let originalStandardPreferences = standardPreferences()
        let initialPreferences = AppPreferences(defaults: defaults)
        try check(!initialPreferences.hideFillerWords && initialPreferences.autoShowOverlay,
                  "First launch keeps original words and automatically shows desktop captions")
        defaults.set(AppTheme.dark.rawValue, forKey: "theme")
        defaults.set(41.0, forKey: "captionFontSize")
        defaults.set(5, forKey: "captionLines")
        defaults.set(CaptionInk.cyan.rawValue, forKey: "captionInk")
        defaults.set(CaptionTypeface.serif.rawValue, forKey: "captionTypeface")
        defaults.set(CaptionBackground.glass.rawValue, forKey: "captionBackground")
        defaults.set(0.6, forKey: "captionOpacity")
        defaults.set(true, forKey: "captionHideFillerWords")
        defaults.set(false, forKey: "captionAutoShowOverlay")
        var session: SessionController? = SessionController(models: models, defaults: defaults, monitorForeground: false)
        let preferences = session!.preferences
        try check(preferences.theme == .dark && preferences.fontSize == 41 && preferences.lineCount == 5 &&
                  preferences.ink == .cyan && preferences.typeface == .serif && preferences.background == .glass && preferences.opacity == 0.6,
                  "All session appearance settings load from injected preferences")
        try check(preferences.hideFillerWords && !preferences.autoShowOverlay,
                  "Caption display and automatic floating preferences load from the injected store")
        preferences.theme = .light
        preferences.fontSize = 48
        preferences.lineCount = 4
        preferences.ink = .yellow
        preferences.typeface = .rounded
        preferences.background = .solid
        preferences.opacity = 0.8
        preferences.hideFillerWords = false
        preferences.autoShowOverlay = true
        let restoredPreferences = AppPreferences(defaults: defaults)
        try check(restoredPreferences.theme == .light && restoredPreferences.fontSize == 48 && restoredPreferences.lineCount == 4 &&
                  restoredPreferences.ink == .yellow && restoredPreferences.typeface == .rounded &&
                  restoredPreferences.background == .solid && restoredPreferences.opacity == 0.8,
                  "Appearance edits persist only to the injected preferences")
        try check(!restoredPreferences.hideFillerWords && restoredPreferences.autoShowOverlay,
                  "Caption display and automatic floating edits persist, including explicit false")
        #if os(macOS)
        try check(session!.source == .system, "First Mac launch defaults to system audio")
        session!.source = .media
        session = nil
        session = SessionController(models: models, defaults: defaults, monitorForeground: false)
        try check(session!.source == .media, "Mac remembers the selected local media source")
        session!.source = .system
        session = nil
        session = SessionController(models: models, defaults: defaults, monitorForeground: false)
        try check(session!.source == .system, "Mac remembers the selected system audio source")
        defaults.set("invalid-caption-source", forKey: "captionSource")
        session = SessionController(models: models, defaults: defaults, monitorForeground: false)
        try check(session!.source == .system, "Corrupted Mac source safely falls back to system audio")
        #endif
        try check(session!.language == "ja", "First launch default")
        session!.language = " EN "
        try check(session!.language == "en", "Normalize selected English code")
        session = nil
        session = SessionController(models: models, defaults: defaults, monitorForeground: false)
        try check(session!.language == "en", "Restore English after a new controller")
        session!.language = "zh"
        session = nil
        session = SessionController(models: models, defaults: defaults, monitorForeground: false)
        try check(session!.language == "zh", "Restore Chinese after a new controller")
        try check(SourceLanguageCatalog.engineLanguage(for: session!.language) == "zh", "Pass Mandarin source code to the engine")
        session!.language = "auto"
        session = nil
        session = SessionController(models: models, defaults: defaults, monitorForeground: false)
        try check(session!.language == "auto" && SourceLanguageCatalog.engineLanguage(for: session!.language) == nil, "Restore automatic source detection")
        defaults.set("invalid-source-code", forKey: "sourceLanguageCode")
        session = SessionController(models: models, defaults: defaults, monitorForeground: false)
        try check(session!.language == "ja", "Corrupted persisted language falls back safely")
        session!.language = "fr"
        try check(SourceLanguageCatalog.engineLanguage(for: session!.language) == "fr", "Existing French remains available")

        // Exercise the App's display projection with real CaptionSegment values,
        // including temporary text, while keeping the export source immutable.
        let earlier = CaptionSegment(start: 0, end: 1, text: "Previous sentence.")
        let spoken = CaptionSegment(start: 2, end: 4, text: "Um, I feel well.")
        let fillerOnly = CaptionSegment(start: 5, end: 6, text: "Uh, um…")
        let originalCaptions = [earlier, spoken, fillerOnly]
        let originalTXT = CaptionExporter.txt(originalCaptions)
        let originalSRT = CaptionExporter.srt(originalCaptions)
        session!.language = "en"
        session!.preferences.hideFillerWords = false
        try check(session!.displayText(for: spoken) == spoken.text, "Disabled filtering shows original text")
        session!.preferences.hideFillerWords = true
        try check(session!.displayText(for: spoken) == "I feel well.", "Session display uses the selected language and preserves meaningful words")
        try check(session!.displayText(for: fillerOnly).isEmpty, "Filler-only display is empty, not replaced with another cue")
        let temporary = CaptionSegment(start: 7, end: 8, text: "Um, still speaking", isFinal: false)
        try check(session!.displayText(for: temporary) == "still speaking", "Temporary caption display uses the same filter")
        for (language, raw, expected) in [("ja", "えっと、始めます。", "始めます。"),
                                          ("fr", "Euh, bonjour.", "bonjour."),
                                          ("zh", "嗯，我知道。", "我知道。") ] {
            session!.language = language
            try check(session!.displayText(for: CaptionSegment(start: 0, end: 1, text: raw)) == expected,
                      "Display filtering follows explicit \(language) selection")
        }
        for language in ["auto", "de"] {
            session!.language = language
            try check(session!.displayText(for: spoken) == spoken.text,
                      "Automatic and unsupported filter languages leave the caption unchanged: \(language)")
        }
        session!.language = "en"
        session!.preferences.hideFillerWords = false
        try check(session!.displayText(for: spoken) == spoken.text && session!.displayText(for: fillerOnly) == fillerOnly.text,
                  "Turning filtering off immediately restores every original word")
        try check(originalCaptions == [earlier, spoken, fillerOnly] &&
                  CaptionExporter.txt(originalCaptions) == originalTXT && CaptionExporter.srt(originalCaptions) == originalSRT &&
                  originalTXT.contains(spoken.text) && originalTXT.contains(fillerOnly.text) &&
                  originalSRT.contains("00:00:05,000 --> 00:00:06,000\nUh, um…"),
                  "Display filtering preserves original caption values, timestamps, TXT and SRT, including filler-only cues")
        try check(originalStandardPreferences.isEqual(standardPreferences()),
                  "All session checks leave the running app's standard appearance, source and language preferences untouched")
        await session!.stop()
        print("PASS: complete language catalog; language/source persistence; normalization; invalid-state recovery; isolated appearance/filler/automatic floating preferences; session display filter toggling; filler-only empty display; original TXT/SRT preserved; standard preferences untouched")
    }
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
