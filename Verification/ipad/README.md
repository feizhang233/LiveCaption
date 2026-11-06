# iPad 模擬器本機辨識驗證

2026-11-06，Xcode 27.2 的 hosted XCTest 實際執行 **4 項、通過 4 項、失敗 0 項、跳過 0 項**，測試方法合計 45.468 秒。原始結果為 `/tmp/live-caption-ipad-verified.xcresult`；匯出的機器可讀摘要在 `test-summary.json`，測試明細在 `test-results.json`，執行日誌節錄在 `run-excerpt.txt`，XCTest 原始文字附件及對應關係保存在 `attachments/`。先前 3 項 CPU 測試的證據保留在 `previous-cpu-run/`，不與本次混合。

測試環境是 **iOS Simulator 27.0（24A434）、arm64、iPad Air 11-inch (M3) 模擬裝置**。本次裝置名稱是 `iPad Simulator`，UDID 為 `1843660C-BAF1-4664-A668-5827B711BF15`；這個名稱不表示測試使用其他 App。**沒有實體 iPad 參與本次測試**，數據反映 Mac 主機上的模擬器，不可當作 M3 iPad 真機速度或記憶體數據。

| 真人音訊來源 | 容器／長度 | 加速要求 → 實際路徑 | 確認字幕段數 | 輸出語言 | 結果檔案 |
| --- | --- | --- | ---: | --- | --- |
| FLEURS 日語 | WAV／10.44 秒 | CPU → CPU | 2 | ja | `ja_jp-0.json` |
| FLEURS 法語 | WAV／10.20 秒 | CPU → CPU | 1 | fr | `fr_fr-0.json` |
| 同一法語錄音＋純色畫面 | MP4／10.20 秒 | CPU → CPU | 2 | fr | `fr-native-video.json` |
| FLEURS 日語 | WAV／10.44 秒 | 預設自動加速 → CPU 備援 | 2 | ja | `ja_jp-0-automatic-acceleration.json` |

四個 JSON 是從實際測試 stdout 的 `IPAD_REAL_INFERENCE` 紀錄抽出，已逐一比對與 XCTest 附件內容一致。測試使用 multilingual tiny、固定 SHA-256 `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` 及靜音播放。三項明確設 `requestedUseGPU=false`；第四項設 `requestedUseGPU=true`，引擎回報 `usingGPU=false`，實際採 CPU 備援。這驗證預設加速要求在本模擬器可安全備援，**沒有驗證 iPad Metal 推論**。每項會從 host App 的模型複製到獨立暫存 ModelStore，重新校驗完整性，使用獨立 UserDefaults；沒有注入預設字幕或假辨識結果。

驗證鏈為 `SessionController → AVPlayer 播放時間 → AVAssetReader 單聲道 16 kHz PCM → StreamingTranscriber → whisper.cpp → 確認字幕`。每項測試檢查原語言（Apple NLLanguageRecognizer）、字幕時間戳位於媒體時間軸、主字幕不重疊、播放結尾完成、暫停跳轉後 generation 更新與播放時鐘保持穩定，以及停止後模型 context 被釋放。此前一次測試暴露 EOF time-jump 導致最後字幕被重設的問題；修正後的本次結果全部通過。

## 已觀察到的限制

這些測試驗證資料流與基本狀態，**不代表辨識內容準確**。本次 tiny 輸出仍包含日語詞語誤辨，兩個日語測試最後一段都出現原錄音沒有的「ご視聴ありがとうございました」；法語也有詞語誤辨。先前法語 MP4 的單獨 `...` 段在新增純標點排除後未再出現，但這並不能消除模型幻覺。完整實際文字保留在 JSON，沒有刪除不佳結果。來源參考文字與授權見 `Tests/Fixtures/manifest.json` 及 `Tests/Fixtures/README.md`。

JSON 中 `inferenceSeconds`、`processedAudioSeconds` 是當時最後一次回報的推論視窗指標，不是完整錄音的累計值；不能據此宣稱整段辨識耗時或端到端字幕延遲。`wallSecondsIncludingPlayback` 包含約 10 秒的實時播放，也不是首字延遲量測。

本次沒有驗證實體 iPad 的 Metal、記憶體峰值、熱穩定性、長時間運行、ReplayKit 跨 App 收音、背景存活或 PiP。Hosted XCTest 也不等同 SwiftUI 觸控、旋轉、分割畫面及多視窗的視覺驗收。

## 重現

1. 準備通過上述 SHA-256 的 `ggml-tiny.bin`；App 內下載或開發測試下載均可。模型不會隨原始碼提供。
2. 執行 `python3 Scripts/fetch-test-audio.py` 取得固定來源的真人日語／法語錄音（僅開發測試資料取得用）。
3. 執行 `bash Scripts/make-video-fixture.sh`，用公開 AVFoundation API 建立法語 MP4；若檔案已存在，保留既有驗證檔即可。
4. 用 `xcrun simctl list devices available` 選擇已安裝 iPadOS/iOS 26＋ runtime 的 iPad 模擬裝置，然後執行：

```sh
bash Scripts/test-ipad-simulator.sh \
  1843660C-BAF1-4664-A668-5827B711BF15 \
  /tmp/live-caption-verification-models/ggml-tiny.bin \
  /tmp/live-caption-verification-audio
```

上述 UDID 只適用本次環境，其他 Mac 請換成自己的裝置。腳本會建置並安裝 test host、將模型與音訊放入該模擬器 App 的資料容器、序列執行四項測試並匯出 `.xcresult` 摘要／附件。它不改模型選擇或 UserDefaults、不清空模擬器、不自動下載模型，且拒絕覆寫內容不同的既有測試檔。腳本要求結果必須是 4 項通過、0 項跳過。此包裝腳本已通過 shell 語法與結果欄位檢查；本紀錄的成功執行使用下列等價原始指令：

```sh
xcodebuild -project LiveCaption.xcodeproj -scheme LiveCaptioniPad \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=1843660C-BAF1-4664-A668-5827B711BF15' \
  -derivedDataPath DerivedData-iPad \
  -resultBundlePath /tmp/live-caption-ipad-verified.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

所有測試工具均供開發驗證；使用 App 不需要 Python、命令列服務或本機連接埠。
