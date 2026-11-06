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
        var session: SessionController? = SessionController(models: models, defaults: defaults)
        try check(session!.language == "ja", "First launch default")
        session!.language = " EN "
        try check(session!.language == "en", "Normalize selected English code")
        session = nil
        session = SessionController(models: models, defaults: defaults)
        try check(session!.language == "en", "Restore English after a new controller")
        session!.language = "zh"
        session = nil
        session = SessionController(models: models, defaults: defaults)
        try check(session!.language == "zh", "Restore Chinese after a new controller")
        try check(SourceLanguageCatalog.engineLanguage(for: session!.language) == "zh", "Pass Mandarin source code to the engine")
        session!.language = "auto"
        session = nil
        session = SessionController(models: models, defaults: defaults)
        try check(session!.language == "auto" && SourceLanguageCatalog.engineLanguage(for: session!.language) == nil, "Restore automatic source detection")
        defaults.set("invalid-source-code", forKey: "sourceLanguageCode")
        session = SessionController(models: models, defaults: defaults)
        try check(session!.language == "ja", "Corrupted persisted language falls back safely")
        session!.language = "fr"
        try check(SourceLanguageCatalog.engineLanguage(for: session!.language) == "fr", "Existing French remains available")
        await session!.stop()
        print("PASS: complete language catalog; English/Chinese/auto preference persistence; normalization; invalid-state recovery; original languages retained")
    }
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
