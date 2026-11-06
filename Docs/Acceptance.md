# 實作與驗收矩陣

日期：2026-11-06。這份表分開「程式已實作」「實際執行的驗證」與「尚未完成」，不把編譯成功當成裝置功能已通過。測試環境為 Apple M4 Pro／24 GiB RAM／Xcode 27.2，目標 OS 為 macOS 26＋／iOS 26＋／iPadOS 26＋。既有證據保留其原始範圍；0.2.0 新增功能以文末的獨立發布驗證清單為準，目前不將舊結果視為本輪通過。

## 產品功能

| 項目 | 程式狀態 | 已執行驗證 | 尚需完成 |
|---|---|---|---|
| 原生 SwiftUI Mac／iOS targets | 已實作，iPhone／iPad 共用既有 scheme／bundle ID，提供完整 Xcode 專案 | Mac、iOS Simulator 與 iOS device 編譯通過；既有 iPad Simulator 真實推論六項通過（0 失敗／0 跳過） | 最終 UI 回歸、iPhone／iPad 真機簽署及安裝 |
| iPhone／窄版 iOS 介面 | 四分頁導航、自適應控制／模型操作、大字級時間碼直排、影片比例與原生 safe area | iPhone Simulator 六項真人辨識與四項原生版面檢查通過；詳見 [iOS 適配](../Verification/ios-adaptation/README.md) | iPhone／iPad 真機觸控、VoiceOver、系統旋轉與檔案選取／存檔完整驗收 |
| App 圖示／關於資訊／隱私清單 | Mac 10 個圖示 slots、iPad 1024 圖示；版本讀 bundle、原始碼連結；本機 API 用途清單 | 本輪結果見 [收尾驗證](../Verification/app-polish/README.md) | 簽署發行 archive 的隱私報告及商店驗收 |
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
| Mac 浮動字幕 | 無邊框透明文字、文字陰影、滑鼠控制列；NSPanel 拖移、縮放、置頂、穿透、螢幕及尺寸選項；0.2.0 新增大型開關、選單列控制與收起主視窗 | 既有 Mac 編譯、原生透明／窄版／大字體渲染、Session／panel 屬性及尺寸恢復檢查；見 [懸浮字幕驗證](../Verification/floating-captions/README.md) | 0.2.0 背景操作回歸待記錄；既有桌面鎖定時未完成的 hover／拖移／縮放／穿透恢復，以及全螢幕、Spaces、混合 Retina 比例、多螢幕拔插 |
| 語氣詞顯示過濾 | 0.2.0 新增可選開關；明確選擇日／英／法／中文時保守過濾，auto／其他語言不變；原始記錄與 TXT／SRT 保留 | 本輪發布驗證待記錄 | 邊界詞、純語氣詞清空、即時切換、各顯示表面一致性及原始匯出回歸 |
| iPhone／iPad 前景字幕 | App 內媒體架構；未啟動本機媒體 PiP 時進背景安全停止，無假背景音訊 | 既有 iOS Simulator 27.0 六個真實 App 整合測試：日／法／英／普通話 WAV、法語 MP4，加上日語預設加速要求／CPU 備援；6 通過／0 失敗／0 跳過 | 0.2.0 生命週期回歸；實體裝置的音訊工作階段、中斷、背景返回、溫度與記憶體 |
| iPhone／iPad 本機媒體浮動字幕 | 0.2.0 新增系統 PiP；只使用本 App 匯入／播放的媒體，PiP 期間改用 CPU；背景關閉 PiP 時停止辨識 | 本輪建置、模擬器與真機結果待記錄；既有診斷 probe 不是此功能的驗收 | 真機啟動／停止／跳轉、背景持續推論、音訊中斷、模型釋放、耗電及熱降頻；不宣稱背景運行已驗證 |
| iPhone／iPad 其他 App 音訊 | 一般產品**不能擷取 Safari 或其他 App 的聲音**；獨立 ReplayKit probe 保留為研究工具 | 既有 ReplayKit extension＋public-API PiP host 的 Simulator／unsigned device build；27＋ScreenCaptureKit 官方入口與背景 capability 曾查核 | 26 真機 app 音訊／IPC；27 新路徑實作、背景本機推論及真機驗證；不屬於本次本機媒體 PiP 支援 |
| 受保護內容 | 讀取已知保護媒體時拒絕；無音訊時提供可能原因 | 失敗狀態程式路徑、無效檔案讀取測試 | DRM 來源實測；不能僅憑靜音判定 DRM |

