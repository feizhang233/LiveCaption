#if os(macOS)
import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Kept by the settings page so switching categories preserves unfinished input
/// and any permission request already in progress. Never persisted to disk.
@MainActor @Observable
final class CaptionScopeSettingsState {
    var applicationError: String?
    var websiteInput = ""
    var websiteError: String?
    var permissionRequest: String?
    var permissionMessage: String?
}

/// Shares the settings Form's scrolling and native control behavior.
struct CaptionScopeSettingsView: View {
    @Bindable var session: SessionController
    @Bindable var editing: CaptionScopeSettingsState
    @State private var runningApplications: [ScopeApplication] = []
    @State private var choosingApplication = false
    @FocusState private var websiteFocused: Bool

    var body: some View {
        @Bindable var scope = session.captionScope
        Group {
            Section("字幕啟用範圍") {
                Picker("產生字幕", selection: $scope.mode) {
                    ForEach(CaptionScopeMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Text("只套用於 Mac 的系統音訊。按「開始字幕」後，依目前前台 App 或網站自動暫停與繼續；手動暫停、停止後不會自動恢復。本機媒體播放不受影響。")
                    .font(.caption).foregroundStyle(.secondary)
                if scope.mode == .selected && scope.applications.isEmpty && scope.websites.isEmpty {
                    Label("尚未指定 App 或網站；新增後才會產生字幕。", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if scope.mode == .selected {
                applicationSection
                websiteSection
            }
        }
        .onAppear(perform: refreshApplications)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshApplications() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshApplications() }
        .fileImporter(isPresented: $choosingApplication, allowedContentTypes: [.applicationBundle], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { addApplication(at: url) }
            case .failure(let error):
                editing.applicationError = "無法選取 App：\(error.localizedDescription)"
            }
        }
    }

    private var applicationSection: some View {
        Section("指定 App") {
            ForEach(session.captionScope.applications) { application in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(application.name).fixedSize(horizontal: false, vertical: true)
                        Text(application.id).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("移除", systemImage: "minus.circle") {
                        session.captionScope.removeApplication(id: application.id)
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("移除 App：\(application.name)")
                    .help("移除 \(application.name)")
                }
            }
            AdaptiveControls(horizontalSpacing: 12, verticalSpacing: 10) {
                runningApplicationMenu
                applicationFileButton
                refreshApplicationsButton
            }
            Text("App 與網站符合其中一項就會啟用。加入瀏覽器 App，代表在該瀏覽器的所有網頁都啟用字幕。")
                .font(.caption).foregroundStyle(.secondary)
            if let applicationError = editing.applicationError {
                Label(applicationError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var runningApplicationMenu: some View {
        Menu("加入已開啟的 App", systemImage: "plus") {
            if runningApplications.isEmpty {
                Text("沒有可加入的 App")
            } else {
                ForEach(runningApplications) { application in
                    Button(application.name) {
                        let added = session.captionScope.addApplication(id: application.id, name: application.name)
                        editing.applicationError = added ? nil : "無法辨識這個 App。請使用「選擇其他 App」重新選取。"
                    }
                    .disabled(session.captionScope.applications.contains { $0.id == application.id })
                }
            }
        }
    }

    private var applicationFileButton: some View {
        Button("選擇其他 App…") { choosingApplication = true }
    }

    private var refreshApplicationsButton: some View {
        Button("重新整理 App", systemImage: "arrow.clockwise", action: refreshApplications)
            .labelStyle(.iconOnly).help("重新整理已開啟的 App")
    }

    private var websiteSection: some View {
        Section("指定網站") {
            ForEach(session.captionScope.websites, id: \.self) { website in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(website).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("移除", systemImage: "minus.circle") {
                        session.captionScope.removeWebsite(website)
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("移除網站：\(website)").help("移除 \(website)")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("網站網域", text: $editing.websiteInput, prompt: Text("例如 youtube.com"))
                    .textFieldStyle(.roundedBorder)
                    .focused($websiteFocused)
                    .onSubmit(addWebsite)
                    .onChange(of: editing.websiteInput) { _, _ in editing.websiteError = nil }
                    .accessibilityHint("輸入網域或網站首頁網址，不含路徑。")
                Button("加入網站", systemImage: "plus", action: addWebsite)
                    .disabled(editing.websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let websiteError = editing.websiteError {
                    Label(websiteError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("輸入網域或首頁網址；規則包含該網域與其子網域，例如 youtube.com 也包含 www.youtube.com。切換分頁、網站或 App 後會重新判斷。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            browserPermissions
        }
    }

    private var browserPermissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("網站判斷需要允許讀取瀏覽器目前的網址。網址只用於本機比對，不會保存瀏覽歷史；無法讀取時會保持暫停。")
                .font(.caption).foregroundStyle(.secondary)
            Menu {
                ForEach(ForegroundContextMonitor.supportedBrowsers) { browser in
                    Button("允許讀取 \(browser.name) 網址…") {
                        requestBrowserPermission(browser.bundleIdentifier, name: browser.name)
                    }
                    .disabled(!runningApplications.contains { $0.id == browser.bundleIdentifier })
                }
            } label: {
                Label("設定瀏覽器權限…", systemImage: "lock.shield")
            }
            .disabled(editing.permissionRequest != nil)
            Text("請先開啟要使用的瀏覽器。支援：\(ForegroundContextMonitor.supportedBrowsers.map(\.name).joined(separator: "、"))。")
                .font(.caption).foregroundStyle(.secondary)
            if editing.permissionRequest != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在確認瀏覽器權限…").font(.caption)
                }
            }
            if let permissionMessage = editing.permissionMessage {
                Text(permissionMessage).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshApplications() {
        var applications: [String: ScopeApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            applications[id] = ScopeApplication(id: id, name: app.localizedName ?? id)
        }
        runningApplications = applications.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func addApplication(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty else {
            editing.applicationError = "這個檔案不是可辨識的 App。請選擇「應用程式」中的 .app 檔案。"
            return
        }
        guard id != Bundle.main.bundleIdentifier else {
            editing.applicationError = "請選擇播放內容的 App；本機媒體播放不需要加入此清單。"
            return
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let added = session.captionScope.addApplication(id: id, name: name)
        editing.applicationError = added ? nil : "無法辨識這個 App。請選擇其他 App。"
    }

    private func addWebsite() {
        do {
            try session.captionScope.addWebsite(editing.websiteInput)
            editing.websiteInput = ""
            editing.websiteError = nil
        } catch {
            editing.websiteError = error.localizedDescription
        }
        websiteFocused = true
    }

    private func requestBrowserPermission(_ bundleIdentifier: String, name: String) {
        guard editing.permissionRequest == nil else { return }
        editing.permissionRequest = bundleIdentifier
        editing.permissionMessage = nil
        Task { @MainActor in
            let state = await session.foregroundMonitor.requestBrowserPermission(bundleIdentifier: bundleIdentifier)
            editing.permissionMessage = "\(name)：\(state.message)"
            editing.permissionRequest = nil
        }
    }
}
#endif
