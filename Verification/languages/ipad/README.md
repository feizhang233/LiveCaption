# 六項 iPad 模擬器真實辨識測試

2026-11-06，hosted XCTest 執行 **6 項、通過 6 項、失敗 0 項、跳過 0 項**，測試方法合計 **69.089 秒**。原始結果是 `/tmp/live-caption-languages-ipad.xcresult`；本目錄保存匯出的 `test-summary.json`、`test-results.json`、六份 XCTest 原始文字附件及對照 manifest、stdout 節錄與六份實際辨識 JSON。六份 JSON 都已逐一與 stdout／附件比對一致。

環境為 Xcode 27.2、iOS Simulator 27.0（24A434）、arm64、iPad Air 11-inch (M3) 模擬裝置，公開顯示名稱 `iPad Simulator`。**沒有實體 iPad 參與**；JSON 的 `device: iPad` 是模擬器回報的裝置類別，不能當作真機證明。

| 測試資料 | 手動語言 | 要求→實際推論 | 確認字幕數 | 實際結果 |
|---|---|---|---:|---|
| 真人英文 WAV，10.56 s | en | CPU→CPU | 2 | [en_us-0.json](en_us-0.json) |
| 真人普通話 WAV，10.38 s | zh | CPU→CPU | 4 | [cmn_hans_cn-0.json](cmn_hans_cn-0.json) |
| 真人日語 WAV，10.44 s | ja | CPU→CPU | 2 | [ja_jp-0.json](ja_jp-0.json) |
| 真人日語 WAV，10.44 s | ja | 自動加速→CPU 備援 | 2 | [ja_jp-0-automatic-acceleration.json](ja_jp-0-automatic-acceleration.json) |
| 真人法語 WAV，10.20 s | fr | CPU→CPU | 2 | [fr_fr-0.json](fr_fr-0.json) |
| 同一法語錄音的 MP4，10.20 s | fr | CPU→CPU | 2 | [fr-native-video.json](fr-native-video.json) |

全部使用經 SHA256 校驗的 multilingual tiny（`be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`）。實際鏈路是 **SessionController → AVPlayer 播放時間 → AVAssetReader 16 kHz 單聲道 PCM → StreamingTranscriber → whisper.cpp → 確認字幕**，參考文字未提供給辨識引擎。每個測試用獨立暫存 ModelStore 與 UserDefaults、靜音播放，檢查非空原語言結果（Apple NLLanguageRecognizer；中文接受繁體／簡體識別）、來源時間戳及非重疊、EOF 完成、暫停跳轉與 generation、停止釋放模型。日語 CPU 用例也檢查音訊中斷 ended 不造成暫停、began 會暫停，且可手動恢復。

英語新用例實際輸出英文，普通話新用例實際輸出中文（偵測為 `zh-Hans`），沒有改用翻譯或雲端。它們證明 App 內播放與本機原文字幕的資料流，**不等同逐字正確**：英語結尾多了 `Thank you.`；中文多了無關 `謝謝`，也將 `篇章`／`開始` 誤辨為 `偏胶`／`开水`，並混用繁簡。原始輸出完整保留。其他語言仍有既有錯字與幻覺，不能由六項通過推定字幕準確率。

所有 `usingGPU` 都為 false；要求自動加速的日語用例是安全 CPU 備援，沒有驗證 iPad Metal。`inferenceSeconds` 與 `processedAudioSeconds` 是最後一次回報的窗口指標，不是整段累計推論或首字延遲；`wallSecondsIncludingPlayback` 含實時播放。沒有測實體 iPad 的記憶體峰值、熱穩定性、長時間運行、ReplayKit 跨 App、背景存活或 PiP，也不是觸控／旋轉／分割畫面的視覺驗收。

## 重現與公開證據處理

先準備已校驗 tiny，執行 `python3 Scripts/fetch-test-audio.py` 取得四種語言資料，再用 `bash Scripts/make-video-fixture.sh` 產生法語 MP4（僅新增中性畫面，沒有假字幕）。然後選擇自己的可用 iPad Simulator UDID：

```sh
bash Scripts/test-ipad-simulator.sh YOUR_IPAD_SIMULATOR_UDID \
  /path/to/ggml-tiny.bin /tmp/live-caption-verification-audio
```

該腳本目前要求 **6 項通過、0 項失敗、0 項跳過**，包含英文／普通話 fixture SHA256、host App 安裝與資料配置、序列 XCTest、摘要與附件匯出。它不修改已存在且內容不同的測試檔、不清空模擬器或覆寫 UserDefaults。本次成功結果由同等 `xcodebuild test` 產生；提取證據時沒有再次執行測試。

公開前先將未修改的摘要、測試明細、附件、JSON、日誌保存到已被 Git 忽略的 `BuildReports/PrivateEvidence/Verification/languages/ipad/`。公開副本僅把模擬裝置顯示名稱改為 `iPad Simulator`、本機使用者家目錄前綴改為 `<USER_HOME>`；**字幕、數字、SHA256、測試狀態未修改**。本輪只處理此新目錄，不覆蓋其他歷史證據。
