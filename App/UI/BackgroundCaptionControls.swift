#if os(macOS)
import AppKit
import SwiftUI

/// One prominent desktop-caption action for the main window and menu bar.
struct DesktopCaptionToggle: View {
    @Bindable var session: SessionController
    var compact = false

    var body: some View {
        Button { session.overlayVisible.toggle() } label: {
            HStack(spacing: 14) {
                Image(systemName: session.overlayVisible ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: compact ? 22 : 28, weight: .medium))
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.overlayVisible ? "隱藏浮動字幕" : "顯示浮動字幕")
                        .font(compact ? .headline : .title3.weight(.semibold))
                    Text(session.overlayVisible ? "已開啟，字幕會浮在其他 App 上方" : "將字幕放到影片下方或桌面任何位置")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(session.overlayVisible ? "ON" : "OFF")
                    .font(.caption.bold().monospaced())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: .capsule)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 64 : 80, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(CaptionTheme.accent)
        .accessibilityLabel(session.overlayVisible ? "隱藏浮動字幕" : "顯示浮動字幕")
        .accessibilityValue(session.overlayVisible ? "已開啟" : "已關閉")
        .accessibilityHint("浮動字幕獨立顯示在桌面，收起主視窗後仍會保留")
        .accessibilityIdentifier("captions.desktop.toggle")
    }
}

/// Keeps the shared session reachable while every main window is closed.
struct BackgroundCaptionControls: View {
    @Bindable var session: SessionController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var preferences = session.preferences
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live Caption").font(.headline)
                Spacer()
                Text(session.source.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            DesktopCaptionToggle(session: session, compact: true)
            SessionControls(session: session)
            StatusStrip(session: session)
            if !session.hasReadyModel {
                Text(session.modelReadinessMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle("不顯示語氣詞", isOn: $preferences.hideFillerWords)
            Toggle("點擊穿透", isOn: $session.clickThrough)
            Menu("浮窗選項") { FloatingCaptionOptions(session: session) }
            Button("顯示主視窗", systemImage: "macwindow") {
                openWindow(id: "main")
                NSApp.activate()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("captions.openMainWindow")
        }
        .toggleStyle(.switch)
        .padding(16)
        .frame(width: 360)
        .tint(CaptionTheme.accent)
        .preferredColorScheme(session.preferences.theme.scheme)
    }
}
#endif
