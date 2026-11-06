import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, captions
    #if os(macOS)
    case scope
    #endif
    case recognition, privacy, about

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "通用"
        case .captions: "字幕樣式"
        #if os(macOS)
        case .scope: "啟用範圍"
        #endif
        case .recognition: "辨識與效能"
        case .privacy: "隱私與資料"
        case .about: "關於"
        }
    }
}

struct SettingsView: View {
    @Bindable var session: SessionController
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var category: SettingsCategory
    @State private var showingLicenses = false
    #if os(macOS)
    @State private var scopeEditing = CaptionScopeSettingsState()
    #endif

    init(session: SessionController, initialCategory: SettingsCategory = .general) {
        self.session = session
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                categoryPicker.pickerStyle(.segmented)
                    .labelsHidden().fixedSize(horizontal: true, vertical: false)
                categoryPicker.pickerStyle(.menu)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CaptionLayout.contentPadding(for: horizontalSizeClass))
            .padding(.vertical, 12)
            Divider()

            Form {
                switch category {
                case .general: generalSettings
                case .captions: captionSettings
                #if os(macOS)
                case .scope: CaptionScopeSettingsView(session: session, editing: scopeEditing)
                #endif
                case .recognition: recognitionSettings
                case .privacy: privacySettings
                case .about: aboutSettings
                }
            }
            .formStyle(.grouped)
        }
        .sheet(isPresented: $showingLicenses) {
            NavigationStack {
                ScrollView {
                    Text(licenseText).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).padding(24)
                }
                .navigationTitle("開放原始碼授權")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingLicenses = false } } }
            }
            #if os(macOS)
            .frame(minWidth: 300, minHeight: 400)
            #endif
        }
    }

    private var categoryPicker: some View {
        Picker("設定分類", selection: $category) {
            ForEach(SettingsCategory.allCases) { category in
                Text(category.title).tag(category)
            }
        }
        .accessibilityIdentifier("settings.category")
    }

    private var generalSettings: some View {
        @Bindable var preferences = session.preferences
        return Group {
            Section("介面外觀") {
                Picker("主題", selection: $preferences.theme) { ForEach(AppTheme.allCases) { Text($0.rawValue).tag($0) } }
            }
            Section("工作階段") {
                #if os(iOS)
                Text("播放本機媒體時可開啟子母畫面字幕，再切到其他 App。一般離開 App 會停止辨識；關閉背景子母畫面也會停止。已確認的字幕會保留至關閉 App 或清除歷史。")
                    .foregroundStyle(.secondary)
                #else
                Toggle("開始系統字幕時自動顯示浮窗", isOn: $preferences.autoShowOverlay)
                Text("收起主視窗後仍會繼續辨識。可從螢幕頂端的字幕選單開啟主視窗、暫停或控制浮窗。")
                    .foregroundStyle(.secondary)
                #endif
            }
        }
    }

    private var captionSettings: some View {
        @Bindable var preferences = session.preferences
        return Group {
            Section("字幕內容") {
                Toggle("隱藏語氣詞", isOn: $preferences.hideFillerWords)
                Text("隱藏「呃、嗯、えー、um、euh」等停頓詞。請指定中文、日文、英文或法文；自動判斷時保留原文以避免誤刪。只影響顯示，匯出保留原文。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("文字與排版") {
                Picker("字體", selection: $preferences.typeface) { ForEach(CaptionTypeface.allCases) { Text($0.rawValue).tag($0) } }
                LabeledContent("字體大小", value: "\(Int(preferences.fontSize)) pt")
                Slider(value: $preferences.fontSize, in: 18...64, step: 1).accessibilityLabel("字幕字體大小")
                Stepper("顯示 \(preferences.lineCount) 行", value: $preferences.lineCount, in: 1...8)
                Picker("文字顏色", selection: $preferences.ink) { ForEach(CaptionInk.allCases) { Text($0.rawValue).tag($0) } }
                Text("行數只影響畫面，匯出仍保留完整文字。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("字幕背景") {
                #if os(macOS)
                Toggle("浮動字幕顯示背景", isOn: $preferences.overlayShowsBackground)
                Text("浮動字幕預設只顯示文字。開啟後，套用下方的背景樣式。")
                    .font(.caption).foregroundStyle(.secondary)
                #endif
                Picker("背景樣式", selection: $preferences.background) { ForEach(CaptionBackground.allCases) { Text($0.rawValue).tag($0) } }
                    .onChange(of: preferences.background) { _, style in
                        if style == .transparent { preferences.opacity = 0 }
                        else if style == .solid, preferences.opacity == 0 { preferences.opacity = 0.94 }
                    }
                if preferences.background != .glass {
                    LabeledContent("背景不透明度", value: "\(Int(preferences.opacity * 100))%")
                    Slider(value: $preferences.opacity, in: 0...1).accessibilityLabel("字幕背景不透明度")
                }
                Text("減少透明度或提高對比啟用時，字幕會使用不透明背景。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var recognitionSettings: some View {
        Group {
            Section("硬體加速") {
                Toggle("使用 Metal 加速", isOn: $session.useGPU).disabled(session.phase == .running || session.isBusy)
                    #if os(iOS)
                    .disabled(session.isPreparingPictureInPicture || session.pictureInPicture.isActive || session.pictureInPicture.isStarting)
                    #endif
                Text("關閉後使用 CPU。若 GPU 載入失敗，引擎會嘗試 CPU；速度依裝置與模型而異。")
                    .font(.caption).foregroundStyle(.secondary)
                if session.phase == .running || session.isBusy {
                    Text("暫停字幕後可以調整加速方式。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("執行狀態") {
                LabeledContent("目前執行方式", value: session.activeBackend)
                LabeledContent("最近一次推論", value: "\(session.metrics.inferenceSeconds.formatted(.number.precision(.fractionLength(2)))) 秒")
                LabeledContent("該次音訊長度", value: "\(session.metrics.audioSeconds.formatted(.number.precision(.fractionLength(2)))) 秒")
            }
        }
    }

    private var privacySettings: some View {
        Group {
            Section("本機處理") {
                Text("音訊與辨識結果不會上傳。")
            }
            Section("字幕保存") {
                Text("字幕歷史只在目前 App 工作階段保留，請在關閉前匯出。")
            }
            Section("內容與平台限制") {
                Text("本機受保護媒體可能無法讀取；系統收音無法判定所有 DRM 情況，收不到音訊時會顯示提示。")
                #if os(iOS)
                Text("浮動字幕使用系統子母畫面，只支援本 App 播放的本機媒體。無法擷取 Safari 或其他 App 的聲音；視窗大小、位置與背景執行由系統控制。")
                #endif
            }
        }
    }

    private var aboutSettings: some View {
        Group {
            Section("版本資訊") {
                LabeledContent("Live Caption", value: appVersion)
                LabeledContent("建置版本", value: buildVersion)
                LabeledContent("辨識引擎", value: "whisper.cpp · v1.9.5")
            }
            Section("開放原始碼") {
                Link("專案原始碼", destination: URL(string: "https://github.com/feizhang233/LiveCaption")!)
                Text("Whisper 與 whisper.cpp 使用 MIT 授權。完整授權隨 App 附於 ThirdPartyNotices.txt。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("開放原始碼授權") { showingLicenses = true }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未提供"
    }

    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未提供"
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "授權檔案無法讀取。請查看專案 ThirdParty/Notices。" }
        return text
    }
}
