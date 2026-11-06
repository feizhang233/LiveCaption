# iPhone／iOS 適配 · 2026-11-06

主產品擴充為 iPhone／iPad 通用 App，最低 iOS／iPadOS 26.0。保留 `LiveCaptioniPad` scheme 與 `com.example.livecaption.ipad` bundle ID；不建立另一份 App 或搬移既有模型／偏好資料。

## 介面與工程

- App 與 hosted tests 的 device family 均為 `1,2`。iPhone 支援直向與左右橫向；iPad 保留四方向。已核對實際建置產物的 Info.plist。
- 窄版採原生四分頁，每頁使用 NavigationStack；Mac／iPad 寬版保留 NavigationSplitView。匯入媒體及選擇模型共用同一份目的地選擇；工作階段留在 App 層。
- 窄版外距為 16 pt；字幕控制列、模型標題及安裝／重試操作可改為直排。模型操作標籤在 iOS 至少 44 pt 高；大字級字幕歷史將時間碼與文字直排。
- 影片保留 16:9 比例，移除會擠壓手機窄版的 180 pt 最小高度。授權說明 sheet 僅在 Mac 使用最小視窗尺寸，iOS 交由系統 safe area 決定。
- iOS 平台說明涵蓋 iPhone／iPad 與背景停止。保留原有媒體、音訊中斷、記憶體警告及背景釋放機制。
- `Scripts/build.sh` 新增 `ios-simulator`／`ios-device`；舊 `ipad-*` 參數可繼續使用。`Scripts/test-ios-simulator.sh` 接受 iPhone 或 iPad UDID，舊 iPad 測試入口委派至共用 runner。

## 驗證範圍

最終共用 runner 完整執行 **10 通過／0 失敗／0 跳過**；機器可讀結果見 `test-summary.json`／`test-results.json`，六份真實辨識結果與七張原生畫面按 `attachments.json` 對照。最終原始結果保留於本機 `/tmp/live-caption-ios-adaptation-accepted`。

Mac、iOS Simulator 與 iOS device unsigned build 均通過，bundle 檢查見 `builds.json`。UI strict audit 為 0 findings；DESIGN.md 官方 linter 0 errors／0 warnings。plist、shell 語法、Swift 語法與差異空白檢查均通過。

iPhone 17／iOS Simulator 27.0 使用獨立測試裝置與本機既有 tiny 模型、真人音訊素材，沒有新增模型下載。既有六項 App 整合測試確認日／法／英／普通話 WAV、法語 MP4、日語預設加速要求／CPU 備援，以及音訊中斷、播放結束、跳轉與釋放。

新增四項 hosted 原生版面測試：320 × 568 四分頁及模型／設定切換、852 × 393 窄版橫向、320 pt accessibility3 字級且可捲動到底、1024 × 768 寬版側欄。這些畫面由真實 UIHostingController／UIKit 控制項渲染，使用隔離的模型與工作階段偏好。寬版測試在同一 iPhone Simulator 內覆寫尺寸與 size class，不能等同實體 iPad 或系統旋轉驗收。

最初測試以 UIKit 舊 `viewControllers` 屬性讀取新版 Tab API，造成三項測試失敗；改用公開 `tabs`／`selectedTab` API。後續大字級檢查的預先計算座標會受原生標題收合影響，改為等待邊界穩定後核對內容底部可達。兩次失敗的原始結果保留於本機 `/tmp/live-caption-ios-adaptation-tests` 與 `/tmp/live-caption-ios-adaptation-tests-final`；修正後四項版面獨立重跑已通過。

本輪未完成實體 iPhone／iPad 簽署安裝、Metal／溫度／長時間記憶體測量、VoiceOver／實際觸控、外部檔案提供者匯入匯出及系統旋轉完整驗收。沒有 App Store／TestFlight 發布。產品仍限 App 內媒體前景字幕，跨 App 收音及背景持續推論沒有新增。

## 設計一致性

| 原規則 | 本輪處理 |
|---|---|
| 寬版側欄／四個目的地 | 寬版維持側欄；窄版新增同名原生分頁，已同步 DESIGN.md 與 UX-CONTRACT.md |
| 影院式字幕、SF 字體、既有色彩與玻璃面板 | 沿用 Theme.swift、CaptionStage、SessionControls；調整可用寬度與自適應排列 |
| 原生 Picker／Form／List／匯入匯出 | 沿用系統控制項、狀態與操作流程，沒有新增平行實作 |
