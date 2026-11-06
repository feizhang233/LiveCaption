import SwiftUI

enum AppPage: String, CaseIterable, Identifiable {
    case live = "即時字幕", media = "媒體播放", models = "模型管理", settings = "設定"
    var id: String { rawValue }
    var icon: String {
        switch self { case .live: "captions.bubble"; case .media: "play.rectangle"; case .models: "square.stack.3d.up"; case .settings: "slider.horizontal.3" }
    }
}

struct RootView: View {
    @Bindable var session: SessionController
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var page: AppPage? = .live
    @State private var importing = false
    @State private var exporting = false
    @State private var export = CaptionExport(captions: [], format: .srt)
    @State private var clearConfirmation = false

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                TabView(selection: $page) {
                    ForEach(AppPage.allCases) { destination in
                        Tab(destination.rawValue, systemImage: destination.icon, value: Optional(destination)) {
                            NavigationStack { destinationView(destination) }
                        }
                    }
                }
            } else {
                splitNavigation
            }
            #else
            splitNavigation
            #endif
        }
        .tint(CaptionTheme.accent)
        .preferredColorScheme(session.preferences.theme.scheme)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await session.openMedia(url); page = .media } }
            case .failure(let error): session.report(error.localizedDescription)
            }
        }
        .fileExporter(isPresented: $exporting, document: export.document, contentType: export.contentType, defaultFilename: export.filename) { result in
            if case .failure(let error) = result { session.report("匯出失敗：\(error.localizedDescription)") }
        }
        .confirmationDialog("清除目前的字幕歷史？尚未匯出的字幕將不再保留。", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("清除字幕歷史", role: .destructive) { Task { await session.clearHistory() } }
        }
    }

    private var splitNavigation: some View {
        NavigationSplitView {
            List(AppPage.allCases, selection: $page) { page in
                Label(page.rawValue, systemImage: page.icon).tag(page)
            }
            .navigationTitle("Live Caption")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                Label("本機辨識 · 原語言字幕", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            destinationView(page ?? .live)
        }
    }

    private func destinationView(_ destination: AppPage) -> some View {
        Group {
            switch destination {
            case .live: workspace(.live)
            case .media: workspace(.media)
            case .models: ModelsView(session: session)
            case .settings: SettingsView(session: session)
            }
        }
        .navigationTitle(destination.rawValue)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if destination == .media || destination == .live {
                    Button { importing = true } label: { Label("匯入媒體", systemImage: "folder.badge.plus") }
                        .accessibilityIdentifier("media.import")
                        .keyboardShortcut("o", modifiers: [.command])
                        .disabled(session.media.isLoading || session.isBusy)
                    Menu {
                        Button("匯出 SRT") { prepareExport(.srt) }
                        Button("匯出 TXT") { prepareExport(.text) }
                        if !session.alternatives.isEmpty {
                            Button("匯出其他結果 TXT") { prepareExport(.alternativeText) }
                        }
                        Divider()
                        Button("清除字幕歷史", role: .destructive) { clearConfirmation = true }
                            .disabled(session.phase == .running || session.isBusy)
                    } label: { Label("匯出字幕", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("captions.export")
                    .disabled(session.captions.isEmpty)
                }
            }
        }
    }

    private func workspace(_ mode: CaptionWorkspaceView.Mode) -> some View {
        #if os(iOS)
        CaptionWorkspaceView(session: session, mode: mode,
                             importMedia: { importing = true }, chooseModel: { page = .models },
                             showMedia: { page = .media })
        #else
        CaptionWorkspaceView(session: session, mode: mode,
                             importMedia: { importing = true }, chooseModel: { page = .models })
        #endif
    }

    private func prepareExport(_ format: CaptionExport.Format) {
        let captions = format == .alternativeText ? session.alternatives.map(\.caption) : session.captions
        export = CaptionExport(captions: captions, format: format)
        exporting = true
    }
}