## 已知限制與未通過項

1. **完整 UI 驗收尚未結束。** 既有版本已以公開 AVKit wrapper 修正本環境的 SwiftUI `VideoPlayer` metadata crash；Mac 原生 UI 曾完成模型下載、匯入日語音訊、實際字幕及 SRT 匯出。另以實際 App coordinator 與 iPad Simulator XCTest 驗證播放、片尾、跳轉及模型釋放。該次 Mac 在後續 iPad 檔案選取器測試時鎖定，系統收音及最終畫面回歸未完成；這是歷史限制，不能作為目前桌面狀態的判斷。0.2.0 改版仍需另記本輪結果。使用者已同意錄製授權；授權同意不等於 OS 權限已授予。
2. **只有 tiny 與 Base 有真人語音實測。** 日語 CER／法語 WER 見 [tiny 核心結果](../Verification/engine/README.md) 與 [Base 比較](../Verification/base/README.md)；該次 Base 日／法語是直接解碼。新增英文／普通話的兩模型直接與串流結果見 [語言驗證](../Verification/languages/README.md)，包含繁簡字形診斷及實際幻覺。Base 並非每段都較準確；iPad Simulator 六項整合測試通過也不代表準確率達標，完整文字見 [本輪證據](../Verification/languages/ipad/README.md)。不承諾其他模型、影視、所有口音／方言或任意語言的準確率。
3. **三分鐘重播不是兩小時穩定性測試。** 還需真實長片、熱降頻、持續記憶體記錄，以及下載／切換／中斷／停止的長時間壓力測試。
4. **VAD 不能可靠區分音樂與人聲。** 目前為自適應能量門檻，音樂及噪音可能觸發推論；尚未整合／驗證神經 VAD。
5. **iPhone／iPad 跨 App 收音仍未支援；本機媒體 PiP 的真機背景執行尚未驗證。** 0.2.0 的浮動字幕只伴隨本 App 播放的檔案，不擷取 Safari／其他 App 的音訊，也不把系統 PiP 當作任意背景工作的保證。既有 26 版 probe 與 27＋ScreenCaptureKit／`screen-capture` 背景能力查核仍屬獨立研究，未完成跨 App Whisper 背景推論驗證。產品未加入雲端替代，見 [平台稽核](ReferenceAudit.md)。
6. **Core ML 未作為本版可用加速宣稱。** framework 有 loader，但產品未提供對應 encoder 資產；目前實測為 Metal／CPU。

## 證據入口

- [程式整理、責任歸屬與一致性回歸](../Verification/code-cleanup/README.md)
- [iPhone／iOS 通用適配、建置與原生版面驗證](../Verification/ios-adaptation/README.md)
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

## 0.2.0 本輪發布驗證

本輪已通過 47 項核心測試、偏好／顯示整合、34 項 Mac 範圍斷言、15 項 iPhone 模擬器測試及 Mac／iOS device 建置。完整結果與限制見 [0.2.0 驗證](../Verification/release-0.2.0/README.md)。真機 PiP／背景推論未驗證；本機更新後系統收音仍待 macOS 錄製權限重新確認。

| 驗證範圍 | 驗證清單（已完成結果見上方獨立紀錄） |
|---|---|
| Mac／iOS Simulator／iOS device 建置 | 版本／建置號、使用環境、成功或失敗及產物；unsigned device build 不代表真機安裝 |
| Mac 背景操作 | 大型開關；收起／關閉主視窗後辨識與浮窗持續；選單列開始／暫停／停止、穿透恢復與重新開窗；退出時資源清理 |
| 語氣詞顯示 | 日／英／法／中文與區域代碼；auto／未知語言不變；標點、實義詞及引號保護；純語氣詞不回退舊字幕；關閉開關還原顯示；TXT／SRT 保持原文 |
| iOS／iPadOS 本機媒體 PiP | 可見預覽、開始／失敗／停止、CPU 切換與偏好恢復、暫停／跳轉／片尾、背景關閉後停止與模型釋放；既有前景媒體回歸 |
| iPhone／iPad 真機背景 | 裝置、OS、模型、音訊來源、持續時間、是否仍產生字幕、音訊中斷、耗電與溫度；目前未驗證 |
| 發布與本機更新 | GitHub 提交與版本；本機 App 版本、安裝位置、啟動結果及既有模型／設定保留情況 |
