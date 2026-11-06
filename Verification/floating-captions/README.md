# Mac 懸浮字幕 · 2026-11-06

Mac 浮窗改為無標題列、透明底、置中字幕與深色文字陰影；主介面字幕區維持原本背景。「顯示背景」另存於注入的 AppPreferences。控制列在開啟三秒內、滑鼠移入或 VoiceOver 啟用時顯示；穿透時收起。即時字幕／媒體播放共用浮窗選項，App 選單提供顯示／隱藏及穿透恢復。快捷鍵只在此 App 作用，並非系統全域熱鍵。

最小視窗為 320 × 144 點；浮窗文字沒有額外垂直內距，64 pt 字體在最小尺寸仍保留完整的一行，空間不足時沿用從開頭截斷的規則，完整字幕仍在歷史與匯出中。「重設大小」恢復 760 × 170。視窗幾何由 CaptionPanelController 負責；NSHostingView 只協商以同一個常數指定的最小尺寸，字幕內容不參與理想視窗尺寸調整。重開時重用同一個 host，並修正舊版過矮的儲存位置；延遲完成的 SwiftUI 版面計算也維持相同限制，見 `panel-reopen.log`。

## 驗證

環境：Apple Silicon、Xcode 27.2／27B52、Swift 6.4.2；Mac／iOS Simulator 均為 unsigned build，沒有安裝或發布。

| 檢查 | 結果／證據 |
|---|---|
| Mac 建置 | 通過，`build-mac.log` |
| iOS Simulator 建置 | 通過，`build-ios.log`；共用字幕版面未破壞 iPhone／iPad 編譯 |
| 既有語言／外觀偏好回歸 | 通過，`preferences.log`；測試使用隔離的 UserDefaults |
| 既有平台音訊／浮窗位置計算 | 通過，`platform.log`；包含小螢幕、負座標與過大儲存位置 |
| 原生畫面 | `native-report.json`、PNG 與 `native-render.log`；實際 Tiny／CPU 辨識日語音訊，未注入示範字幕 |
| 原生 Session／NSPanel 狀態 | 同一份原生 harness 驗證無標題列、透明、開啟前穿透／置頂設定、恢復、寬度、隱藏／重開，以及舊 100 點高度修正 |
| UI strict audit | 0 findings，`premium-audit.json` |
| DESIGN.md 官方 lint | 0 errors、0 warnings，`design-lint.json` |
| 差異檢查 | `git diff --check` 通過 |

畫面包含：剛開啟的控制、空白閒置、760 × 170 文字、320 × 170 換行、白色底圖對比、320 × 144 的 32／64 pt、760 × 170 的 64 pt、背景開啟及主頁字幕區對照。空白浮窗沒有持續顯示的波形或提示卡。白色底圖只用於檢查文字陰影，非影片擷取。

模型 SHA-256：`be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`。日語素材 `ja_jp-0.wav` SHA-256：`bd1b9533cfa176b8c2a71ecb4821a02bc86fa368d096373efe8d8dceafb35634`；來源／授權沿用 [Fixtures](../../Tests/Fixtures/README.md)。畫面文字是模型當次實際輸出，含原有誤辨，不代表辨識品質改善。未下載模型、未錄製系統音訊、未變更使用者的顯示或輔助使用設定；離屏原生視窗保持原前台 App。

## 限制

桌面鎖定，Computer Use 無法解鎖。因此實際滑鼠 hover、拖移／縮放、跨 App 點擊穿透及 App 選單鍵盤操作尚未驗收。全螢幕影片、Spaces、多螢幕及混合縮放仍待實測。原生 panel 屬性／方法通過不等於以上互動已通過。

減少透明度與提高對比的既有背景覆寫分支保留，但系統環境值唯讀，本輪未變更全域設定來模擬，沒有把該兩項列為畫面驗收通過。無簽署建置也不等於安裝、簽署或發行完成。
