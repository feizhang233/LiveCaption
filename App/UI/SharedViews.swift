import CaptionCore
import SwiftUI

struct CaptionStage: View {
    @Bindable var session: SessionController
    var overlay = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let caption = session.stageCaption
        return VStack(alignment: .leading, spacing: 12) {
            if !overlay {
                HStack {
                    Label(caption?.isFinal == false ? "暫定字幕" : "原文字幕", systemImage: "captions.bubble")
                    Spacer()
                    if let caption {
                        Text(timecode(caption.start)).monospacedDigit()
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(CaptionTheme.secondaryText)
            }
            if let caption, !session.displayStageText.isEmpty {
                Text(session.displayStageText)
                    .font(.system(size: session.preferences.fontSize, weight: .medium, design: session.preferences.typeface.design))
                    .foregroundStyle(session.preferences.ink.color)
                    .lineLimit(session.preferences.lineCount)
                    .truncationMode(.head)
                    .multilineTextAlignment(overlay ? .center : .leading)
                    .modifier(CaptionTextShadow(enabled: overlay))
                    .frame(maxWidth: .infinity, alignment: overlay ? .center : .leading)
                    .accessibilityLabel((caption.isFinal ? "已確認字幕：" : "暫定字幕：") + session.displayStageText)
            } else if overlay {
                Color.clear.frame(height: 0).accessibilityHidden(true)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 30, weight: .light))
                    Text(caption != nil ? "已隱藏語氣詞" : session.isWaitingForScope ? "等待指定 App 或網站" : session.phase == .running ? "等待語音…" : "讓原文跟上聲音")
                        .font(overlay ? .title3 : .title2.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if !overlay { Text(session.isWaitingForScope ? "切換到指定範圍後自動繼續" : "字幕會在辨識到語音後出現").font(.callout).foregroundStyle(CaptionTheme.secondaryText) }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: overlay ? 50 : 100)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, overlay ? 24 : CaptionLayout.contentPadding(for: horizontalSizeClass))
        .padding(.vertical, overlay ? 0 : CaptionLayout.contentPadding(for: horizontalSizeClass))
        .frame(maxWidth: .infinity, minHeight: overlay ? 0 : 190, maxHeight: overlay ? .infinity : nil, alignment: overlay ? .center : .leading)
        .background { stageBackground }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var stageBackground: some View {
        if overlay && session.displayStageText.isEmpty {
            Color.clear
        } else if reduceTransparency || contrast == .increased {
            CaptionTheme.reading
        } else if overlay && !session.preferences.overlayShowsBackground {
            Color.clear
        } else {
            switch session.preferences.background {
            case .solid: CaptionTheme.reading.opacity(session.preferences.opacity)
            case .glass:
                Color.clear.glassEffect(.regular.tint(CaptionTheme.reading), in: .rect(cornerRadius: 20))
            case .transparent: Color.black.opacity(session.preferences.opacity)
            }
        }
    }
}

/// A small dark edge keeps floating text readable over both light and dark video.
private struct CaptionTextShadow: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: .black, radius: 1, x: -1, y: -1)
                .shadow(color: .black, radius: 1, x: 1, y: 1)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 2)
        } else { content }
    }
}

#if os(macOS)
/// The controls occupy reserved space, so hovering never moves the subtitle.
struct FloatingCaptionView: View {
    @Bindable var session: SessionController
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var isHovering = false
    @State private var introductionVisible = true

    private var controlsVisible: Bool {
        !session.clickThrough && (isHovering || introductionVisible || voiceOver)
    }

    var body: some View {
        ZStack {
            CaptionStage(session: session, overlay: true)
                .padding(.top, 38)
                .padding(.bottom, 12)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    CaptionPanelDragHandle()
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .overlay(alignment: .leading) {
                            Label("拖移字幕", systemImage: "hand.draw")
                                .font(.caption).padding(.leading, 8)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        .help("拖曳以移動字幕；也可從選項重設位置")
                    Button { session.clickThrough = true } label: {
                        Image(systemName: "cursorarrow.rays")
                    }
                    .help("啟用點擊穿透；回到主視窗後可按 ⌥⌘L 關閉")
                    .accessibilityLabel("啟用浮窗點擊穿透")
                    floatingOptions
                    Button { session.overlayVisible = false } label: {
                        Image(systemName: "xmark")
                    }
                    .help("隱藏浮動字幕（⇧⌘L）")
                    .accessibilityLabel("隱藏浮動字幕")
                }
                .buttonStyle(.borderless)
                .controlSize(.regular)
                .padding(6)
                .modifier(GlassPanel())
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    if session.stageCaption == nil {
                        Text(session.isWaitingForScope ? "等待指定 App 或網站" : session.phase == .running ? "等待語音…" : "開始辨識後，字幕會顯示在這裡")
                            .font(.caption)
                            .padding(8)
                            .background(CaptionTheme.reading, in: .capsule)
                    }
                    Spacer(minLength: 0)
                    CaptionPanelResizeHandle().frame(width: 24, height: 24)
                        .help("拖曳以調整大小；也可從選項選擇寬度")
                }
            }
            .padding(8)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
            .accessibilityHidden(!controlsVisible)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onChange(of: session.clickThrough) { _, _ in isHovering = false; introductionVisible = false }
        .task {
            try? await Task.sleep(for: .seconds(3))
            introductionVisible = false
        }
        .preferredColorScheme(.dark)
    }

    private var floatingOptions: some View {
        Menu {
            FloatingCaptionOptions(session: session)
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("浮動字幕選項")
        .accessibilityLabel("浮動字幕選項")
    }
}

