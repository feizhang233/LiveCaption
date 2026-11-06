import CaptionCore
import SwiftUI
import UniformTypeIdentifiers

struct CaptionStage: View {
    @Bindable var session: SessionController
    var overlay = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !overlay {
                HStack {
                    Label(session.stageCaption?.isFinal == false ? "暫定字幕" : "原文字幕", systemImage: "captions.bubble")
                    Spacer()
                    if let caption = session.stageCaption {
                        Text(timecode(caption.start)).monospacedDigit()
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(CaptionTheme.secondaryText)
            }
            if let caption = session.stageCaption {
                Text(caption.text)
                    .font(.system(size: session.preferences.fontSize, weight: .medium, design: session.preferences.typeface.design))
                    .foregroundStyle(session.preferences.ink.color)
                    .lineLimit(session.preferences.lineCount)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: overlay ? .center : .leading)
                    .accessibilityLabel((caption.isFinal ? "已確認字幕：" : "暫定字幕：") + caption.text)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 30, weight: .light))
                    Text(session.phase == .running ? "等待語音…" : "讓原文跟上聲音")
                        .font(overlay ? .title3 : .title2.weight(.medium))
                    if !overlay { Text("字幕會在辨識到語音後出現").font(.callout).foregroundStyle(CaptionTheme.secondaryText) }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: overlay ? 50 : 100)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(overlay ? 18 : 24)
        .frame(maxWidth: .infinity, minHeight: overlay ? 80 : 190, alignment: .leading)
        .background { stageBackground }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var stageBackground: some View {
        if reduceTransparency || contrast == .increased {
            CaptionTheme.reading
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { actions; Spacer(minLength: 8); inputLevel }
            VStack(alignment: .leading, spacing: 12) { actions; inputLevel }
        }
        .padding(16)
        .modifier(GlassPanel())
    }
    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await session.togglePlayback() }
            } label: {
                Label(session.isPlaybackPaused ? "繼續" : session.phase == .running ? "暫停" : "開始字幕", systemImage: session.phase == .running && !session.isPlaybackPaused ? "pause.fill" : "play.fill")
                    .fixedSize().frame(minWidth: 82)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.phase != .running && !session.canStart)
            .keyboardShortcut(.return, modifiers: [.command])
            Button { Task { await session.stop() } } label: { Label("停止", systemImage: "stop.fill") }
                .buttonStyle(.bordered)
                .disabled(session.phase == .idle || session.phase == .stopping)
                .keyboardShortcut(".", modifiers: [.command])
        }
        .controlSize(.large)
        .fixedSize(horizontal: true, vertical: false)
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
                        HStack(alignment: .top, spacing: 16) {
                            Text(timecode(caption.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                            Text(caption.text).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        Divider()
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
                        HStack(alignment: .top, spacing: 16) {
                            Text(timecode(alternative.caption.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(alternative.caption.text).textSelection(.enabled)
                        }.padding(.vertical, 6)
                    }
                    if session.alternatives.count > 100 { Text("畫面顯示最近 100 筆；其他結果 TXT 匯出包含全部保留結果。").font(.caption) }
                }
            }
        }
    }
}

struct CaptionDocument: FileDocument {
    /// A filename-tagged text type preserves .srt on both macOS and iPadOS save panels.
    static let subRipType = UTType(filenameExtension: "srt", conformingTo: .plainText)!
    static var readableContentTypes: [UTType] { [.plainText, subRipType] }
    static var writableContentTypes: [UTType] { [.plainText, subRipType] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
