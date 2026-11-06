import Foundation

@main struct CaptionScopeChecks {
    @MainActor static func main() throws {
        let suite = "LiveCaption.CaptionScopeChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var checks = 0
        func check(_ condition: Bool, _ message: String) throws {
            checks += 1
            if !condition { throw Failure(message: message) }
        }
        func rejected(_ value: String) -> Bool {
            do { _ = try CaptionScopePolicy.normalizeWebsite(value); return false }
            catch { return true }
        }

        let scope = CaptionScopePreferences(defaults: defaults)
        try check(scope.mode == .always && scope.allows(bundleIdentifier: nil, url: nil), "First launch preserves continuous captions")
        var notifications = 0
        scope.onChange = { notifications += 1 }
        scope.mode = .selected
        try check(!scope.allows(bundleIdentifier: "com.apple.Safari", url: URL(string: "https://example.com")), "Empty selected rules block")
        try check(!scope.allows(bundleIdentifier: nil, url: nil), "Unknown foreground app blocks")
        try scope.addWebsite("  HTTPS://Example.COM/  ")
        try check(scope.websites == ["example.com"], "Normalize case, URL root and whitespace")
        try scope.addWebsite("example.com.")
        try check(scope.websites.count == 1 && notifications == 2, "Duplicate site does not persist or notify twice")
        try check(scope.allows(bundleIdentifier: "com.apple.Safari", url: URL(string: "https://example.com/watch?v=1")), "All pages under an allowed host")
        try check(scope.allows(bundleIdentifier: "com.apple.Safari", url: URL(string: "http://video.example.com/film")), "True subdomain allowed")
        try check(!scope.allows(bundleIdentifier: "com.apple.Safari", url: URL(string: "https://notexample.com")), "Hostname suffix without dot is denied")
        try check(!scope.allows(bundleIdentifier: "com.apple.Safari", url: URL(string: "https://example.com.evil.test")), "Allowed domain in attack hostname is denied")
        try check(!scope.allows(bundleIdentifier: "com.apple.Safari", url: URL(string: "https://example.com@evil.test")), "Allowed domain in URL userinfo does not match")
        try check(!scope.allows(bundleIdentifier: "com.apple.Safari", url: URL(string: "file://example.com/movie")), "Non-web URL denied")
        try check(!scope.allows(bundleIdentifier: "com.apple.Safari", url: nil), "Unreadable browser URL fails closed")
        try check(!scope.allows(bundleIdentifier: nil, url: URL(string: "https://example.com")), "A URL without a foreground app is insufficient")
        try check(!scope.allows(bundleIdentifier: "com.example.Player", url: nil), "Unselected non-browser denied")

        scope.addApplication(id: "com.example.Player", name: "Player")
        try check(scope.allows(bundleIdentifier: "com.example.Player", url: nil), "Selected app works without a URL")
        try check(!scope.allows(bundleIdentifier: "com.example.Player.Helper", url: nil), "Application ID must match exactly")
        scope.addApplication(id: "com.apple.Safari", name: "Safari")
        try check(scope.allows(bundleIdentifier: "com.apple.Safari", url: nil), "Explicit browser app selection overrides URL unavailability")
        try check(scope.allows(bundleIdentifier: "com.apple.Safari", url: URL(string: "https://unlisted.test")), "Explicit browser app selection allows all of that app")
        scope.addApplication(id: "com.apple.Safari", name: "Safari")
        try check(scope.applications.count == 2 && notifications == 4, "Duplicate app does not persist or notify twice")
        try check(!scope.addApplication(id: "bad id", name: "Invalid"), "Invalid app identity rejected")

        let restored = CaptionScopePreferences(defaults: defaults)
        try check(restored.mode == .selected && restored.applications == scope.applications && restored.websites == scope.websites, "Restore selected mode and both allowlists")
        restored.removeApplication(id: "com.apple.Safari")
        restored.removeWebsite("example.com")
        let removed = CaptionScopePreferences(defaults: defaults)
        try check(removed.websites.isEmpty && removed.applications.count == 1, "Removal persists")
        removed.mode = .always
        try check(CaptionScopePreferences(defaults: defaults).mode == .always, "Continuous choice persists")

        try check(try CaptionScopePolicy.normalizeWebsite("https://例え.jp") == "xn--r8jz45g.jp", "Unicode domains normalize to browser IDNA")
        try check(try CaptionScopePolicy.normalizeWebsite("localhost") == "localhost", "Local development host accepted")
        for invalid in ["", " ", "example.com/watch", "https://example.com/?v=1", "https://example.com/#video", "https://example.com:8000", "https://user@example.com", "https://user:secret@example.com", "ftp://example.com", "*.example.com", "https://evil.test\\@example.com", "https://ex ample.com", "https://foo%2Eexample.com", "https://-example.com", "https://example..com", "https://example.com//", "com"] {
            try check(rejected(invalid), "Invalid or overbroad website rule rejected: \(invalid)")
        }
        defaults.set("corrupt-mode", forKey: CaptionScopePreferences.Keys.mode)
        defaults.set(Data("broken-json".utf8), forKey: CaptionScopePreferences.Keys.applications)
        defaults.set(["EXAMPLE.com", "example.com", "https://bad.test/path", ""], forKey: CaptionScopePreferences.Keys.websites)
        let repaired = CaptionScopePreferences(defaults: defaults)
        try check(repaired.mode == .selected && repaired.applications.isEmpty && repaired.websites == ["example.com"], "Corrupt settings fail closed; sanitize and deduplicate rules")
        defaults.set(Data([0, 1]), forKey: CaptionScopePreferences.Keys.mode)
        try check(CaptionScopePreferences(defaults: defaults).mode == .selected, "Wrong persisted mode type also fails closed")
        print("PASS: \(checks) foreground scope checks; exact app identity, domain boundaries, invalid input, persistence, callbacks and fail-closed recovery")
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
