#if os(macOS)
import AppKit
import CoreServices
import Observation

enum BrowserPageState: Equatable, Sendable {
    case disabled, notSupported, checking, available, permissionRequired, permissionDenied, unavailable

    var message: String {
        switch self {
        case .disabled: "網頁判斷未啟用。"
        case .notSupported: "此 App 不支援讀取目前網頁，可改用應用程式規則。"
        case .checking: "正在確認目前網頁…"
        case .available: "已允許讀取目前網頁。"
        case .permissionRequired: "請先允許此瀏覽器的網頁存取權限。"
        case .permissionDenied: "網頁存取未獲允許。請在系統設定 → 隱私權與安全性 → 自動化中允許 Live Caption。"
        case .unavailable: "無法讀取網頁。請開啟瀏覽器及一般網頁後重試。"
        }
    }
}

struct ForegroundContext: Equatable, Sendable {
    var appBundleIdentifier: String?
    var appName: String?
    var pageURL: URL?
    var pageState: BrowserPageState

    static let unavailable = ForegroundContext(pageState: .unavailable)
}

struct SupportedBrowser: Identifiable, Sendable {
    let bundleIdentifier: String
    let name: String
    fileprivate let currentTabProperty: AEKeyword
    fileprivate let urlProperty: AEKeyword
    var id: String { bundleIdentifier }
}

/// Reads only the front application's identity and, when requested, its active page URL.
/// No page contents are read, no browser is launched, and URLs are never persisted.
@MainActor @Observable
final class ForegroundContextMonitor {
    // Safari's installed Safari.sdef and Chromium's scripting.sdef define these codes.
    // Keep this explicit allowlist in sync with the sandbox Apple Events entitlement.
    static let supportedBrowsers: [SupportedBrowser] = [
        .init(bundleIdentifier: "com.apple.Safari", name: "Safari", currentTabProperty: code("cTab"), urlProperty: code("pURL")),
        .init(bundleIdentifier: "com.google.Chrome", name: "Google Chrome", currentTabProperty: code("acTa"), urlProperty: code("URL ")),
        .init(bundleIdentifier: "com.microsoft.edgemac", name: "Microsoft Edge", currentTabProperty: code("acTa"), urlProperty: code("URL ")),
        .init(bundleIdentifier: "com.brave.Browser", name: "Brave", currentTabProperty: code("acTa"), urlProperty: code("URL "))
    ]

