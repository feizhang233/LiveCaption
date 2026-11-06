import AVKit
import CaptionCore
import SwiftUI
import UniformTypeIdentifiers

enum AppPage: String, CaseIterable, Identifiable {
    case live = "即時字幕", media = "媒體播放", models = "模型管理", settings = "設定"
    var id: String { rawValue }
    var icon: String {
        switch self { case .live: "captions.bubble"; case .media: "play.rectangle"; case .models: "square.stack.3d.up"; case .settings: "slider.horizontal.3" }
    }
}

struct RootView: View {
    @Bindable var session: SessionController
    @State private var page: AppPage? = .live
    @State private var importing = false
    @State private var exporting = false
    @State private var document = CaptionDocument(text: "")
    @State private var exportName = "字幕.srt"
    @State private var exportType = CaptionDocument.subRipType
    @State private var clearConfirmation = false
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var isCommittingSeek = false

    var body: some View {
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
            Group {
                switch page ?? .live {
                case .live: livePage
                case .media: mediaPage
                case .models: ModelsView(session: session)
                case .settings: SettingsView(session: session)
                }
            }
            .navigationTitle((page ?? .live).rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if page == .media || page == .live {
                        Button { importing = true } label: { Label("匯入媒體", systemImage: "folder.badge.plus") }
                            .keyboardShortcut("o", modifiers: [.command])
                            .disabled(session.media.isLoading || session.isBusy)
                        Menu {
                            Button("匯出 SRT") { prepareExport(srt: true) }
                            Button("匯出 TXT") { prepareExport(srt: false) }
                            if !session.alternatives.isEmpty {
                                Button("匯出其他結果 TXT") { prepareAlternativeExport() }
                            }
                            Divider()
                            Button("清除字幕歷史", role: .destructive) { clearConfirmation = true }
                                .disabled(session.phase == .running || session.isBusy)
                        } label: { Label("匯出字幕", systemImage: "square.and.arrow.up") }
                        .disabled(session.captions.isEmpty)
                    }
                }
            }
        }
        .tint(CaptionTheme.accent)
        .preferredColorScheme(session.preferences.theme.scheme)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await session.openMedia(url); page = .media } }
            case .failure(let error): session.report(error.localizedDescription)
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: exportName) { result in
            if case .failure(let error) = result { session.report("匯出失敗：\(error.localizedDescription)") }
        }
        .confirmationDialog("清除目前的字幕歷史？尚未匯出的字幕將不再保留。", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("清除字幕歷史", role: .destructive) { Task { await session.clearHistory() } }
        }
    }

    private var livePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sourceControls
                CaptionStage(session: session)
                SessionControls(session: session)
                StatusStrip(session: session)
                if !session.hasReadyModel { modelPrompt }
                #if os(macOS)
                overlayControls
                #else
                Label("iPad 目前支援 App 內媒體。跨 App 收音與畫中畫仍在實機可行性驗證中。", systemImage: "ipad")
                    .font(.callout).foregroundStyle(.secondary)
                #endif
                Divider()
                TranscriptHistory(session: session)
            }
            .padding(24)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
    }

    private var mediaPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if session.media.isReady {
                    Text(session.media.title ?? "").font(.headline).lineLimit(2)
                    NativePlayerView(player: session.media.player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(minHeight: 180, maxHeight: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Text(timecode(displayedPlayhead)).monospacedDigit()
                        Slider(value: Binding(get: { displayedPlayhead }, set: { scrubPosition = $0 }),
                               in: 0...max(1, session.media.duration), onEditingChanged: scrubEditingChanged)
                            .accessibilityLabel("播放位置")
                            .accessibilityValue(timecode(displayedPlayhead))
                            .disabled(session.isBusy || session.media.isLoading || isCommittingSeek)
                        Text(timecode(session.media.duration)).monospacedDigit()
                    }.font(.caption)
                    CaptionStage(session: session)
                    sourceControls
                    SessionControls(session: session)
                    StatusStrip(session: session)
                    if !session.hasReadyModel { modelPrompt }
                    TranscriptHistory(session: session)
                } else {
                    ContentUnavailableView {
                        Label("開啟一段影片或音訊", systemImage: "play.rectangle.on.rectangle")
                    } description: {
                        Text("匯入本機檔案，一邊播放，一邊產生原語言字幕。檔案不會上傳。")
                    } actions: {
                        Button("選擇媒體檔案") { importing = true }.buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 300)
                    if session.media.isLoading { ProgressView("正在讀取音軌…") }
                    StatusStrip(session: session)
                }
            }
            .padding(24)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
    }

    private var sourceControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { sourcePicker; languagePicker }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 12) { sourcePicker; languagePicker }
        }
    }
    private var sourcePicker: some View {
        Picker("音訊來源", selection: Binding(get: { session.source }, set: { value in Task { await session.changeSource(value) } })) {
            ForEach(CaptionSource.allCases) { source in Text(source.rawValue).tag(source) }
        }.disabled(session.isBusy).frame(maxWidth: 260)
    }
    private var languagePicker: some View {
        Picker("來源語言", selection: $session.language) {
            ForEach(SourceLanguageCatalog.preferred) { language in
                Text(language.name).tag(language.code)
            }
            Text(SourceLanguageCatalog.automatic.name).tag(SourceLanguageCatalog.automatic.code)
            Divider()
            ForEach(SourceLanguageCatalog.other) { language in
                Text(language.name).tag(language.code)
            }
        }.disabled(session.phase == .running || session.isBusy).frame(maxWidth: 260)
    }
    private var modelPrompt: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { modelGuidance; chooseModelButton }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 10) { modelGuidance; chooseModelButton }
        }
    }
    private var modelGuidance: some View {
        Text(session.modelReadinessMessage)
            .font(.callout).fixedSize(horizontal: false, vertical: true)
    }
    private var chooseModelButton: some View {
        Button("選擇模型") { page = .models }.buttonStyle(.bordered)
    }
    #if os(macOS)
    private var overlayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { overlayButton; overlayOptions }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 12) { overlayButton; overlayOptions }
            }
            HStack {
                Menu("移至螢幕") {
                    ForEach(Array(session.panel.screenNames.enumerated()), id: \.offset) { index, name in
                        Button(name) { session.panel.selectScreen(index: index) }
                    }
                    Button("重設位置") { session.panel.resetPosition() }
                }
                Text("啟用穿透後，可在此關閉；拖曳浮窗邊緣調整大小。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .controlSize(.small)
    }
    private var overlayButton: some View {
        Button(session.overlayVisible ? "隱藏浮動字幕" : "顯示浮動字幕", systemImage: "macwindow.on.rectangle") {
            session.overlayVisible.toggle()
            if session.overlayVisible { session.panel.show(content: CaptionStage(session: session, overlay: true).preferredColorScheme(.dark)) }
            else { session.panel.hide() }
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }
    private var overlayOptions: some View {
        HStack(spacing: 16) {
            Toggle("置頂", isOn: $session.alwaysOnTop).onChange(of: session.alwaysOnTop) { _, value in session.panel.setAlwaysOnTop(value) }
            Toggle("點擊穿透", isOn: $session.clickThrough).onChange(of: session.clickThrough) { _, value in session.panel.setClickThrough(value) }
        }
    }
    #endif
    private var displayedPlayhead: Double {
        min(max(0, isScrubbing || isCommittingSeek ? scrubPosition : session.media.currentTime), max(1, session.media.duration))
    }
    private func scrubEditingChanged(_ editing: Bool) {
        if editing {
            scrubPosition = session.media.currentTime
            isScrubbing = true
        } else {
            let target = scrubPosition
            isCommittingSeek = true
            isScrubbing = false
            Task {
                await session.seek(to: target)
                isCommittingSeek = false
            }
        }
    }
    private func prepareExport(srt: Bool) {
        document = CaptionDocument(text: srt ? CaptionExporter.srt(session.captions) : CaptionExporter.txt(session.captions))
        exportType = srt ? CaptionDocument.subRipType : .plainText
        exportName = "Live Caption.\(srt ? "srt" : "txt")"
        exporting = true
    }
    private func prepareAlternativeExport() {
        document = CaptionDocument(text: CaptionExporter.txt(session.alternatives.map(\.caption)))
        exportType = .plainText
        exportName = "Live Caption - 其他辨識結果.txt"
        exporting = true
    }
}
