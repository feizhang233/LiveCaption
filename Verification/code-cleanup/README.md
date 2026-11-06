# 程式整理與一致性檢查 · 2026-11-06

本輪從現有未提交版本檢視 UI、工作階段、模型／媒體、核心與支援腳本，整理重複實作及責任歸屬，保留先前 iOS 適配與啟用範圍功能。

## 整理結果

| 範圍 | 結果 |
|---|---|
| 導航與頁面 | RootView 從 284 行縮至 114 行，負責導航和系統選檔／匯出呈現；CaptionWorkspaceView 用同一套字幕、來源、控制、狀態與歷史組合即時／媒體頁，並持有媒體拖曳狀態 |
| 自適應 UI | AdaptiveControls 統一原先分散的 ViewThatFits＋HStack／VStack；CaptionPageContent 與 CaptionLayout 統一頁寬、捲動和外距；TranscriptRow 共用主字幕／其他結果的時間碼與大字級排列 |
| 匯出 | CaptionExport 將內容快照、格式、類型與檔名放在同一份狀態；CaptionDocument 獨立負責 FileDocument，移除兩套匯出準備流程 |
| 偏好 | AppPreferences 從視覺主題檔移至 Session，外觀、來源語言與預設模型選擇統一使用傳入的 UserDefaults；一般 App 仍使用 standard，測試可隔離 |
| 模型／媒體 | 模型完整性驗證共用 detached task 與取消傳遞；移除未使用的掃描 Task 控制代碼；共用解碼器及播放狀態清理，對外可觀察狀態由 MediaController 唯一寫入 |
| 工作階段／核心 | 移除無呼叫者的 clearError／panel.isVisible；iOS 生命週期與 Mac watchdog 分平台編譯；StreamingTranscriber.reset() 移除未使用參數，等待者完成流程集中 |
| 腳本／工程 | 三個 App harness 編譯流程共用 test-support.sh；移除 project.yml 重複的檔案分享鍵，保留 Info.plist 作唯一來源；重新生成 Xcode 工程 |

保留仍被 App、CaptionProbe 或回歸測試使用的兩種事件串流、時間軸及平台 API。重複控制項排列只集中到既有原生 ViewThatFits 行為，沒有另建布局引擎。另在 runtime 檢查發現先前 `iphone.and.ipad` 圖示不存在，已改為有效的媒體圖示；補跑版面後沒有該警告。

## 已執行驗證

| 檢查 | 結果／證據 |
|---|---|
| 核心 Swift package | 39 通過／0 失敗，`core-tests.log` |
| 模型管理 | 全部通過，含校驗、取消／重試、啟動競爭與無效檔案，`model-checks.log` |
| 媒體 | 原始日語 WAV 與 48 kHz stereo 解碼／播放／暫停／seek／失敗狀態／釋放通過，`media-checks.log` |
| 語言／外觀偏好 | 持久化、全部 7 個外觀欄位的隔離載入／修改／恢復、standard 未被修改，`language-settings.log` |
| 啟用範圍 | 44 項規則＋34 項真實模型工作階段檢查通過，`scope-policy.log`／`scope-session.log` |
| iPhone Simulator 整合 | 6 真人辨識＋4 原生版面，10 通過／0 失敗／0 跳過，`ios-test-summary.json` |
| 最後版面補查 | 圖示整理後單獨重跑 4 項原生版面通過，`ios-layout-final-summary.json`；7 張圖在 `native-ios/` |
| Mac／iOS device build | unsigned build 通過，`mac-build.log`／`ios-device-build.log`；Simulator build 由完整 hosted test build 通過 |
| Mac 原生渲染 | 11 張離屏原生畫面在 `native-mac/`，涵蓋六分類、窄版與短視窗捲動；分類原生 action 成功，前台 App 保持不變，`native-mac.log` |
| 靜態檢查 | UI strict audit 0 findings；DESIGN.md linter 0 errors／0 warnings；Swift／shell 語法、plist 與 git diff --check 通過 |

命令入口為 `swift test --package-path Packages/CaptionCore`、`Scripts/test-models.sh`、`Scripts/test-media.sh`、`Scripts/test-language-settings.sh`、`Scripts/test-caption-scope.sh`、`Scripts/test-caption-scope-session.sh`、`Scripts/test-ios-simulator.sh` 及 `Scripts/build.sh`。本輪核心 scratch 目錄為 `/tmp/live-caption-refactor-core-tests`；App harness 共用其 Debug 產物。測試素材沿用本機有來源聲明與固定 SHA-256 的既有 tiny／真人錄音，沒有重新下載模型。

日誌中的專案／家目錄元資料在此目錄泛化為 `<PROJECT_ROOT>`／`<HOME>`；原始完整副本仍保留於 `/tmp/live-caption-refactor-*`。完整 iOS 結果為 `/tmp/live-caption-refactor-ios/Integration.xcresult`，最後版面補查為 `/tmp/live-caption-refactor-layout-final.xcresult`。

## 畫面與限制

已檢視代表性的 iPhone 320 pt、模型／設定、大字級、橫向與寬版側欄，以及 Mac 通用／啟用範圍寬窄畫面。寬版 iPad 測試是在 iPhone Simulator 覆寫尺寸與 size class；Mac 使用離屏 NSHostingView。原生渲染及程式選擇／捲動檢查不等同真機觸控、VoiceOver、系統旋轉或實際檔案提供者的匯入／存檔驗收。

媒體檢查仍有既有 AVFoundation macOS 27 API 棄用警告；Xcode 的 hosted build 仍顯示未使用 AppIntents 時跳過 metadata extraction 的工具訊息，沒有編譯失敗。本輪未發布、簽署安裝、改動資料保留政策或執行長時間／熱測量。

## 設計一致性

| 規則 | 核對 |
|---|---|
| 原生四目的地與窄版／寬版導航 | 保留；RootView 唯一持有選擇 |
| 既有色彩、字體與玻璃面板 | 保留 Theme.swift；抽取共同排列與偏好持久化，不另建樣式系統 |
| 主字幕與重播結果 | 共用 TranscriptRow；主歷史、alternative 資料與 SRT 不重疊政策保留 |
| 文檔中的 canonical owner | DESIGN.md、UX-CONTRACT.md 與 STRUCTURE.md 已同步更新新責任歸屬 |