/// Shared with the main window, where all options remain keyboard accessible.
struct FloatingCaptionOptions: View {
    @Bindable var session: SessionController
    var body: some View {
        @Bindable var preferences = session.preferences
        return Group {
            Toggle("顯示背景", isOn: $preferences.overlayShowsBackground)
            Toggle("隱藏語氣詞", isOn: $preferences.hideFillerWords)
            Toggle("置頂", isOn: $session.alwaysOnTop)
            Menu("字幕寬度") {
                Button("窄（480 點）") { session.panel.resize(to: 480) }
                Button("標準（760 點）") { session.panel.resize(to: 760) }
                Button("寬（1,040 點）") { session.panel.resize(to: 1_040) }
            }
            Menu("移至螢幕") {
                ForEach(Array(session.panel.screenNames.enumerated()), id: \.offset) { index, name in
                    Button(name) { session.panel.selectScreen(index: index) }
                }
            }
            Button("重設大小") { session.panel.resize(to: NSSize(width: 760, height: 170)) }
            Button("重設位置") { session.panel.resetPosition() }
        }
    }
}
#endif

struct StatusStrip: View {
    var session: SessionController
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 9) {
                if session.isBusy { ProgressView().controlSize(.small) }
                else { Image(systemName: session.errorMessage == nil ? "info.circle" : "exclamationmark.triangle").foregroundStyle(session.errorMessage == nil ? Color.secondary : Color.orange) }
                Text(session.status).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.metrics.droppedAudioSeconds + session.inputDroppedSeconds > 0 {
                Label("辨識速度跟不上播放，已略過 \(session.metrics.droppedAudioSeconds + session.inputDroppedSeconds, specifier: "%.1f") 秒音訊。可改用較小模型。", systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.status)
        .padding(.vertical, 8)
    }
}

struct SessionControls: View {
    @Bindable var session: SessionController
    var body: some View {
        AdaptiveControls { actions; inputLevel }
            .padding(16)
            .modifier(GlassPanel())
    }
    private var actions: some View {
        AdaptiveControls(horizontalSpacing: 12) { playbackButton; stopButton }
            .controlSize(.large)
    }
    private var playbackButton: some View {
        Button {
            Task { await session.togglePlayback() }
        } label: {
            Label(session.isWaitingForScope ? "暫停自動字幕" : session.isPlaybackPaused ? "繼續" : session.phase == .running ? "暫停" : "開始字幕", systemImage: session.isWaitingForScope || (session.phase == .running && !session.isPlaybackPaused) ? "pause.fill" : "play.fill")
                .fixedSize(horizontal: false, vertical: true).frame(minWidth: 82)
        }
        .buttonStyle(.borderedProminent)
        .disabled(session.isBusy || (session.phase != .running && !session.canStart && !session.isWaitingForScope))
        .keyboardShortcut(.return, modifiers: [.command])
    }
    private var stopButton: some View {
        Button { Task { await session.stop() } } label: { Label("停止", systemImage: "stop.fill") }
            .buttonStyle(.bordered)
            .disabled(session.phase == .idle || session.phase == .stopping)
            .keyboardShortcut(".", modifiers: [.command])
    }
    private var inputLevel: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(.secondary)
            ProgressView(value: Double(session.level)).frame(width: 70).accessibilityLabel("音訊音量")
            Text(session.models.selectedModel?.name ?? "尚未選擇模型").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct TranscriptHistory: View {
    var session: SessionController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("字幕歷史").font(.headline)
                Spacer()
                Text("\(session.captions.count) 段已確認").font(.caption).foregroundStyle(.secondary)
            }
            if session.trimmedHistory {
                Text("字幕記錄已達容量上限，已停止辨識。已保留的字幕仍可匯出。").font(.caption).foregroundStyle(.orange)
            }
            if session.captions.isEmpty {
                ContentUnavailableView("還沒有字幕", systemImage: "text.alignleft", description: Text("已確認的原文會保留在這裡，可匯出為 TXT 或 SRT。"))
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.captions.suffix(500)) { caption in
                        if !session.displayText(for: caption).isEmpty {
                            TranscriptRow(caption: caption, text: session.displayText(for: caption)).padding(.vertical, 12)
                            Divider()
                        }
                    }
                    if session.captions.count > 500 {
                        Text("畫面顯示最近 500 段；匯出包含目前保留的全部字幕。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !session.alternatives.isEmpty {
                DisclosureGroup("重播的其他辨識結果（\(session.alternatives.count)）") {
                    Text("主字幕保留首次確認的文字。時間重疊且無法可靠合併的重播結果保留在這裡，可另行匯出 TXT；不寫入主 SRT，避免重疊顯示。")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    ForEach(session.alternatives.suffix(100)) { alternative in
                        if !session.displayText(for: alternative.caption).isEmpty {
                            TranscriptRow(caption: alternative.caption, text: session.displayText(for: alternative.caption)).padding(.vertical, 6)
                        }
                    }
                    if session.alternatives.count > 100 { Text("畫面顯示最近 100 筆；其他結果 TXT 匯出包含全部保留結果。").font(.caption) }
                }
            }
        }
    }
}

private struct TranscriptRow: View {
    let caption: CaptionSegment
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            Text(timecode(caption.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Text(text).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
