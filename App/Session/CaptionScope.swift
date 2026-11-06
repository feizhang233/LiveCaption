import Foundation
import Observation

enum CaptionScopeMode: String, CaseIterable, Identifiable, Sendable {
    case always
    case selected

    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: "始終產生字幕"
        case .selected: "僅在指定 App／網站"
        }
    }
}

struct ScopeApplication: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

enum CaptionScopeError: LocalizedError {
    case invalidWebsite
    case websiteMustBeDomain

    var errorDescription: String? {
        switch self {
        case .invalidWebsite:
            "請輸入有效的網站網域，例如 youtube.com 或 https://youtube.com。"
        case .websiteMustBeDomain:
            "網站規則適用於整個網域及其子網域。請只輸入網域，不含頁面路徑、連接埠、查詢或帳號。"
        }
    }
}

/// Pure matching rules. The caller supplies a URL only when it has verified the
/// current foreground browser and read that browser's currently selected tab.
enum CaptionScopePolicy {
    static func allows(mode: CaptionScopeMode, applications: [ScopeApplication], websites: [String],
                       bundleIdentifier: String?, url: URL?) -> Bool {
        if mode == .always { return true }
        guard let bundleIdentifier else { return false }
        if applications.contains(where: { $0.id == bundleIdentifier }) { return true }
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = canonicalHost(url.host) else { return false }
        return websites.contains { rule in
            host == rule || (!isIPv4(rule) && host.hasSuffix("." + rule))
        }
    }

    /// Website rules are deliberately domain-wide. Never silently turn a
    /// pasted individual page URL into permission for every page on that site.
    static func normalizeWebsite(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("%"), !value.contains("\\"),
              !value.contains(where: { $0.isWhitespace }) else { throw CaptionScopeError.invalidWebsite }
        let candidate = value.contains("://") ? value : "https://" + value
        guard let url = URL(string: candidate), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = canonicalHost(url.host) else { throw CaptionScopeError.invalidWebsite }
        guard components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { throw CaptionScopeError.websiteMustBeDomain }
        return host
    }

    static func validApplication(_ application: ScopeApplication) -> Bool {
        !application.id.isEmpty && !application.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            application.id.utf8.allSatisfy { byte in
                (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) ||
                    byte == 45 || byte == 46 || byte == 95
            }
    }

    private static func canonicalHost(_ candidate: String?) -> String? {
        guard var host = candidate?.lowercased(), !host.isEmpty else { return nil }
        // A DNS trailing dot denotes the same fully-qualified hostname.
        if host.hasSuffix(".") { host.removeLast() }
        guard host.count <= 253 else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host == "localhost" || labels.count >= 2 else { return nil }
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { byte in
                    (97...122).contains(byte) || (48...57).contains(byte) || byte == 45
                }
        }) else { return nil }
        return host
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { part in
            part.allSatisfy(\.isNumber) && Int(part).map { (0...255).contains($0) } == true
        }
    }
}

/// Persisted independently of the recognition engine, so editing an allowlist
/// never clears the transcript or changes the selected source language.
@MainActor @Observable
final class CaptionScopePreferences {
    enum Keys {
        static let mode = "captionScope.mode"
        static let applications = "captionScope.applications"
        static let websites = "captionScope.websites"
    }

    var mode: CaptionScopeMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Keys.mode)
            onChange?()
        }
    }
    private(set) var applications: [ScopeApplication] {
        didSet {
            guard applications != oldValue else { return }
            if let data = try? JSONEncoder().encode(applications) { defaults.set(data, forKey: Keys.applications) }
            onChange?()
        }
    }
    private(set) var websites: [String] {
        didSet {
            guard websites != oldValue else { return }
            defaults.set(websites, forKey: Keys.websites)
            onChange?()
        }
    }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.mode) != nil {
            // A corrupt existing choice must not unexpectedly enable all apps.
            mode = defaults.string(forKey: Keys.mode).flatMap(CaptionScopeMode.init(rawValue:)) ?? .selected
        } else {
            mode = .always
        }
        let storedApps = defaults.data(forKey: Keys.applications)
            .flatMap { try? JSONDecoder().decode([ScopeApplication].self, from: $0) } ?? []
        var seenApps = Set<String>()
        applications = storedApps.filter { CaptionScopePolicy.validApplication($0) && seenApps.insert($0.id).inserted }
        var seenSites = Set<String>()
        websites = (defaults.stringArray(forKey: Keys.websites) ?? [])
            .compactMap { try? CaptionScopePolicy.normalizeWebsite($0) }
            .filter { seenSites.insert($0).inserted }
    }

    func allows(bundleIdentifier: String?, url: URL?) -> Bool {
        CaptionScopePolicy.allows(mode: mode, applications: applications, websites: websites,
                                  bundleIdentifier: bundleIdentifier, url: url)
    }

    @discardableResult
    func addApplication(id: String, name: String) -> Bool {
        let application = ScopeApplication(id: id, name: name)
        guard CaptionScopePolicy.validApplication(application) else { return false }
        if let index = applications.firstIndex(where: { $0.id == id }) {
            applications[index] = application
        } else {
            applications.append(application)
        }
        return true
    }

    func removeApplication(id: String) {
        applications.removeAll { $0.id == id }
    }

    @discardableResult
    func addWebsite(_ input: String) throws -> String {
        let website = try CaptionScopePolicy.normalizeWebsite(input)
        if !websites.contains(website) { websites.append(website) }
        return website
    }

    func removeWebsite(_ website: String) {
        websites.removeAll { $0 == website }
    }
}
