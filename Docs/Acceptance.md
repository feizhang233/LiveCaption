# 實作與驗收矩陣

日期：2026-11-06。這份表分開「程式已實作」「實際執行的驗證」與「尚未完成」，不把編譯成功當成裝置功能已通過。測試環境為 Apple M4 Pro／24 GiB RAM／Xcode 27.2，目標 OS 為 macOS 26＋／iPadOS 26＋。

## 產品功能

| 項目 | 程式狀態 | 已執行驗證 | 尚需完成 |
|---|---|---|---|
| 原生 SwiftUI Mac／iPad targets | 已實作，提供完整 Xcode 專案 | Mac、iPad Simulator 與 iPad device 編譯通過；iPad Simulator 真實推論六項通過（0 失敗／0 跳過） | 最終 UI 回歸、iPad 真機簽署及安裝 |
| whisper.cpp 本機原文辨識 | 已整合固定官方 C API／XCFramework，`translate=false` | tiny 與 Base＋Metal 日語／法語樣本；另有英文／普通話 16 次直接及串流推論；tiny 取消／釋放／重新載入成功 | 其餘四種模型實際推論；影視、不同口音／方言與其他語言品質 |
| 加速與備援 | Metal／Accelerate／CPU 路徑；GPU 配置探測 | 開發機 Metal、CPU 與受限 GPU 環境備援檢查；iPad Simulator 預設 GPU 要求安全備援 CPU | Core ML encoder 未整合；實體 iPad Metal／不同 GPU／RAM |
| 模型管理 | 六種多語言目錄、進度、空間、取消、重試、驗證、切換、刪除 | 真正 tiny 下載與校驗；取消後立即重試；損壞／符號連結拒絕；Mac 及 iPad 模擬器 App 內 tiny 下載、驗證與選擇已完成 | 大型下載、磁碟耗盡、網路中斷及 iPad 真機 |
| 分段與排程 | 自適應能量 VAD、前滾、重疊、去重、臨時／確認字幕、序列推論及有界佇列 | 核心邊界測試；三分鐘真人片段重播；靜音不觸發推論；低音量法語 | 電影／動漫／課程、背景音樂、多人重疊及長句字幕閱讀品質 |
| 音訊轉換 | 共用 PCMNormalizer、明確混音、按 converter 要求提供 frames | 右聲道語音、48／44.1／16 kHz、100 秒離線 PCM、格式切換 | 不同硬體音訊路由及系統收音實際格式 |
| 過載與取消 | 入口最新 8 塊音訊；推論有界佇列；略過秒數提示；generation 失效 | 入口淘汰／終止測試；慢推論淘汰；seek 後在途及已排隊事件失效 | 真實熱降頻、記憶體壓力和兩小時連續操作 |
| 本機音訊／影片播放 | AVFoundation 播放與按播放時間供應 PCM；原生播放器介面 | 真人日語 WAV、法語 H.264/AAC MP4、48 kHz stereo 的實際讀取／播放／暫停／跳轉；完整 SessionController 測試 | 真機 iPad 與其他媒體格式端到端字幕；最終影片 UI 回歸 |
| TXT／SRT 匯出 | 確認字幕匯出及媒體時間戳 | 核心格式、非重疊時間軸、保留重播文字；Mac 原生 UI 實際匯出 SRT 並讀回 | iPad UI 存檔及外部字幕播放器對齊 |
| Liquid Glass／外觀 | 原生玻璃控制面板、字幕樣式／字體／色彩／行數、主題與透明度 | 原生 API 編譯；Mac 頁面、iPad 模擬器橫直向與模型頁已視覺檢查 | 低透明／提高對比、長字幕、鍵盤、窄視窗及 iPad 分割畫面／多視窗完整矩陣 |
| Mac 系統收音 | ScreenCaptureKit，無虛擬驅動 | 轉換 adapter 與時間戳離線測試 | 真正權限提示／拒絕／撤銷、系統音訊與實際播放來源 |
| Mac 浮動字幕 | NSPanel 拖移、縮放、置頂、穿透與螢幕選擇 | 平台碼編譯 | 全螢幕影片、Spaces、混合 Retina 比例、多螢幕拔插及穿透恢復 |
| iPad 前景字幕 | App 內媒體架構；App 進背景安全停止，無假背景模式 | iOS Simulator 27.0 執行六個真實 App 整合測試：日／法／英／普通話 WAV、法語 MP4，加上日語預設加速要求／CPU 備援；6 通過／0 失敗／0 跳過 | 實體 iPad 的音訊工作階段、中斷、背景返回、溫度與記憶體 |
| iPad 跨 App／字幕 PiP | **只交付獨立診斷 probe，沒有產品化背景推論** | ReplayKit extension＋public-API PiP host 的 Simulator／unsigned device build；27＋ScreenCaptureKit 官方入口與背景 capability 已查核 | 26 真機 app 音訊／IPC／PiP；27 新路徑實作、背景本機推論及真機驗證 |
| 受保護內容 | 讀取已知保護媒體時拒絕；無音訊時提供可能原因 | 失敗狀態程式路徑、無效檔案讀取測試 | DRM 來源實測；不能僅憑靜音判定 DRM |

