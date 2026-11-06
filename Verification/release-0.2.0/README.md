# 0.2.0（build 2）驗證紀錄

2026-11-06，本機 Xcode 27.2／Swift 6.4.2。結果摘要見 [results.json](results.json)，本輪產品來源見 [source-sha256.txt](source-sha256.txt)。

| 項目 | 結果 |
|---|---|
| CaptionCore | 47 項通過，0 失敗；包含 8 項語氣詞邊界案例 |
| 偏好與顯示整合 | 開關／來源保存、隔離 defaults、顯示切換、純語氣詞清空與原始 TXT／SRT 保留通過 |
| Mac 啟用範圍 | 34 項斷言通過；真實 Tiny 模型配合受控靜音 adapter，沒有擷取使用者音訊 |
| Mac 建置 | 工作目錄與 staged tree `afeadaece1b0a39a8c8193e4fe4fd99450384315` 的乾淨 archive 均通過；archive 另放入既有已校驗官方 framework，未納入 Git |
| iPhone 模擬器 | 15 項通過、0 失敗、0 略過：6 項真人媒體推論、4 項版面、5 項 PiP 控制／字幕像素測試 |
| iOS device SDK | unsigned build 通過；iPhone＋iPad、最低 iOS 26、單一視窗及 audio 背景模式均從成品核對 |
| Mac 版面 | 660 寬主頁、420 寬工作區與 360 寬選單離屏原生渲染並目視檢查；短視窗垂直捲動正常，無水平裁切 |
| UI 靜態稽核 | strict audit 0 errors／warnings；此結果不能代替原生實際互動 |
| 本機更新 | 安裝 0.2.0（2）並驗證簽章；實際主頁大型開關、語氣詞開關、系統音訊來源與既有 Large v3 模型均可見 |

Mac 更新前的 78 段字幕已匯出至被 Git 排除的私人備份；舊 App 亦保留於本機。使用者字幕、模型、私人路徑及已安裝 App 不隨原始碼發布。公開文字證據依 [倉庫規則](../../Docs/Repository.md) 泛化本機路徑，原件另存私人備份。

## 明確未驗證／待完成

- 本輪模擬器回報不支援真正 PiP 啟動。15 項測試驗證控制、有限媒體時間軸、取消回呼及實際字幕像素更新，**不代表真機 PiP 或背景 Whisper 已通過**。仍需 iPhone／iPad 實機檢查背景持續辨識、音訊中斷、溫度及耗電。
- Mac 更新後，系統錄製權限雖顯示開啟，ScreenCaptureKit 仍回傳 TCC 拒絕。已請使用者重新確認權限；本輪沒有宣稱更新後的系統收音已恢復。實際選單列點擊、關閉主窗後持續收音及完整 Spaces／全螢幕矩陣仍待互動驗證。
- 乾淨 archive 的 Mac 建置之後，僅另修正 iOS scene manifest／工程設定及補入測試文件；Mac 執行邏輯沒有再修改。unsigned device build 不等同真機安裝、TestFlight 或 App Store 發布。

離屏截圖僅驗證版面幾何；非作用中 AppKit 視窗呈中性色，不代表實際選單彈出時的色彩。
