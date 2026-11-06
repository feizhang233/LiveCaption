# CaptionCore 自查與修正

日期：2026-11-06。範圍：`Packages/CaptionCore` 的推論取消、串流排程、文字／時間邊界。沒有修改 App／Session，也沒有新增模型下載。

## 已重現的缺陷

| 程度 | 問題與觸發方式 | 修正 | 修改前證據 |
| --- | --- | --- | --- |
| P1：字幕文字遺失 | 音訊視窗重疊時，前一段結束後 80 ms 內的新短句被直接略過；150 ms 內再次說出的相同詞，即使字幕時間不重疊，也會被當成重複文字刪掉。測試中 1.01 秒的 `Oui.` 與 1.05 秒的第二個 `Bonjour.` 都消失。 | 去重只適用於實際時間重疊，移除跨越確認字幕結束點的 80／150 ms 容差；既有日法重疊消除測試仍通過。 | `baseline-boundaries.log`：兩個文字邊界案例失敗。 |
| P1：可輸入資料導致崩潰 | `CaptionExporter.timestamp(Double.greatestFiniteMagnitude)` 先乘以 1000，再轉 Int64；有限輸入也會溢位並 trap。 | 先拆整秒與毫秒，只把小於 60／1000 的餘數轉 Int；保留正常時間的毫秒捨入與進位。 | `baseline-timestamp.log`：xctest unexpected signal 5，Double→Int64 fatal error。 |
| P2：過時字幕閃回 | 第一筆臨時推論還在執行時，較新視窗已等待處理，舊結果仍被發布。可控排程測試收到 `obsolete hypothesis` 後才收到 `newer hypothesis`。 | 每個排程視窗帶遞增序號與語言快照；只有仍為最新視窗的臨時結果能發布。確認字幕仍依順序完成。 | `baseline-boundaries.log`：過時 partial 案例失敗。 |

## 取消隔離加固

取消旗標由整個 engine 共用，改成每次載入／推論各自持有，另外用有鎖的 slot 指向目前操作。舊 flag 被取消或舊操作清理時，不會改寫下一次操作的 flag。模型卸載後若新載入失敗，加速狀態也會回到未載入狀態。

此項是隔離加固，**沒有宣稱在完整真實推論中重現了舊任務誤取消新任務的現場競態**。新增的交錯測試驗證 flag／slot 隔離契約；另以實際 whisper.cpp 測試取消、卸載、重載及再次成功辨識，結果在 `cancellation-after.json`。Swift 的取消處理器可以與 operation 並行執行，相關語義見[官方實作與 API 說明](https://github.com/swiftlang/swift/blob/main/stdlib/public/Concurrency/TaskCancellation.swift)。

## 驗證結果

- `core-tests-after.log`：**30 項測試，0 失敗**，其中新增 6 項針對這次缺陷／隔離契約的回歸測試。
- 既有音訊下混、重採樣、靜音／低音量、seek generation、排程過載、取消、重複文字及跨 seek 歷史規則均保留通過。
- `cancellation-after.json`：`cancellationObserved=true`、`unloadedAfterCancellation=true`，重載後產生 1 段真實辨識文字。
- 此輪沒有重新跑長時間效能測試；實際 App／iPad 整合測試由主工作流程在相同最終產物上執行，不能由單元測試結果推定已通過。

最終共用開發產物：`/tmp/live-caption-core-build/out/Products/Debug`。
