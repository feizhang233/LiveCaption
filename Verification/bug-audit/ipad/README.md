# 自查修正後的 iPad Simulator 整合回歸

2026-11-06，`/tmp/live-caption-bug-audit-ipad.xcresult`：**4 項通過、0 失敗、0 skipped**，測試方法合計 **45.757 秒**。環境為 Xcode 27.2、arm64、iOS Simulator 27.0（24A434）、iPad Air 11-inch (M3) 模擬裝置。**沒有實體 iPad 參與**。

三項使用 tiny CPU 執行真人日語 WAV、法語 WAV 與法語 MP4；第四項日語要求預設加速（`requestedUseGPU=true`），本模擬器實際以 CPU 備援（`usingGPU=false`）通過，不能據此宣稱 iPad Metal 已驗證。

本輪日語 CPU 用例另外以 NotificationCenter 發送音訊中斷通知，確認 `ended` 不會錯誤暫停正在播放的工作階段、`began` 會暫停，且可由使用者明確恢復。這驗證 App 的通知處理邏輯，並非實體電話／耳機／系統音訊中斷的裝置測試。實際播放、whisper.cpp 推論、原語言字幕、媒體時間戳、EOF、暫停跳轉與停止釋放模型也全部通過。

`test-summary.json` 與 `test-results.json` 直接由 xcresulttool 匯出；`attachments/` 保存四個原始 XCTest 文字附件及 manifest。四份方便閱讀的字幕 JSON 從實際 stdout 抽取，已逐一確認與原始附件內容一致。`run-excerpt.txt` 保留測試命令、各用例結果及總數。原有 `Verification/ipad/` 歷史資料未改動。

模型仍可能誤辨或產生幻覺，本輪日語輸出仍包含來源錄音沒有的片尾句；完整結果保留在 JSON。通過表示資料流與狀態回歸通過，不代表準確率、實體 iPad 效能、長時間穩定性、跨 App／背景／PiP 或完整 UI 操作通過。JSON 的推論耗時與音訊長度為最後回報視窗，不應當成整段耗時或首字延遲。

模型與媒體生命週期的獨立回歸紀錄位於上一層 `model-management.log` 及 `media-lifecycle.log`。此次僅整理既有成功結果，未額外重跑測試。
