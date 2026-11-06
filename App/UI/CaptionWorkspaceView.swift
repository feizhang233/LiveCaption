import SwiftUI

/// Both caption destinations share the same source, controls, status and history.
/// The media destination additionally owns its player and transient seek gesture.
struct CaptionWorkspaceView: View {
    enum Mode { case live, media }

    @Bindable var session: SessionController
    let mode: Mode
    let importMedia: () -> Void
    let chooseModel: () -> Void
    #if os(iOS)
    var showMedia: () -> Void = {}
    #endif
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var isCommittingSeek = false
    #if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showingPreview = false
    @State private var showingHistory = false
    #endif

    var body: some View {
        CaptionPageContent(spacing: mode == .live ? 22 : 20) {
            #if os(macOS)
            if mode == .live { desktopLiveWorkspace }
            else { standardWorkspace }
            #else
            standardWorkspace
            #endif
        }
    }

    private var standardWorkspace: some View {
        Group {
            if mode == .media && !session.media.isReady {
                emptyMedia
            } else {
                if mode == .media { mediaPlayer }
                if mode == .live { sourceControls }
                #if os(iOS)
                if mode == .media {
                    MobileFloatingCaptionControls(session: session)
                } else {
                    Button("前往媒體播放並設定浮動字幕", systemImage: "pip.enter", action: showMedia)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Text("匯入音訊或影片後，可在媒體播放頁開啟子母畫面字幕，切到其他 App 繼續觀看。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif
                CaptionStage(session: session)
                if mode == .media { sourceControls }
                SessionControls(session: session)
                StatusStrip(session: session)
                if !session.hasReadyModel { modelPrompt }
                #if os(macOS)
                overlayControls
                #endif
                if mode == .live {
                    Divider()
                }
                TranscriptHistory(session: session)
            }
        }
    }

    private var mediaPlayer: some View {
        Group {
            Text(session.media.title ?? "").font(.headline).lineLimit(2)
            NativePlayerView(player: session.media.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxHeight: 440)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                Text(timecode(displayedPlayhead)).monospacedDigit()
                Slider(value: Binding(get: { displayedPlayhead }, set: { scrubPosition = $0 }),
                       in: 0...max(1, session.media.duration), onEditingChanged: scrubEditingChanged)
                    .accessibilityLabel("播放位置")
                    .accessibilityValue(timecode(displayedPlayhead))
                    .disabled(session.isBusy || session.media.isLoading || isCommittingSeek)
                Text(timecode(session.media.duration)).monospacedDigit()
            }
            .font(.caption)
        }
    }

    private var emptyMedia: some View {
        Group {
            ContentUnavailableView {
                Label("開啟一段影片或音訊", systemImage: "play.rectangle.on.rectangle")
            } description: {
                Text("匯入本機檔案，一邊播放，一邊產生原語言字幕。檔案不會上傳。")
            } actions: {
                Button("選擇媒體檔案", action: importMedia).buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 300)
            if session.media.isLoading { ProgressView("正在讀取音軌…") }
            StatusStrip(session: session)
        }
    }

    private var sourceControls: some View {
        AdaptiveControls(horizontalSpacing: 20) { sourcePicker; languagePicker }
    }
    private var sourcePicker: some View {
        Picker("音訊來源", selection: Binding(get: { session.source }, set: { value in Task { await session.changeSource(value) } })) {
            ForEach(CaptionSource.allCases) { source in Text(source.rawValue).tag(source) }
        }.pickerStyle(.menu).disabled(session.isBusy).frame(maxWidth: 260, alignment: .leading)
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
        }.pickerStyle(.menu).disabled(session.phase == .running || session.isBusy).frame(maxWidth: 260, alignment: .leading)
    }
    private var modelPrompt: some View {
        AdaptiveControls(verticalSpacing: 10) {
            Text(session.modelReadinessMessage)
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Button("選擇模型", action: chooseModel).buttonStyle(.bordered)
        }
    }
    #if os(macOS)
    private var desktopLiveWorkspace: some View {
        @Bindable var preferences = session.preferences
        return Group {
            DesktopCaptionToggle(session: session)
            AdaptiveControls {
                Button("收起主視窗", systemImage: "menubar.arrow.up.rectangle") {
                    dismissWindow(id: "main")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("captions.hideMainWindow")
                Text("收起後仍可從選單列的字幕圖示控制；已開啟的浮窗會保留。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sourceControls
            SessionControls(session: session)
            StatusStrip(session: session)
            if !session.hasReadyModel { modelPrompt }
            VStack(alignment: .leading, spacing: 14) {
                AdaptiveControls {
                    Toggle("開始系統收音時顯示浮窗", isOn: $preferences.autoShowOverlay)
                    Toggle("不顯示語氣詞", isOn: $preferences.hideFillerWords)
                }
                overlayOptions
                Menu("浮窗位置與樣式") { FloatingCaptionOptions(session: session) }
                Text("滑鼠移到字幕上可拖移或縮放；若啟用點擊穿透，可從選單列關閉。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            Divider()
            DisclosureGroup("字幕預覽", isExpanded: $showingPreview) {
                CaptionStage(session: session).padding(.top, 12)
            }
            DisclosureGroup("字幕歷史（\(session.captions.count) 段）", isExpanded: $showingHistory) {
                TranscriptHistory(session: session).padding(.top, 12)
            }
        }
    }

    private var overlayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveControls { overlayButton; overlayOptions }
            HStack {
                Menu("浮窗選項") { FloatingCaptionOptions(session: session) }
                Text("滑鼠移到字幕上可拖移或縮放；啟用穿透後，可在此關閉。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .controlSize(.small)
    }
    private var overlayButton: some View {
        Button(session.overlayVisible ? "隱藏浮動字幕" : "顯示浮動字幕", systemImage: "macwindow.on.rectangle") {
            session.overlayVisible.toggle()
        }
    }
    private var overlayOptions: some View {
        @Bindable var preferences = session.preferences
        return HStack(spacing: 16) {
            Toggle("置頂", isOn: $session.alwaysOnTop)
            Toggle("點擊穿透", isOn: $session.clickThrough)
            Toggle("顯示背景", isOn: $preferences.overlayShowsBackground)
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
}
