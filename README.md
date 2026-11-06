# Live Caption

公開原始碼倉庫：[feizhang233/LiveCaption](https://github.com/feizhang233/LiveCaption)。

原生 Swift／SwiftUI 即時原文字幕 App，支援 **macOS 26＋與 iPadOS 26＋**。內建官方 whisper.cpp；音訊在本機辨識，模型由使用者在 App 內下載及選擇。使用者不需要 Python、命令列引擎、API key、背景伺服器或連接埠。

這是可建置的第一版開發交付，**尚未完成所有平台與長時間情境的產品驗收**。日語／法語真人音訊已通過本機核心流程；iPad 真機、Mac 系統收音權限、全螢幕與多螢幕仍待驗證。iPad 的可用架構以 **App 內媒體播放、前景本機字幕**為目標；ReplayKit／PiP 是獨立研究工具，沒有宣稱全本機跨 App 背景辨識已成立。完整狀態見 [驗收矩陣](Docs/Acceptance.md)。

後續開發與維護請先讀 [專案結構與維護指南](STRUCTURE.md)：包含目錄責任、資料流、取消與時間軸不變條件，以及各層修改後的測試入口。

GitHub 原始碼的納入／排除範圍、乾淨目錄建置與驗證紀錄元資料處理，見 [倉庫發布說明](Docs/Repository.md)。

## 使用流程

1. 開啟「模型管理」，查看檔案大小、記憶體估計及可用空間；下載模型，等待大小與 SHA-256 驗證完成後按「使用模型」。不會自動下載大型模型。
2. 在「即時字幕」或「媒體播放」選擇來源與原語言。首次預設日語，之後記住上次選擇；提供法語、英文、中文（普通話）、可選自動偵測及固定引擎支援的其他語言。中文輸出繁簡字形由模型決定，沒有額外字形轉換，也不保證所有中文方言。辨識設定為原文轉寫，沒有翻譯功能。
3. 匯入本機音訊／影片，按「開始字幕」。Mac 也提供其他 App 的系統音訊來源及浮動字幕視窗。
4. 使用暫停、繼續、停止；停止會取消推論並釋放模型。確認字幕保留在當次工作階段，可匯出 TXT／SRT；關閉 App 前請先匯出。

「設定」提供系統／淺色／深色、字幕字體、大小、顏色、行數、透明／Liquid Glass／純色背景及適用的不透明度。導航與控制面板使用原生 Liquid Glass；字幕閱讀區優先維持對比，尊重減少透明度及提高對比。Mac 浮窗可拖移、縮放、置頂、點擊穿透與移至指定螢幕；主視窗和選單提供恢復穿透控制。多視窗共用同一個辨識工作階段。

快捷鍵：`⌘O` 匯入、`⌘Return` 開始／暫停、`⌘.` 停止、`⇧⌘L` 顯示／隱藏浮窗、`⌥⌘L` 關閉浮窗點擊穿透。

## 開發建置

已提供 [LiveCaption.xcodeproj](LiveCaption.xcodeproj)，**直接用 Xcode 開啟，無須安裝 XcodeGen**。本次編譯環境為 Xcode 27.2（27B52）／Swift 6.4.2；deployment target 為 26.0。Xcode 26 的相容性尚未實測，建議使用本次驗證版本。

命令列建置需選用完整 Xcode 的 Developer 目錄；只有 Command Line Tools 不足以建置 iPad target。此次驗證在 Apple Silicon Mac 執行；平台音訊與工作階段測試腳本固定編譯 arm64，未驗證 Intel Mac。模擬器執行測試另需在 Xcode 安裝 iOS／iPadOS 26＋ runtime。

首次取得原始碼時，開發者需下載並校驗固定的官方 XCFramework：

```sh
bash Scripts/fetch-whisper.sh
open LiveCaption.xcodeproj
```

已存在且可用的 `Packages/CaptionCore/Frameworks/whisper.xcframework` 不必重複下載。二進位與模型權重排除於版本控制；App 發行包會內含引擎，不要求使用者執行上述腳本。下載腳本使用 macOS 內建 curl、shasum、unzip，不需要 Python。

Xcode scheme：

| Scheme | 用途 |
|---|---|
| `LiveCaptionMac` | 原生 macOS App |
| `LiveCaptioniPad` | 原生 iPad App／模擬器 |

亦可執行無簽署的編譯／連結驗證，不會安裝或發布 App：

```sh
bash Scripts/build.sh mac
bash Scripts/build.sh ipad-simulator
bash Scripts/build.sh ipad-device
# 同時驗證 Mac 與 iPad Simulator
bash Scripts/build.sh all
```

`CAPTION_BUILD_DIR` 可指定 DerivedData 路徑，`CAPTION_CONFIGURATION` 可選 `Debug`／`Release`。一般開啟專案不需要重新生成；只有維護 `project.yml` 後才使用開發工具 XcodeGen 2.46.0 同步產生專案。

## 簽署與權限

- **Mac**：在 `LiveCaptionMac → Signing & Capabilities` 選擇自己的 Team，必要時把 `com.example.livecaption.mac` 改為唯一 bundle ID。產品使用 App Sandbox；網路權限只用於模型下載，本機檔案透過系統選檔／存檔介面授權。
- **系統收音**：使用 ScreenCaptureKit，不安裝虛擬音效驅動。首次開始時由系統要求錄製權限；被拒時到「系統設定 → 隱私權與安全性 → 螢幕與系統音訊錄製」允許 App，必要時重新開啟。此版不擷取麥克風、不保存螢幕影片。
- **iPad 真機**：為 `LiveCaptioniPad` 選自己的 Team、唯一 bundle ID，啟用裝置 Developer Mode，再由 Xcode Run。一般產品不需要 App Group，也沒有偽造背景音訊模式；進入背景會停止辨識。
- **研究用廣播**：另開 [Experimental/ReplayKitProbe.xcodeproj](Experimental/ReplayKitProbe.xcodeproj)。host 與 extension 需要同一個已簽署 App Group；26 版 ReplayKit 設定及 27 版新的 ScreenCaptureKit 公開研究路徑見 [平台可行性](Docs/PlatformFeasibility.md)。這個診斷 App 不做語音辨識，也不嵌入一般產品；27＋替代路徑尚未實作或真機驗證。

Unsigned build 通過不代表真機簽署、安裝、權限授予或功能已驗證；本交付沒有進行 App Store／TestFlight 發布或 Mac notarization。

## 共用核心與依賴

`App/Media` 以 AVFoundation 讀取本機媒體，跟隨實際播放位置供應 PCM；`App/Platform/macOS` 提供 ScreenCaptureKit 與 NSPanel。兩者連接 `Packages/CaptionCore` 的音訊正規化、音量型 VAD、重疊分段、序列化 whisper.cpp 推論、臨時／確認字幕及 TXT／SRT 資料模型。`App/Session` 協調取消、跳轉與帶 generation 的字幕事件；`App/Models` 共用下載、儲存與完整性驗證。

引擎固定 **whisper.cpp 1.9.5**／commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`，採官方 `b5454` XCFramework 並鎖定 SHA-256，詳見 [依賴 manifest](ThirdParty/whisper-dependency.json)。本版使用可用的 Metal／Accelerate／CPU；未提供 Core ML encoder 資產，因此**不宣稱 Core ML 加速已啟用或驗證**。

模型包含多語言 tiny、base、small、medium、large-v3-turbo、large-v3，沒有 `.en` 選項。檔案存於 App 沙盒的 `Application Support/LiveCaption/Models`；只有下載且驗證成功才標為可用，支援取消、重試、切換及刪除使用中以外的模型。[模型來源與雜湊](Docs/Models.md) 區分精確檔案大小與估計執行記憶體需求。

第三方引擎與模型的 MIT 聲明保留於 [ThirdParty](ThirdParty) 及 App 內附的 `ThirdPartyNotices.txt`。三個技術參考專案的版本、授權、依賴與不採用項目列於 [原始碼稽核](Docs/ReferenceAudit.md)。未引入 Tauri、React、Python 或遠端推論服務作為 App 執行依賴。

## 驗證與目前限制

- [英文／中文驗證](Verification/languages/README.md)：Tiny、Base 的真人英文／普通話直接及串流辨識，另有六項 iPad Simulator App 整合測試；完整保留誤辨與模型幻覺。
- [延遲優化實測](Verification/latency/README.md)：首次臨時結果與更新更早、忙時避免無效重算、pause 後重用已載入模型；列出轉寫品質、推論成本及測量限制。
- [Bug 自查與修復](Docs/BugAudit.md)：暫停尾音、相鄰字幕漏字、過時結果、模型啟動校驗與媒體生命週期等修正，含修改前失敗及最新回歸證據。
- [核心實測](Verification/engine/README.md)：Apple M4 Pro 上以 tiny 辨識兩段日語、兩段法語真人音訊；包含逐字稿、錯誤率、串流延遲、取消、靜音及約三分鐘重播記憶體紀錄。tiny 在部分樣本有明顯錯誤，不能等同電影字幕品質。
- [Base 模型實測](Verification/base/README.md)：相同四段真人音訊的原文轉寫、SRT、CER／WER、推論時間及 RSS。日語兩段誤差較 tiny 低，法語一段較低、一段較高；不是準確率承諾或即時延遲驗收。
- [App 工作階段整合測試](Verification/session-integration.md)：真實播放器與推論串接、暫停、兩種跳轉、正常 EOF、非重疊匯出、清除與釋放。
- [iPad 模擬器整合測試](Verification/ipad/README.md)：四項真人音訊／影片測試通過，包含預設加速要求的 CPU 備援；不代表實體 iPad 或背景辨識已驗證。
- [模型／媒體測試](Docs/Validation-Models-Media.md)：真實 tiny 下載、取消立即重試、SHA-256、損壞拒絕，以及媒體播放、暫停、跳轉與時間軸。
- [平台可行性與離線 PCM 測試](Docs/PlatformFeasibility.md)：有界收音入口、重採樣、時間戳及獨立 ReplayKit／PiP probe；明確分開編譯證據與真機證據。
- [驗收矩陣](Docs/Acceptance.md)：完整 UI 回歸、兩小時連續運行、大型模型、背景音樂／多人說話、iPad 真機、DRM、全螢幕和混合縮放多螢幕仍有待測項。

開發檢查可執行 `swift test --package-path Packages/CaptionCore`、`bash Scripts/test-models.sh`、`bash Scripts/test-platform-audio.sh` 及 `bash Scripts/test-media.sh /path/to/audio.wav`。可選的 `Scripts/fetch-test-audio.py` 只供開發者取得有授權的測試音訊；App 與 Xcode 建置完全不依賴它。
