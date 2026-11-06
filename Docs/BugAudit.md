# Bug 自查與修復

日期：2026-11-06。本輪檢查共用辨識核心、模型管理、媒體讀取、App 工作階段、Mac 收音／浮窗，以及獨立 ReplayKit／PiP 診斷工具。下列項目為具體缺陷；程式與驗證證據會一併保留。

## 播放與工作階段

| 問題 | 修復 | 證據 |
|---|---|---|
| App 暫停時未送出最後一次輪詢之後已播放的音訊；實際日語測試殘留 829 samples，約 52 ms | 等待在途讀取完成，再把 reader 補齊到實際暫停位置，最後確認字幕；原生播放器暫停與 EOF 也使用完整 drain | [修復前失敗](../Verification/bug-audit/pause-before.json)、[日語回歸](../Verification/bug-audit/session-ja.json) |
| 固定以播放時鐘前進超過 1.2 秒判斷跳轉；正常播放遇到較晚輪詢或較快播放速度可能被誤判，丟棄語音 | 與實際單調時鐘間隔、播放速率比較，同時保留原生 seek 通知與反向跳轉檢測 | SessionHarness 模擬一次 1.4 秒延遲，驗證辨識 generation 不變；另測真正 seek 與直接跳至 EOF |
| 原生播放器暫停後，App 的播放鍵仍顯示暫停，需再按一次才能繼續 | 播放鍵與目前媒體播放狀態一致，支援一次操作恢復原生暫停 | SessionHarness 原生暫停後呼叫與 UI 共用的 togglePlayback |
| iPad 音訊中斷通知未區分開始／結束；結束通知也可能暫停正在播放的內容 | 只處理 `.began`，維持手動恢復 | iPad hosted XCTest 注入公開中斷通知，檢查 ended 不暫停、began 暫停及明確恢復 |

## 辨識核心

修正三類已重現的缺陷：前段結束後 80 ms 內的新短句被丟棄、150 ms 內不重疊的重複詞被去掉；較新的臨時任務已排隊時仍顯示舊的在途結果；巨大有限時間戳轉 Int64 崩潰。現在只在實際時間重疊處去重、以排程 revision 淘汰舊 partial，並只轉換有界的時間餘數。

另將取消旗標改為每次操作獨立，避免遲到的取消回呼影響後續推論。此項是並發隔離加固，有確定性交錯單測與真實 C 取消／卸載／重載驗證，沒有聲稱在完整推論中現場復現該競態。

**30 項核心測試通過**，修改前失敗／崩潰及修改後紀錄見 [核心自查](../Verification/engine/bug-audit/README.md)。

## 模型與媒體

- 啟動時同步保留全部待驗證模型，避免掃描 Task 尚未執行時誤啟動下載或刪除。
- 斷鏈的模型符號連結可被識別及刪除，修正無法重試；儲存目錄建立失敗時不再啟動下載。
- reader 非同步 open 加入 revision 與取消檢查，舊工作不會在 close 後復活，也不會清掉更新的 reader；失敗替換不再留下舊 PCM。
- 匯入失敗會清除時長、播放位置及播放狀態；空播放器不再顯示假播放；過期 seek 回呼不會覆寫新媒體位置。
- PCM frame 數先限幅再轉整數，避免巨大有限時間溢位；controller 銷毀會先停用 player，reader 關閉後才釋放 security scope。

[模型回歸](../Verification/bug-audit/model-management.log) 與 [媒體回歸](../Verification/bug-audit/media-lifecycle.log) 全部通過，包含實際 MP4、48 kHz stereo、共 32 次 open 途中 close，以及保留播放器引用時銷毀 controller。外部 security-scoped 權限實際授權不屬於命令列測試範圍。

## 平台與診斷工具

修正小螢幕／部分離屏浮窗恢復，以及獨立 ReplayKit probe 的缺口／重疊封包時間戳與 PiP 暫停後繼續送幀；補強框架回呼執行緒及錯誤清理。離線轉換、封包、幾何回歸及 probe 兩種架構編譯通過；PiP 互動只有編譯證據，詳見 [平台自查](../Verification/platform-bug-review.md)。

## 最終整合結果

- macOS App 開發用 ad hoc 簽署建置通過，iPad device unsigned build 通過。
- iPad Simulator **4 通過／0 失敗／0 跳過**，45.757 秒。包含真人日語／法語 WAV、法語 MP4、CPU 備援與音訊中斷通知回歸，見 [本輪結果](../Verification/bug-audit/ipad/README.md)。
- [法語影片完整 Session 回歸](../Verification/bug-audit/session-fr.json) 使用最後修復的全部程式碼，驗證輪詢延遲、暫停尾音、原生控制單次恢復、正常／直接跳轉 EOF、歷史及模型釋放。
- [建置版本與來源雜湊](../Verification/bug-audit/builds.json)。早先 [日語 Session](../Verification/bug-audit/session-ja.json) 執行於後續核心改動之前；最終日語資料流由本輪 iPad 測試再次覆蓋。

## 驗證範圍

真人音訊回歸使用已校驗的 multilingual tiny、日語 FLEURS 音訊，以及法語錄音製作的 H.264／AAC MP4。影片只有純色畫面，聲音為實際真人錄音。測試不向遠端服務傳輸音訊，也不注入字幕文字。

本輪不把離線 adapter 測試或編譯成功當作 Mac 系統收音權限、全螢幕、多螢幕、實體 iPad、ReplayKit／PiP 背景辨識的實測。這些項目的狀態仍以 [驗收矩陣](Acceptance.md) 為準。
