# 圖示與次要收尾 · 2026-11-06

本輪補齊 Mac／iPad App 圖示、關於頁版本／建置編號與原始碼連結、模型下載 User-Agent 版本，以及 required-reason API 隱私清單。保留既有啟用範圍與設定分類修改；沒有把平台或長時間待驗收項目標成完成。

## 資產與工程

- 母圖與生成提示詞在 [Design/AppIcon](../../Design/AppIcon/README.md)，使用內建 imagegen 生成，再以內建 sips 匯出尺寸。iPad 母圖 1024 × 1024 且無 alpha；Mac 母圖為透明外緣的圓角圖塊。不是 Icon Composer 分層圖示。
- `bash Scripts/generate-app-icons.sh` 成功匯出 1 個 iPad single-size slot 與 10 個 Mac slots；`bash -n` 通過。以 sips 逐一讀取尺寸／alpha 並對照 Contents.json，11 個 slots 全部符合。
- 以既有 XcodeGen 2.46.0 重新生成主工程，兩個 App target 均包含 Assets.xcassets 與 PrivacyInfo.xcprivacy。版本真值仍是 0.1.0／build 1。
- `bundle-checks.json` 檢查三個實際產物：Mac 有 AppIcon.icns；iPad 有 icon Info.plist 設定及已生成的實際 PNG；各自均有 Assets.car、第三方 notices 與逐位元等同來源的隱私清單。

## 建置與回歸

| 檢查 | 結果與證據 |
|---|---|
| Mac unsigned build | exit 0，`build-mac.log` |
| iPad Simulator unsigned build | exit 0，`build-ipad-simulator.log` |
| iPad device unsigned build | exit 0，`build-ipad-device.log` |
| 既有模型管理檢查 | exit 0，`model-checks.log`：SHA-256、大小／損壞／symlink 拒絕、啟動競爭、選擇與刪除鎖等全部通過；本輪未再次下載模型 |
| UI strict audit | 0 findings，`premium-audit.json` |
| DESIGN.md 官方 linter 0.4.0 | 0 errors、0 warnings，`design-lint.json`；沿用既有工具，未新增依賴 |
| PrivacyInfo.xcprivacy | `plutil -lint` 通過；用途／官方依據見 [Privacy.md](../../Docs/Privacy.md) |
| 差異與腳本語法 | `git diff --check`、`bash -n Scripts/generate-app-icons.sh` 通過 |

建置命令分別是 `CAPTION_BUILD_DIR=DerivedData bash Scripts/build.sh mac`、`CAPTION_BUILD_DIR=DerivedData-iPad bash Scripts/build.sh ipad-simulator` 及 `CAPTION_BUILD_DIR=DerivedData-iPadDevice bash Scripts/build.sh ipad-device`，實際環境值為對應的專案絕對路徑。Xcode log 含 generic destination 的 operatingSystemVersion 診斷，沒有程式編譯或資產警告／錯誤。

首次受限環境嘗試因系統快取／服務不可用而失敗；重新使用正常 Xcode／Swift 系統服務後通過。前次失敗原始 log 留在被排除的 `BuildReports/Logs/app-polish`，沒有改寫成程式失敗或成功證據。公開 log／audit 中的專案與家目錄路徑僅作元資料泛化，原始副本也保留於上述本機目錄。

## 畫面檢查

以目前 SwiftUI 原始碼與 AppKit 渲染關於頁 800 × 650、420 × 650、420 × 650 深色，共三張 PNG；另渲染通用分類作同層樣式對照（`general-sibling.png`）。已逐一檢視：版本顯示 0.1.0、建置版本 1，窄版分類選單、連結及授權按鈕完整，說明文字正常換行；深色外觀可讀。

渲染 harness 在本輪建置 App 的暫存副本內執行，使用真正 bundle metadata 及 notices／privacy resources；啟動時對版本與資源存在作 precondition，未提供版本值給畫面。視窗禁止啟用並位於螢幕外；使用隔離的模型／工作階段 defaults，不下載模型、不收音、不請求瀏覽器授權。前台 App 保持不變。`render.log` 含系統暫存 App sandbox extension 訊息，但渲染、preconditions 與程序 exit 0 均成功。

這些是實際原生控制項的離屏畫面，不等同桌面鍵盤／點選或系統權限對話框驗收；本輪未以點擊專案連結開啟外部瀏覽器，也未重跑辨識品質或長時間測試。iPad 真機安裝、Mac 系統收音／全螢幕／多螢幕、兩小時連續運行與發行 archive／商店驗收仍按 [Acceptance](../../Docs/Acceptance.md) 保留待測。
