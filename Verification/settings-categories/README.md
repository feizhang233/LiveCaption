# 設定分類整理 · 2026-11-06

設定改為六個功能分類：通用、字幕樣式、啟用範圍（僅 Mac）、辨識與效能、隱私與資料、關於。上方使用原生分類 Picker；空間足夠時顯示分段選項，窄視窗改用含標籤的選單。每次只顯示目前分類，grouped Form 負責捲動。字幕樣式內分開文字／排版與背景，辨識內分開加速與執行狀態。

原有設定、資料綁定及權限操作保留。`CaptionScopeSettingsState` 由設定頁持有，讓未提交的網站文字、錯誤及進行中的權限請求在切換分類後仍保留於記憶體；沒有新增持久化瀏覽資料或自動授權。

已執行：

- Mac unsigned build 通過：`build-mac.log`。
- iPad Simulator unsigned build 通過：`build-ipad.log`，iPad 排除 Mac 專屬啟用範圍。
- UI strict audit：0 findings，`premium-audit.json`。
- 官方 DESIGN.md linter：0 errors、0 warnings，`design-lint.log`。使用本機既有 `@google/design.md` 0.4.0；沒有新增依賴。
- 六個 Mac 分類的 800 × 650 原生 NSHostingView 畫面，以及 420 pt 窄版字幕／啟用範圍、420 × 420 啟用範圍，已產生並逐一檢視，共九張 PNG。寬版顯示分段分類列，窄版顯示選單，未見重疊或裁掉分類入口。
- 另以原生 NSSegmentedControl action 從通用切到關於，並在 420 × 420 視窗透過原生 NSScrollView 捲至啟用範圍底部；兩張追加 PNG 確認內容確實切換、網站輸入與權限入口可捲動到達，分類入口維持可見。共十一張 PNG，結果見 `render.log`／`render-report.json`。
- 獨立程式審查確認原有控制項與資訊完整保留，分類切換只改變顯示，網站草稿及權限請求狀態的持有者在分類外。

PNG 來自真實 SwiftUI／AppKit 控制項的離屏視窗，不是設計稿，也不代表已完成使用者桌面上的點選、鍵盤、系統選單或權限對話框驗收。渲染 harness 使用私有 UserDefaults suite、禁止啟用的離屏視窗與測試清單，不變更標準偏好、不改變前台、不下載模型、不收音、不請求瀏覽器權限。未重跑音訊／模型辨識測試，因本次僅整理設定 UI 與暫存輸入狀態；前一輪功能驗證見 `../caption-scope/`。
