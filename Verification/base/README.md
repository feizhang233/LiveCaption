# Base 多語言模型真人音訊驗證

2026-11-06 在 Apple M4 Pro／24 GiB RAM 開發機執行。使用現有原生 `CaptionProbe`、whisper.cpp 1.9.5／官方 b5454、Metal、手動日語／法語與 `translate=false`。這是本機核心直接檔案解碼測試，**不是 App UI、ScreenCaptureKit、iPad、串流字幕延遲或長時間穩定性驗收**。

模型由開發 QA 明確下載到 `/tmp/live-caption-verification-models/ggml-base.bin`，未加入 App、原始碼倉庫或產品自動下載流程；本次沒有下載 small、medium 或 large。來源固定 Hugging Face revision `5359861c739e955e79d9a303bcbc70fb988958b1`，實際大小 **147,951,465 bytes**，SHA-256 **`60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`**。檢查紀錄見 [model-verification.json](model-verification.json)。

四段測試音訊與先前 tiny 測試完全相同；本次在執行前重新驗證其 SHA-256。來源、參考逐字稿與 Google FLEURS／CC BY 4.0 聲明見 [fixture manifest](../engine/fixture-manifest.json) 及 [資料來源說明](../../Tests/Fixtures/README.md)。

| 片段 | 音訊秒數 | 指標 | 先前 tiny 錯誤率 | 本次 Base 錯誤率 | Base 推論秒數 | Base 峰值 RSS |
|---|---:|---|---:|---:|---:|---:|
| ja_jp-0 | 10.44 | CER | 35.56% | 28.89%（13/45） | 0.434 | 約 327.5 MiB |
| ja_jp-1 | 14.22 | CER | 26.09% | 15.22%（7/46） | 0.151 | 約 325.0 MiB |
| fr_fr-0 | 10.20 | WER | 20.00% | 35.00%（7/20） | 0.122 | 約 325.7 MiB |
| fr_fr-1 | 8.28 | WER | 69.23% | 42.31%（11/26） | 0.137 | 約 326.0 MiB |

Base 在這兩段日語與第二段法語的觀察錯誤率較低，第一段法語反而較高。**不能推論 Base 對所有音訊更準確**；結果仍有明顯聽錯。CER 與 WER 不能直接互相比大小；四個短朗讀樣本也不足以宣稱影視、動漫、背景音樂或課程的整體準確率。

`loadSeconds` 為 0.115–0.202 秒，這次可能受作業系統檔案／GPU 快取影響。表中的推論時間來自直接解碼完整短片，沒有模擬即時輸入，因此不是觀眾看到字幕的端到端延遲；也不應和先前 tiny 的不同冷／熱狀態測量比較速度。原始數值與逐字稿保留於每段 `.json`，字幕在同名 `.srt`，引擎 stderr 在 `.engine.log`；[comparison.json](comparison.json) 彙整數值。

計分使用既有 `Scripts/score-fixtures.swift`，保留相同正規化規則：文字小寫；日語保留字母／數字計 CER；法語以非字母／數字分詞計 WER，保留重音。完整結果在 [accuracy.json](accuracy.json)。

重現單段（已取得固定模型及音訊後）：

```sh
swift run --package-path Packages/CaptionCore CaptionProbe \
  --model /tmp/live-caption-verification-models/ggml-base.bin \
  --audio /tmp/live-caption-verification-audio/ja_jp-0.wav \
  --language ja --srt /tmp/base-ja.srt
swift Scripts/score-fixtures.swift Verification/engine/fixture-manifest.json Verification/base
```

此結果增加了 Base 的功能與品質證據，尚未驗證 Base 的即時串流、兩小時運行、模型切換 UI 或任何 iPad 實體裝置表現。
