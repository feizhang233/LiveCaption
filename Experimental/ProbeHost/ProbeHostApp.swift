import ReplayKit
import SwiftUI

@main
struct ProbeHostApp: App {
    var body: some Scene { WindowGroup { ProbeScreen() } }
}

struct ProbeScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var pip = CaptionPiPProbe()
    @State private var report = "尚無廣播資料"
    @State private var ticks: UInt64 = 0
    @State private var sceneEvents: [String] = []
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("這是實驗工具，沒有語音辨識。錄製最多保留最近 8 秒 App 音訊於本機 App Group；正常停止會刪除。不要錄製敏感內容。")
                        .font(.callout)
                    BroadcastPicker().frame(width: 64, height: 64)
                        .accessibilityLabel("啟動診斷廣播")
                    Text(report).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    ProbeSurface(pip: pip).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Button("啟動畫中畫") { pip.start() }
                        Button("停止畫中畫") { pip.stop() }
                    }.buttonStyle(.bordered)
                    Text(pip.state)
                    Text("主 App 計時回呼：\(ticks) 次。切到其他 App／鎖定螢幕，回來檢查回呼是否停滯；數值持續增加也不能單獨證明 Whisper 可持續推論。")
                    ForEach(Array(sceneEvents.enumerated()), id: \.offset) { _, event in Text(event).font(.caption.monospaced()) }
                    Button("刪除殘留診斷音訊", role: .destructive) { eraseProbeAudio() }
                }.padding()
            }
            .navigationTitle("跨 App 收音實驗")
            .task {
                while !Task.isCancelled {
                    ticks &+= 1
                    report = readStatus()
                    pip.render(text: "診斷資料，非辨識字幕\n主 App 回呼：\(ticks)\n\(Date().formatted(date: .omitted, time: .standard))")
                    do { try await Task.sleep(for: .seconds(1)) } catch { break }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                sceneEvents.append("\(Date().formatted(date: .omitted, time: .standard)) \(String(describing: phase))")
                if sceneEvents.count > 30 { sceneEvents.removeFirst() }
            }
        }
    }

    private var directory: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LiveCaptionAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("BroadcastProbe")
    }
    private func readStatus() -> String {
        guard let directory else { return "App Group 不可用；請完成簽署設定。" }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("status.json")),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return "尚無廣播資料" }
        return text
    }
    private func eraseProbeAudio() {
        guard let directory else { return }
        for index in 0..<32 { try? FileManager.default.removeItem(at: directory.appendingPathComponent("slot-\(index).json")) }
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        picker.preferredExtension = "\(Bundle.main.bundleIdentifier ?? "").broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

private struct ProbeSurface: UIViewRepresentable {
    let pip: CaptionPiPProbe
    func makeUIView(context: Context) -> ProbeVideoSurface { pip.surface }
    func updateUIView(_ uiView: ProbeVideoSurface, context: Context) {}
}
