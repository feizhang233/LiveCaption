# 本機辨識核心驗證

執行日期：2026-11-06。開發機：Apple M4 Pro、24 GiB RAM、Xcode 27.2。以下是**開發機上的原生 Swift／whisper.cpp 核心測試**，不是 iPad 真機、ScreenCaptureKit、PiP 或完整影片 App 的驗收。

## 固定依賴與測試輸入

- whisper.cpp 1.9.5，commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`；官方對應二進位 `b5454`，下載 SHA-256 見 `ThirdParty/whisper-dependency.json`。
- 多語言 `ggml-tiny.bin`，77,691,713 bytes；SHA-256 `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21`。本次只有 tiny 做實際推論，不能外推到其他模型。
- 四個真人錄音來自 Google FLEURS，固定 revision `d7c758a6dceecd54a98cac43404d3d576e721f07`，CC BY 4.0。來源、原始檔名、參考逐字稿與音訊 SHA-256 在 `fixture-manifest.json`。原始音訊留在測試用 `/tmp`，未放入 App 或原始碼倉庫。
- 短片是乾淨的朗讀語音，不代表電影、動漫、音樂、多人重疊或直播。

## 已測結果

四段直接解碼使用手動日語／法語、`translate=false` 與 Metal。可檢查同名 JSON、SRT 和 `accuracy.json`。字／詞錯誤率是這幾個樣本的觀察值，並非準確率承諾。

| 音訊 | 秒數 | 指標 | 編輯數／參考單位 | 觀察錯誤率 |
| --- | ---: | --- | ---: | ---: |
| ja_jp-0 | 10.44 | CER | 16 / 45 | 35.56% |
| ja_jp-1 | 14.22 | CER | 12 / 46 | 26.09% |
| fr_fr-0 | 10.20 | WER | 4 / 20 | 20.00% |
| fr_fr-1 | 8.28 | WER | 18 / 26 | 69.23% |

計分將文字轉小寫，日語只保留字母與數字；法語以非字母／非數字分詞，保留重音。計算程式為 `Scripts/score-fixtures.swift`。tiny 有明顯聽錯字詞，不應將「成功產生原文字幕」等同高品質字幕。

串流結果：

- `ja-long-stream.json`：把一段 10.44 秒真人日語錄音重播 18 次，總音訊 187.92 秒；以絕對播放時鐘送入 200 ms PCM 區塊。牆鐘 187.98 秒、121 次臨時字幕、32 段確認字幕、淘汰音訊 0 秒。第一筆臨時字幕在 1.47 秒；確認字幕的觀察最大延遲為 3.01 秒，單次推論最大 0.278 秒。峰值常駐記憶體 246,448,128 bytes（約 235 MiB），每次重播採樣均未再增加。這只是三分鐘重複片段檢查，尚不是數小時穩定性驗證。
- `fr-stream.json`：非常小聲的 10.20 秒真人法語錄音經串流管線成功產生法語字幕。第一筆臨時字幕在檔案開始後 3.46 秒（語音本身約在 2 秒才開始），淘汰音訊 0 秒。此樣本曾揭露固定音量門檻過高，修正自適應 VAD 門檻後重測通過。
- `silence-stream.json`：7 秒數位靜音，0 次推論、0 臨時字幕、0 確認字幕。
- `cancellation.json`：實際 C 推論中取消，觀察到 CancellationError；釋放模型，再載入並成功解碼。未使用假辨識結果。
- `metal-backend-regression.json`：加入模擬器 CPU 政策後，實體 Mac 仍記錄 `gpuRequested=true`、`gpuLoaded=true` 並產生實際日語字幕，確認沒有意外停用實體 Mac Metal。
- `core-tests.log`：24 個單元／整合邊界測試通過，涵蓋來源時間軸 SRT、日法重疊消除、相隔較久的重複句保留、靜音／低音量、緩衝上限、seek 後在途與已緩衝事件失效、慢推論淘汰、右聲道混音與 44.1→16 kHz 重採樣、缺失模型和語言表，以及 8 個跨 seek 歷史對齊案例。新增安靜音訊只產生「…」「...」「♪」時不輸出臨時或確認字幕的測試，仍保留 Unicode 日法中文字與數字。

## 重播／跳轉後的歷史規則

`CaptionTimeline` 保留第一筆已確認字幕。新的字幕若完全被覆蓋、且文字重複便略過；若只有一端重疊，只有在相鄰文字邊界出現至少 3 個正規化字元的精確匹配時，才刪除新結果的重複前／後綴並調整時間邊界。這是保守文字啟發式，不是詞級時間戳。

無法明確分割的新結果會完整保存在 `alternatives`，由介面顯示為其他辨識記錄。舊字幕不會因為使用者跳到句子中間而被刪掉；也不會依時間比例切掉不確定的文字。主要 TXT／SRT 使用 `timeline.cues`，時間區間不重疊。另一輪辨識的修正若不同於第一次，仍可從其他記錄閱讀，不會被默默覆寫或丟失。

預設最多 10,000 段主要字幕、1,000 段其他記錄。超出上限的新內容透過 `CaptionTimelineUpdate.unretained` 交還呼叫端，呼叫端必須提示並停止或另存；集合本身不會刪除較早文字。`uncoveredRanges(in:)` 可協助未來略過已處理音訊，但文字區間並不代表精確詞邊界，本版不靠任意切音訊來假定對齊正確。

## 修正與實際限制

1. 某些受限執行環境能列舉 Metal 但無法配置 GPU buffer，upstream ggml 在載入時會 assert。現在先檢查 Metal 工作集預算及 buffer 可配置性，無法配置即使用 CPU；正常 macOS GPU 權限下的 Metal 載入及推論已測。iOS Simulator 曾通過小型配置探測後仍在模型配置時崩潰，因此明確使用 CPU 備援；不宣稱模擬器 Metal 已可用，也不把模擬器結果當作 iPad 真機效能。小型探測不能保證真機日後大型配置永不失敗。
2. iPad 模型載入前另查 `os_proc_available_memory()`，以檔案大小 × 1.8 + 256 MiB 做保守檢查；這是估算與瞬間快照，不能保證不被 jetsam 終止。尚無大型模型／iPad 真機記憶體測試。
3. 官方二進位實際含 Core ML loader，但 App 沒有附帶／下載轉換後的 encoder `.mlmodelc`。實測載入器找不到 encoder 後使用 ggml；本版只宣稱 Metal／Accelerate／CPU，不宣稱 Core ML 加速已驗證。
4. VAD 是自適應能量、250 ms 前滾及 600 ms 靜音延遲，沒有額外神經語音分類器。音樂與噪音仍可能觸發辨識；背景音樂、多人重疊及 DRM 需要平台真實情境測試。
5. 在途推論被 epoch 失效；UI 使用 `taggedEvents` 並比較 `currentGeneration`，才能同時拒絕已經進入 AsyncStream 緩衝的舊事件。
6. 重採樣曾發現右聲道消失與尾部資料遺失，已透過明確 downmix 與依 input callback 要求的 frame 數切片修正。串流長測使用原生 16 kHz 單聲道檔案，44.1 kHz 立體聲路徑另有波形測試。

## 重現

先執行 `Scripts/fetch-whisper.sh` 安裝並校驗開發用 XCFramework。App 使用者不需執行任何腳本。

```sh
swift test --package-path Packages/CaptionCore
swift run --package-path Packages/CaptionCore CaptionProbe \
  --model /path/to/ggml-tiny.bin --audio /path/to/ja_jp-0.wav --language ja
swift run --package-path Packages/CaptionCore CaptionProbe \
  --model /path/to/ggml-tiny.bin --audio /path/to/ja_jp-0.wav --language ja --stream --repeat 18
swift run --package-path Packages/CaptionCore CaptionProbe \
  --model /path/to/ggml-tiny.bin --audio /path/to/ja_jp-1.wav --language ja --cpu --cancel-check
swift Scripts/score-fixtures.swift Verification/engine/fixture-manifest.json Verification/engine
```

來源：[whisper.cpp 1.9.5](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.5)、[官方 b5454](https://github.com/ggml-org/whisper.cpp/releases/tag/b5454)、[Google FLEURS](https://huggingface.co/datasets/google/fleurs)。必要引擎授權保留於 `ThirdParty/whisper.cpp-LICENSE` 及 `ThirdParty/ggml-LICENSE`。
