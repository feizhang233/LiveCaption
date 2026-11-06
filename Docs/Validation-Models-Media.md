# 模型管理與媒體驗證紀錄

日期：2026-11-06。環境：本機 Apple Silicon Mac、Xcode 27.2、Swift 6.4.2。下列為實際執行結果；不代表 iPad 真機驗證或長時間效能驗收。

## 模型管理

`bash Scripts/test-models.sh --network` 通過：

- 以 1 MiB 區塊計算 SHA-256；正確檔案可用，錯誤大小、錯誤 SHA-256 與符號連結遭拒。
- 啟動時重新驗證既有檔案；損壞檔案不會標記為已安裝。
- 模型選擇持久化；載入中/使用中的模型不能刪除；刪除目前選擇會清除設定。
- 真正向 pinned Hugging Face URL 下載 tiny，在 150 ms 取消後立即重試；舊操作不會覆寫新操作。
- 真正下載的 77,691,713 位元組 tiny 通過 SHA-256 `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` 後才原子移動至正式檔案。

驗證模型保存在 `/tmp/live-caption-verification-models/ggml-tiny.bin`，沒有加入原始碼或 App bundle。本輪模型管理測試未下載/載入其他五種模型，但其 manifest 大小及 SHA-256 已比對官方倉庫 LFS metadata；後續 Base 直接推論的獨立驗證見 `Verification/base/README.md`。

四個 `App/Models/*.swift` 檔案以 Swift 6 分別通過 macOS 與 arm64 iPadOS 26 Simulator SDK 的 typecheck。這證明 API/編譯相容性，不是 iPad 下載或記憶體實測。

## 媒體

`bash Scripts/test-media.sh` 使用真正的日語 FLEURS 錄音 `ja_jp-0.wav`（10.44 秒），並將同一錄音轉為 48 kHz/16-bit/stereo，再分別通過：

- 解碼為單聲道 16 kHz 浮點音訊；3 秒得到 48,000 個 sample（允許 2 sample 邊界誤差）。
- 不會輸出播放位置之後的音訊；單次 `read` 不超過 8,000 sample（0.5 秒）。
- 固定播放時間不會重複/繼續輸出音訊。
- 向後跳轉到 1.5 秒與向前跳轉到 3.25 秒後，sample 時間戳對應媒體時間軸。
- 實際 AVPlayer 靜音播放，暫停後等待 450 ms，播放位置保持穩定（誤差小於 20 ms）；跳轉到 2 秒後恢復播放。
- 不存在的檔案回報真實 AVFoundation 錯誤，並清除 ready/loading 狀態。

這裡的測試針對媒體讀取與播放器時間軸，不聲稱字幕端到端延遲或字幕時間戳誤差已達特定標準。whisper.cpp 推論及字幕排程由其他驗證項目涵蓋。SDK 27 對部分仍支援目標 OS 26 的 AVAssetReader API 發出棄用警告，測試通過。

後續亦執行 `bash Scripts/test-media.sh /tmp/live-caption-verification-audio/fr-native-video.mp4` 並通過相同全部檢查，包括 MP4 的 AAC 音軌，以及從該影片抽取、轉換的 48 kHz stereo 音訊。此 10.20 秒影片以公開 AVFoundation API 為真正的法語 FLEURS 錄音加入中性純色 H.264 畫面；沒有合成語音、字幕文字或假辨識內容。影片來源與變更記錄見 `Tests/Fixtures/derived-video.json`。這個命令列播放器驗證不等同 SwiftUI 畫面互動或 iPad 真機驗證。

## iPad Simulator App 整合

最終 `/tmp/live-caption-ipad-verified.xcresult` 實際執行 **4 項通過、0 失敗、0 跳過**，測試方法合計 45.468 秒。環境是 iPad Air 11-inch (M3) 模擬裝置、iOS Simulator 27.0（24A434）、arm64；沒有使用實體 iPad。

日語 WAV、法語 WAV、法語 MP4 三項明確使用 CPU；第四項日語設定 `requestedUseGPU=true`，實際 `usingGPU=false`，證實本模擬器的預設加速要求可落到 CPU 備援。每項重新校驗 tiny、使用真實 AVPlayer/AVAssetReader/whisper.cpp 資料流，驗證原語言、媒體時間戳、EOF、暫停跳轉與模型釋放。沒有注入假字幕。App plist 的 `UIFileSharingEnabled` 及 `LSSupportsOpeningDocumentsInPlace` 已設為 true，允許以 Files 提供測試媒體；這不是實機或觸控操作驗收。

四份實際字幕 JSON、XCTest 摘要及原始附件見 `Verification/ipad/`。tiny 仍有誤辨和日語片尾幻覺；通過的是資料流／狀態驗證，並非準確率門檻。最後推論視窗的耗時不是整段或首字延遲。尚未驗證 iPad 真機 Metal、記憶體峰值、長時間／熱穩定性、跨 App／背景／PiP 及完整介面操作，詳見 `Verification/ipad/README.md`。

## 音訊來源

兩段日語與兩段法語真人錄音已取得，來源、授權、原文與 SHA-256 保存在 `Tests/Fixtures/manifest.json`；音訊只放在 `/tmp/live-caption-verification-audio`。詳見 `Tests/Fixtures/README.md`。重新取得資料的 Python 腳本只供開發測試，App 與 Xcode 建置不需要 Python。
