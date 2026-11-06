# 低延遲版 iPad 整合回歸

2026-11-06，最終低延遲核心及模型重用改動後，以 Xcode 27.2、iPad Air 11-inch (M3) 模擬裝置／iOS Simulator 27.0 執行 hosted XCTest。**4 通過、0 失敗、0 跳過**，測試方法合計 46.308 秒。

日語 WAV、法語 WAV、法語 MP4 使用實際 tiny CPU 推論；另一個日語用例要求自動加速並正確採 Simulator CPU 備援。日語 CPU 用例另驗證 interruption ended 不暫停、began 暫停及使用者恢復。各用例檢查原語言、來源時間戳、主 SRT 不重疊、EOF、seek、paused 時鐘及 stop 釋放 context。

[test-summary.json](test-summary.json)、[test-results.json](test-results.json) 及 [原始附件](attachments) 為實際 `.xcresult` 匯出。四份命名 JSON 直接解碼自附件，包含完整辨識文字與後端回報；沒有刪掉誤辨。來源及方法同 [前輪整合測試](../../bug-audit/ipad/README.md)，本次是新增延遲優化後的獨立 run。

原始結果 `/tmp/live-caption-latency-ipad.xcresult`、日誌 `/tmp/live-caption-latency-ipad.log`。建置及 source SHA256 見 [builds.json](../builds.json)。此回歸不量測字幕顯示延遲，不能把 Simulator 數字當作真機 iPad 效能、Metal 或背景能力。