## 已知限制與未通過項

1. **完整 UI 驗收尚未結束。** 已以公開 AVKit wrapper 修正本環境的 SwiftUI `VideoPlayer` metadata crash；Mac 原生 UI 已完成模型下載、匯入日語音訊、實際字幕及 SRT 匯出。另以實際 App coordinator 與 iPad Simulator XCTest 驗證播放、片尾、跳轉及模型釋放。Mac 在後續 iPad 檔案選取器測試時鎖定，尚需解鎖後完成系統收音及最終畫面回歸。使用者已同意錄製授權；授權同意不等於 OS 權限已授予。
2. **只有 tiny 與 Base 有真人語音實測。** 日語 CER／法語 WER 見 [tiny 核心結果](../Verification/engine/README.md) 與 [Base 比較](../Verification/base/README.md)；該次 Base 日／法語是直接解碼。新增英文／普通話的兩模型直接與串流結果見 [語言驗證](../Verification/languages/README.md)，包含繁簡字形診斷及實際幻覺。Base 並非每段都較準確；iPad Simulator 六項整合測試通過也不代表準確率達標，完整文字見 [本輪證據](../Verification/languages/ipad/README.md)。不承諾其他模型、影視、所有口音／方言或任意語言的準確率。
3. **三分鐘重播不是兩小時穩定性測試。** 還需真實長片、熱降頻、持續記憶體記錄，以及下載／切換／中斷／停止的長時間壓力測試。
4. **VAD 不能可靠區分音樂與人聲。** 目前為自適應能量門檻，音樂及噪音可能觸發推論；尚未整合／驗證神經 VAD。
5. **iPad 跨 App 全本機方案尚未驗證。** 26 版 probe 不把 App Group 或 PiP 當作背景推論保證；27＋已新增 ScreenCaptureKit 與正式 `screen-capture` 背景能力，但本次僅查核公開文件／SDK，未實作或驗證 Whisper 持續背景推論。產品未加入雲端替代，見 [平台稽核](ReferenceAudit.md)。
6. **Core ML 未作為本版可用加速宣稱。** framework 有 loader，但產品未提供對應 encoder 資產；目前實測為 Metal／CPU。

## 證據入口

- [英文與普通話的實際辨識、語言設定與六項 iPad 整合測試](../Verification/languages/README.md)
- [延遲優化與維護結構](../Verification/latency/README.md)：新舊版本相同真人音訊對比；模組維護入口見 [STRUCTURE](../STRUCTURE.md)。
- [Bug 自查、修復與最新 30 項核心／4 項 iPad 整合回歸](BugAudit.md)
- [建置環境、產物簽署狀態與來源雜湊](../Verification/builds.json)
- [核心真人音訊、SRT、延遲、記憶體與測試紀錄](../Verification/engine/README.md)
- [Base 四段真人音訊、CER／WER 與 tiny 比較](../Verification/base/README.md)
- [App 工作階段整合](../Verification/session-integration.md)
- [iPad Simulator 真實推論](../Verification/ipad/README.md)
- [模型下載與媒體播放時間軸](Validation-Models-Media.md)
- [平台可行性、probe 建置與真機測試步驟](PlatformFeasibility.md)
- [模型固定來源、位元組與 SHA-256](Models.md)
- [參考專案版本、授權及實際程式碼差異](ReferenceAudit.md)
- [測試音訊來源與 CC BY 4.0 聲明](../Tests/Fixtures/README.md)

完成後續測試時應記錄裝置、OS、模型、測試來源、實際結果與證據，再更新對應列；不要只改成「已完成」。
