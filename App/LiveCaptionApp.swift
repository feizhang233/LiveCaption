import SwiftUI

@main
struct LiveCaptionApp: App {
    @State private var session = SessionController()
    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(session: session)
                #if os(macOS)
                .frame(minWidth: 660, minHeight: 520)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1_080, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("停止字幕並釋放模型") { Task { await session.stop() } }
                    .keyboardShortcut(".", modifiers: [.command])
                Button(session.overlayVisible ? "隱藏浮動字幕" : "顯示浮動字幕") { session.overlayVisible.toggle() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("關閉浮窗點擊穿透") { session.clickThrough = false }
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }
        #endif
        #if os(macOS)
        MenuBarExtra("Live Caption", systemImage: session.phase == .running ? "captions.bubble.fill" : "captions.bubble") {
            BackgroundCaptionControls(session: session)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
