import SwiftUI

struct SettingsView: View {
    @Bindable var session: SessionController
    @State private var showingLicenses = false
    var body: some View {
        @Bindable var preferences = session.preferences
        Form {
            Section("外觀") {
                Picker("主題", selection: $preferences.theme) { ForEach(AppTheme.allCases) { Text($0.rawValue).tag($0) } }
            }
            Section("字幕") {
                Picker("字體", selection: $preferences.typeface) { ForEach(CaptionTypeface.allCases) { Text($0.rawValue).tag($0) } }
                LabeledContent("字體大小", value: "\(Int(preferences.fontSize)) pt")
                Slider(value: $preferences.fontSize, in: 18...64, step: 1).accessibilityLabel("字幕字體大小")
                Stepper("顯示 \(preferences.lineCount) 行", value: $preferences.lineCount, in: 1...8)
                Picker("文字顏色", selection: $preferences.ink) { ForEach(CaptionInk.allCases) { Text($0.rawValue).tag($0) } }
                Picker("背景樣式", selection: $preferences.background) { ForEach(CaptionBackground.allCases) { Text($0.rawValue).tag($0) } }
                    .onChange(of: preferences.background) { _, style in
                        if style == .transparent { preferences.opacity = 0 }
                        else if style == .solid, preferences.opacity == 0 { preferences.opacity = 0.94 }
                    }
                if preferences.background != .glass {
                    LabeledContent("背景不透明度", value: "\(Int(preferences.opacity * 100))%")
                    Slider(value: $preferences.opacity, in: 0...1).accessibilityLabel("字幕背景不透明度")
                }
                Text("減少透明度或提高對比啟用時，字幕會使用不透明背景。行數只影響畫面，匯出仍保留完整文字。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("辨識") {
                Toggle("使用 Metal 加速", isOn: $session.useGPU).disabled(session.phase == .running || session.isBusy)
                LabeledContent("目前執行方式", value: session.activeBackend)
                Text("關閉後使用 CPU。若 GPU 載入失敗，引擎會嘗試 CPU；速度依裝置與模型而異。")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("最近一次推論", value: "\(session.metrics.inferenceSeconds.formatted(.number.precision(.fractionLength(2)))) 秒")
                LabeledContent("該次音訊長度", value: "\(session.metrics.audioSeconds.formatted(.number.precision(.fractionLength(2)))) 秒")
            }
            Section("資料與使用範圍") {
                Text("音訊與辨識結果不會上傳。字幕歷史只在目前 App 工作階段保留，請在關閉前匯出。多視窗共用目前辨識工作階段。")
                Text("本機受保護媒體可能無法讀取；系統收音無法判定所有 DRM 情況，收不到音訊時會顯示提示。")
                #if os(iOS)
                Text("目前在 App 內播放時產生字幕。進入背景會停止辨識並釋放模型；不宣稱 PiP 或廣播擴充可維持任意本機推論。")
                #endif
            }
            Section("關於") {
                LabeledContent("Live Caption", value: "0.1")
                LabeledContent("辨識引擎", value: "whisper.cpp · v1.9.5")
                Text("Whisper 與 whisper.cpp 使用 MIT 授權。完整授權隨 App 附於 ThirdPartyNotices.txt。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("開放原始碼授權") { showingLicenses = true }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingLicenses) {
            NavigationStack {
                ScrollView {
                    Text(licenseText).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).padding(24)
                }
                .navigationTitle("開放原始碼授權")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingLicenses = false } } }
            }
            .frame(minWidth: 300, minHeight: 400)
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "授權檔案無法讀取。請查看專案 ThirdParty/Notices。" }
        return text
    }
}
