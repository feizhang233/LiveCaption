# App 工作階段整合驗證

2026-11-06 執行 `Scripts/test-session.sh` 通過，日語音訊結果在 `session-integration.json`，法語 H.264／AAC 影片結果在 `session-fr-video.json`。法語影片由同一份有授權的真人 FLEURS 音訊製成，畫面為無字幕純色，不含可供讀取的字幕軌。

測試直接編譯 App 的模型、媒體、SessionController、SwiftUI 與 macOS 平台原始碼，只排除 App 的 `@main` 入口。使用實際 `SessionController`、AVPlayer、AVAssetReader、模型 SHA-256 掃描和 whisper.cpp CPU 推論；沒有模擬辨識器，沒有顯示視窗或要求錄製權限，播放器設為靜音。

測試的 ModelStore 指向自動清理的暫存目錄與獨立 UserDefaults suite。tiny 模型由已校驗檔案複製後再次通過 App 的完整性掃描；未更動使用者模型或選擇設定。

通過項目：

1. 選擇已驗證 tiny，匯入真人日語 FLEURS `ja_jp-0.wav`，產生實際原文字幕。
2. 約 2.53 秒暫停，播放時鐘保持固定，確認字幕時間不超過已播放音訊。
3. 跳回 1 秒再播放，原有「インターネット」字幕保留，後續主要字幕區間不重疊，成功匯出 SRT。
4. 直接操作 AVPlayer seek，驗證與原生播放控制相同的時間跳轉通知會使舊辨識 generation 失效。
5. 自然播放到實際結尾：日語 10.44 秒、法語影片 10.20 秒。正常暫停且無解碼錯誤；尾部字幕確實超過先前暫停位置，推論指標沒有因 EOF 通知而清零。
6. 結束後按開始，會回到起點自動重播；靜音開頭不會生成只含省略號或標點的字幕。
7. 另從開頭約 0.8 秒直接以 AVPlayer 跳至 EOF，確認略過的音訊不被解碼成字幕。法語案例略過約 9.37 秒，確認字幕 0 筆、推論時間 0；這個案例曾揭露 timeJumped 通知與播放時鐘到達的競態，修正後通過。
8. 清除歷史並停止後等待，舊字幕不會再次出現；模型 C context 已釋放，ModelStore 使用鎖已解除。
9. 匯入不存在的檔案後，呈現錯誤且媒體不再標記為可播放。

法語影片的第一次暫停設為 4.5 秒，因原始錄音約在 2 秒才開始發聲。結果包含實際法語文字，但 tiny 仍有明顯誤辨；本測試證明媒體／生命週期／字幕鏈路運作，不代表字幕正確率已達產品驗收門檻。

這是 macOS 開發機的 App 邏輯整合測試；不替代可視 UI、全螢幕、多顯示器、系統音訊錄製、iPad 真機或 PiP 測試。tiny 的辨識仍有錯字，見 `engine/accuracy.json`。

重現：

```sh
Scripts/test-session.sh \
  /path/to/ggml-tiny.bin \
  /path/to/ja_jp-0.wav \
  /path/to/CaptionCore/out/Products/Debug

Scripts/test-session.sh \
  /path/to/ggml-tiny.bin \
  /path/to/fr-native-video.mp4 \
  /path/to/CaptionCore/out/Products/Debug fr
```

第三個參數可省略，腳本會自行建立 CaptionCore 開發產物；第四個來源語言參數預設 `ja`。以上均為開發驗證工具，App 使用者不需執行。