    var readsBrowserURL = false {
        didSet {
            guard readsBrowserURL != oldValue else { return }
            revision &+= 1
            currentProcessID = nil
            refresh()
        }
    }
    private(set) var context = ForegroundContext.unavailable
    @ObservationIgnored private var onChange: ((ForegroundContext) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var currentProcessID: pid_t?
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var readInFlight = false
    @ObservationIgnored private var sessionActive = true
    @ObservationIgnored private var running = false
    @ObservationIgnored private let reader = BrowserPageReader()
    @ObservationIgnored private let notificationCenter = NSWorkspace.shared.notificationCenter

    deinit {
        pollTask?.cancel()
        observers.forEach(notificationCenter.removeObserver)
    }

    func start(onChange: @escaping (ForegroundContext) -> Void) {
        self.onChange = onChange
        guard !running else { onChange(context); refresh(); return }
        running = true
        sessionActive = true
        let center = notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSessionActive(false) }
            })
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSessionActive(true) }
            })
        }
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        running = false
        revision &+= 1
        pollTask?.cancel()
        pollTask = nil
        let center = notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        currentProcessID = nil
        publish(.unavailable)
        onChange = nil
    }

    /// Permission is requested only by an explicit settings action, never by polling.
    /// Selecting a browser that isn't already running does not launch it.
    func requestBrowserPermission(bundleIdentifier: String) async -> BrowserPageState {
        guard Self.supportedBrowsers.contains(where: { $0.bundleIdentifier == bundleIdentifier }),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              !app.isTerminated else { return .unavailable }
        let result = await reader.requestPermission(processID: app.processIdentifier)
        refresh()
        return result
    }

    func refresh() {
        guard running, sessionActive else { return }
        guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated else {
            revision &+= 1
            currentProcessID = nil
            publish(.unavailable)
            return
        }
        let browser = Self.supportedBrowsers.first { $0.bundleIdentifier == app.bundleIdentifier }
        let pid = app.processIdentifier
        let identityChanged = currentProcessID != pid
        if identityChanged {
            revision &+= 1
            currentProcessID = pid
        }
        let base = ForegroundContext(appBundleIdentifier: app.bundleIdentifier, appName: app.localizedName,
                                     pageState: !readsBrowserURL ? .disabled : browser == nil ? .notSupported : .checking)
        // Immediately revoke the old page on app activation; a delayed reply cannot
        // restore it after a focus switch, stop, or policy change.
        if identityChanged || !readsBrowserURL || browser == nil { publish(base) }
        guard readsBrowserURL, let browser, !readInFlight else { return }
        readInFlight = true
        let expectedRevision = revision
        Task { [weak self, reader] in
            let result = await reader.read(processID: pid, browser: browser)
            guard let self else { return }
            self.readInFlight = false
            guard self.running, self.sessionActive, self.readsBrowserURL,
                  self.revision == expectedRevision,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                self.refresh()
                return
            }
            self.publish(ForegroundContext(appBundleIdentifier: base.appBundleIdentifier,
                                           appName: base.appName, pageURL: result.url, pageState: result.state))
        }
    }

    private func setSessionActive(_ active: Bool) {
        sessionActive = active
        revision &+= 1
        currentProcessID = nil
        if active { refresh() } else { publish(.unavailable) }
    }

    private func publish(_ next: ForegroundContext) {
        guard next != context else { return }
        context = next
        onChange?(next)
    }

    private static func code(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

/// Apple Events are synchronous, so the bounded read runs off the main actor. There
/// is at most one queued read per monitor; permission prompts use a separate queue.
private final class BrowserPageReader: @unchecked Sendable {
    struct Result: Sendable { let url: URL?; let state: BrowserPageState }
    private let queue = DispatchQueue(label: "LiveCaption.foreground-page", qos: .utility)
    private let permissionQueue = DispatchQueue(label: "LiveCaption.browser-permission", qos: .userInitiated)

    func requestPermission(processID: pid_t) async -> BrowserPageState {
        await withCheckedContinuation { continuation in
            permissionQueue.async {
                let target = NSAppleEventDescriptor(processIdentifier: processID)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), true)
                continuation.resume(returning: Self.state(for: status))
            }
        }
    }

    func read(processID: pid_t, browser: SupportedBrowser) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.readSynchronously(processID: processID, browser: browser))
            }
        }
    }

    private static func readSynchronously(processID: pid_t, browser: SupportedBrowser) -> Result {
        let target = NSAppleEventDescriptor(processIdentifier: processID)
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), false)
        guard permission == noErr else { return Result(url: nil, state: state(for: permission)) }
        let window = object(want: DescType(cWindow), form: OSType(formAbsolutePosition),
                            selection: NSAppleEventDescriptor(int32: 1), container: .null())
        let tab = property(browser.currentTabProperty, of: window)
        let url = property(browser.urlProperty, of: tab)
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
                                          targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(url, forKeyword: AEKeyword(keyDirectObject))
        // The send itself also suppresses permission prompts, closing the race
        // between preflight and send if permission changes in System Settings.
        let options: NSAppleEventDescriptor.SendOptions = [.waitForReply, .neverInteract,
            .init(rawValue: UInt(kAEDoNotPromptForUserConsent))]
        do {
            let reply = try event.sendEvent(options: options, timeout: 0.6)
            let errorNumber = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0
            guard errorNumber == 0 else { return Result(url: nil, state: state(for: errorNumber)) }
            guard let text = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
                  let resultURL = URL(string: text),
                  let scheme = resultURL.scheme?.lowercased(), ["https", "http"].contains(scheme),
                  resultURL.host != nil else { return Result(url: nil, state: .unavailable) }
            return Result(url: resultURL, state: .available)
        } catch {
            return Result(url: nil, state: state(for: OSStatus((error as NSError).code)))
        }
    }

    private static func state(for status: OSStatus) -> BrowserPageState {
        switch status {
        case noErr: .available
        case OSStatus(errAEEventWouldRequireUserConsent): .permissionRequired
        case OSStatus(errAEEventNotPermitted): .permissionDenied
        default: .unavailable
        }
    }

    private static func property(_ code: AEKeyword, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object(want: DescType(cProperty), form: OSType(formPropertyID),
               selection: NSAppleEventDescriptor(typeCode: code), container: container)
    }

    private static func object(want: DescType, form: OSType, selection: NSAppleEventDescriptor,
                               container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let descriptor = NSAppleEventDescriptor.record()
        descriptor.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: AEKeyword(keyAEDesiredClass))
        descriptor.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        descriptor.setDescriptor(selection, forKeyword: AEKeyword(keyAEKeyData))
        descriptor.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return descriptor.coerce(toDescriptorType: DescType(typeObjectSpecifier))!
    }
}
#endif
