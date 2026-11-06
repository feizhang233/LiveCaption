# 參考原始碼、授權與相容性稽核

查核日期：2026-11-06。以下是本次實際下載並閱讀的原始碼版本，並非只根據 README 推論功能。參考專案的 Rust、Tauri、React、Python、伺服器套件均未加入產品執行依賴；平台程式碼為本專案原生實作。whisper.cpp 的實際採用版本與雜湊另見 `ThirdParty/whisper-dependency.json` 及引擎建置腳本。

## 官方 whisper.cpp

產品直接使用 [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp) C API，透過固定版本的 Apple XCFramework 整合。保留官方 MIT 授權；Swift 包裝只管理 C context、推論序列化及取消。沒有啟動 HTTP server，沒有 Python 執行依賴。引擎版本及實際加速後端以本專案固定的 framework 與建置驗證記錄為準，不能由其他封裝專案的版本反推。

## kotonoha

- 來源：[7nohe/kotonoha，commit `65ff626bad2d550fe840c3b5bc84e2b384b44c7e`](https://github.com/7nohe/kotonoha/tree/65ff626bad2d550fe840c3b5bc84e2b384b44c7e)。`Cargo.toml` 套件版本 `0.1.6`；MIT，copyright 2026 DAIKI URATA。
- 實讀 `src-tauri/src/audio/system.rs:18–49,71–101`、`system_catap.rs`、`src-tauri/src/overlay.rs:16–68`、`stt/segmenter.rs`、`stt/engine.rs`、`stt/models.rs`、`Cargo.toml`、`Cargo.lock`。
- lock 實際版本：`whisper-rs 0.16.0`、`whisper-rs-sys 0.15.0`、`screencapturekit 7.0.1`、`cidre 0.15.2`、`rubato 0.16.2`、`tauri 2.11.2`。`tauri-nspanel` 固定 git revision `a3122e894383aa068ec5365a42994e3ac94ba1b6`。
- 可參考的機制：ScreenCaptureKit 排除本程序音訊；音訊轉成單聲道；非啟用式 NSPanel、跨 Spaces／全螢幕輔助視窗、依邏輯點計算位置。本專案用 Swift `SCStream`、`AVAudioConverter`、`NSPanel` 直接實作這些平台能力。
- 不採用其 Tauri shell、翻譯／Ollama、會議摘要或其宣稱的延遲數值。本專案的多螢幕／全螢幕行為仍需另行實測。

## Lakr233/WhisperKit

- 來源：[Lakr233/WhisperKit，commit `84b7ab2d4c9ba12841af22e71f50a34016cb744f`](https://github.com/Lakr233/WhisperKit/tree/84b7ab2d4c9ba12841af22e71f50a34016cb744f)。不是 Argmax 的同名專案。MIT，copyright 2025 Lakr Aream；LICENSE 同時附 whisper.cpp 的 MIT 聲明。
- 實讀 `Package.swift:1–37`、`Sources/WhisperKit/Core/WhisperEngine.swift:17–80`、`WhisperEngineExtensions.swift`、`Services/VADService.swift:15–45`、`Utilities/AudioUtilities.swift`。
- Swift tools `5.9`，最低 iOS 16／macOS 13。binary target 雜湊 `a1a4043a47a5d662402d43c22f4e0d094bc7974c706f483a191d6574cef4f7f8`；URL 為該 repository 的 `whisper.xcframework` release 資產。套件含 `ggml-silero-v5.1.2` VAD 資源。
- 實際包裝使用 `whisper_init_from_file_with_params`、`whisper_init_state` 和釋放函式；GPU 與 VAD 參數可在 Swift 設定。這些原始碼可協助理解 C API 生命週期，但未提供本專案需要的完整下載、播放時序或背景保證。
- 本專案未依賴此二進位資產。該 manifest 的 checksum 可驗證資產內容，但本次讀取的 manifest 沒有足以把 binary 唯一對應到官方 whisper.cpp commit 的建置溯源，因此產品選擇直接固定官方引擎來源。

## Live-Translate iOS

- 來源：[senoldogann/Live-Translate，commit `9566f40fa7fe348d729ce0601935bef2156fb756`](https://github.com/senoldogann/Live-Translate/tree/9566f40fa7fe348d729ce0601935bef2156fb756)。MIT，copyright 2025–2026 Senol Dogan。
- 實讀 `ios/App/Sources/BroadcastExtension/SampleHandler.swift:16–80,93–113`、`BroadcastAudioConverter.swift`、`PipSubtitleController.swift:35–80,96–117,183–230`、`ios/Core/Sources/LiveTranslateCore/LTSClient.swift`、`SegmentRelay.swift:57–96`、`ios/App/project.yml`、`scripts/build-whisper-ios-xcframework.sh:24–46`。
- iOS App target 最低 `16.2`、Swift `5.0`；Core package tools `5.9`、iOS `16`。本地引擎 build script 在沒有 vendor checkout 時直接 shallow clone whisper.cpp 預設分支，沒有固定 tag／commit；該流程不可作為可重現依賴鎖定。
- **跨 App 路徑依賴伺服器**：SampleHandler 建立 `LTSClient`，從 `SharedLTSConfig.serverURL`／API key 連線；`.audioApp` 經 converter 後呼叫 `client.sendPCMBytes`。回來的字幕再寫入 App Group。這不是廣播 extension 本機 Whisper 推論的證據。
- PiP 用公開的 `AVSampleBufferDisplayLayer`／`AVPictureInPictureController.ContentSource`，但同檔 `setValue(1, forKey: "controlsStyle")` 不是這裡可採用的公開 API；本專案不使用該 KVC 控制項。
- 註解聲稱 extension 固定 50 MB 上限、Darwin notification 可以喚醒主 App。本專案沒有把這些註解當成平台保證：實際 memory/jetsam 閾值依裝置及系統測量；通知與 App Group 不提供任意背景 CPU 執行權。

## 授權處理

上述三個參考專案均只用於架構與 API 查核，沒有逐段複製其程式碼、資產或依賴。必要的 whisper.cpp／ggml MIT 文字跟隨所採用引擎交付。若後續複製參考程式碼或 VAD 資產，必須把對應 copyright／license 加入 `ThirdParty` 並在 App 授權頁保留，不應因同為 MIT 而省略原作者。

## 本次 SDK 相容性警示

查核環境為 Xcode `27.2 (27B52)`、Swift `6.4.2`；產品最低 iPadOS／macOS `26.0`。以下 headers 路徑均相對於本機 `iPhoneOS.sdk/System/Library/Frameworks`，並與 2026-11-06 Apple 公開文件交叉核對：

| API／能力 | 實際證據 | 解讀 |
|---|---|---|
| ReplayKit broadcast | `ReplayKit.framework/Headers/RPBroadcastExtension.h:120–121`；[官方 metadata](https://developer.apple.com/tutorials/data/documentation/replaykit/rpbroadcastsamplehandler.json) | iOS／iPadOS `deprecatedAt: 27.0`，訊息 `No longer supported`；不是本次已證明 runtime 移除 |
| ScreenCaptureKit 與 picker | [framework metadata](https://developer.apple.com/tutorials/data/documentation/screencapturekit.json)、[picker metadata](https://developer.apple.com/tutorials/data/documentation/screencapturekit/sccontentsharingpicker.json)；`ScreenCaptureKit.framework/Headers/SCContentSharingPicker.h:72,129,164` | framework、picker、observer 均為 iOS／iPadOS 27.0 起可用；不能移植為 26 版支援聲明 |
| SCStream 音訊配置 | `ScreenCaptureKit.framework/Headers/SCStream.h:315–330,474,497` | `capturesAudio`、`sampleRate`、`channelCount`、`excludesCurrentProcessAudio` 與 SCStream 為 iOS 27.0 起可用 |
| 不能共用的 Mac API | 同檔 `SCStream.h:152–186,525,533` | display/window filter initializer、`updateContentFilter`、`updateConfiguration` 明列 iOS unavailable；須由系統 picker 建立 iPad 路徑 |
| 正式背景擷取模式 | [Apple 背景模式文件](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)／[JSON](https://developer.apple.com/tutorials/data/documentation/xcode/configuring-background-execution-modes.json) | 列出 Screen Capture／`screen-capture`，用途為背景擷取及串流螢幕內容；未保證任意 Whisper GPU 工作 |

[Apple ScreenCaptureKit 概覽](https://developer.apple.com/documentation/screencapturekit) 已明確說明新的跨平台範圍、以此替代 ReplayKit 串流／鏡像及不再需要 broadcast extension，推薦 `SCContentSharingPicker`、適當背景 capability，並要求 `NSScreenCaptureUsageDescription`。因此 **27＋有新的公開研究路徑，不應描述成 iPad 一概無法跨 App 收音**；但是本次沒有實作或在 iPad 驗證該路徑、持續本機推論及 PiP。既有獨立 probe 仍只提供 iOS 26 deployment 的 ReplayKit／PiP 診斷，產品維持前景媒體方案；後續架構與測試界線見 [平台可行性](PlatformFeasibility.md)。
