# 英文與中文：真人音訊本機驗證

2026-11-06，在 Apple M4 Pro／macOS 27.2，使用固定 whisper.cpp 1.9.5 / b5454 及已校驗的多語言 Tiny、Base，完成 **16 次真實本機推論**：2 模型 × 2 種模式 × 4 段英文／普通話錄音。全部使用實際 Metal、手動 `en` 或 `zh`、原文轉寫；全部產生非空結果，時間戳在來源長度內，8 次串流測試均沒有錯誤或丟棄音訊。這證明核心可以執行英文／普通話轉寫，**不是實體 iPad、跨 App、所有中文方言或可承諾準確率的驗證**。

## 音訊來源與方法

來源是 [Google FLEURS 固定版本](https://huggingface.co/datasets/google/fleurs/tree/d7c758a6dceecd54a98cac43404d3d576e721f07)，`en_us`、`cmn_hans_cn` test split，CC-BY-4.0，署名 **Google FLEURS contributors**。實際讀取同 revision 的 dataset card、兩份 `test.tsv` 與 archive；每種語言取 archive 中最先遇到的兩段 4–12 秒、不同逐字稿的錄音，**在辨識前選定**。實際 WAV 是 16 kHz 單聲道，長度與來源 sample count 相符。完整逐字稿、來源檔名、URL、SHA256 見 [manifest](../../Tests/Fixtures/manifest.json)，授權與取得方法見 [Fixtures README](../../Tests/Fixtures/README.md)。保留既有日語／法語四段；本輪 Mac 核心檢查沒有重跑它們的辨識（另外的 iPad 全套整合測試有保留原四項回歸）。

| Fixture | 時長 | 來源內容概要 |
|---|---:|---|
| en_us-0 | 10.56 s | 溝通緩慢使西方風格落後 25–30 年 |
| en_us-1 | 8.76 s | 德語名詞與 Sie 的首字母大寫規則 |
| cmn_hans_cn-0 | 10.38 s | 一個篇章結束及新篇章開始 |
| cmn_hans_cn-1 | 8.28 s | 鈣、鉀、銀、金等金屬元素 |

Direct 將短片完整交予引擎（probe 對長檔仍限每窗 25 秒）；Stream 用產品 VAD／重疊窗口／序列排程／去重，按實際音訊塊的**末端**每 200 ms 提交，不讀取未播放音訊。使用目前 1.0 秒首個臨時窗口、0.8 秒更新節奏的核心，沒有為這些資料調整解碼或字幕內容。16 個程序串行執行；同機曾編譯單元測試，所以本頁是功能與輸出品質證據，不把單次耗時當成嚴格效能基準。輸入資料與引擎 source hash 另存本目錄。

## 實際輸出與品質限制

以下 primary 指標保留真實輸出，不按來源答案改字。英語 WER 為非字母／數字切詞、忽略大小寫但不把數字詞轉數字；中文 CER 只去掉標點／空白，**主分數保留繁簡字形差異**。每個結果資料夾的 `accuracy.json` 保留 reference、hypothesis、編輯數及分母。

| 英文 WER | Tiny direct | Tiny stream | Base direct | Base stream |
|---|---:|---:|---:|---:|
| EN0 | 1/19 = 5.3% | 3/19 = 15.8% | 1/19 = 5.3% | 3/19 = 15.8% |
| EN1 | 5/21 = 23.8% | 5/21 = 23.8% | 3/21 = 14.3% | 3/21 = 14.3% |

| 中文原始 CER | Tiny direct | Tiny stream | Base direct | Base stream |
|---|---:|---:|---:|---:|
| ZH0 | 4/23 = 17.4% | 9/23 = 39.1% | 9/23 = 39.1% | 13/23 = 56.5% |
| ZH1 | 4/21 = 19.0% | 5/21 = 23.8% | 9/21 = 42.9% | 12/21 = 57.1% |

Base 中文多輸出繁體，而 FLEURS reference 為簡體；原始 CER 因此同時計入字形與辨識差異。評分器另提供明確命名的 `simplifiedScriptDiagnostic`：以系統 Foundation／ICU `Traditional-Simplified` 對兩邊文字轉換後再算 CER，**不改 App 字幕、不取代 primary 分數**：

| 中文繁簡正規化診斷 CER | Tiny direct | Tiny stream | Base direct | Base stream |
|---|---:|---:|---:|---:|
| ZH0 | 4/23 = 17.4% | 6/23 = 26.1% | 2/23 = 8.7% | 6/23 = 26.1% |
| ZH1 | 4/21 = 19.0% | 5/21 = 23.8% | 3/21 = 14.3% | 6/21 = 28.6% |

需要保留的真實問題：

- EN0 direct 的單一編輯是來源 `year` 與輸出 `years`；兩模型 stream 在結尾加了來源沒有的 `Thank you.`。
- EN1 包含德語 `Sie`，Tiny 出現 `world's safe`、Base 出現 `world say` 等錯字；不能以非空英語字幕視為內容正確。
- ZH0 的 `篇章` 被 Tiny 寫成 `偏胶`、Base 寫成 `偏章`；ZH1 的 `钙、钾` 等元素也有同音錯字。
- 中文 stream 會出現無關開頭，例如 Tiny 的 `謝謝`、`《新年》`，以及 Base 的 `謝謝大家`、`請問一下`。沒有使用特定短句黑名單隱藏問題。
- 四段短篇朗讀不能代表電影、噪聲、長時間運行或設備熱節流表現；本輪不承諾固定字形、所有口音／方言或任何準確率。模型較大也不保證每個短窗口結果更好。

## 證據與重現

App 的語言選擇與引擎參數共用 `SourceLanguageCatalog`，會保存並恢復上次的 `en`／`zh`／其他語言或 auto；無效設定安全回退。實際 App 類別的 [語言設定回歸](language-settings.log) 通過；[39 項核心測試](../engine/en-zh/README.md) 包含 EN／ZH 參數、英文及簡繁 Unicode 去重與 TXT／SRT。最終 Mac／iPad device build 與六項 Simulator 結果及來源 SHA 見 [builds.json](builds.json)。

`tiny/direct`、`tiny/stream`、`base/direct`、`base/stream` 各有四段原始 JSON、whisper stderr 與 `accuracy.json`。`checks.log` 記錄 16 個結果的非空、來源時間軸、實際 Metal、stream error/drop 檢查，以及 fetch/scorer 回歸。`fetch-reuse.log` 記錄四個已校驗檔案的復用；`fetch-repair.log` 記錄故意破壞 `/tmp` 英語測試副本後，從固定官方來源修復一個檔案、復用另一個檔案。另用禁止網路的 curl stub 證明完全有效的選定資料不觸發重新下載，並驗證未知語言參數回傳錯誤。既有 JA／FR 分數逐欄相同，該評分器回歸沒有重新推論。

```sh
# 僅為開發測試取得真人資料，App/Xcode 建置不需要 Python。
python3 Scripts/fetch-test-audio.py --language en_us --language cmn_hans_cn
# 先依專案 README 建置 CaptionProbe，並準備已校驗的多語言 tiny/base。
bash Verification/languages/run-core-checks.sh /path/to/CaptionProbe \
  /path/to/models /tmp/live-caption-verification-audio /tmp/language-results
# 僅重算分數，不再執行辨識。
xcrun swift Scripts/score-fixtures.swift Tests/Fixtures/manifest.json \
  /tmp/language-results/tiny/stream --language en_us --language cmn_hans_cn
```

實際測試使用 `/tmp/live-caption-core-build/out/Products/Debug/CaptionProbe`。重現腳本忠實保留本輪循環及參數，已通過 shell 語法檢查；為避免無意重跑，它沒有再次執行整輪。大型模型、音訊及建置產物保留在 `/tmp`，未加入原始碼倉庫。

另有 [iPad hosted App 六項測試](ipad/README.md)：6 項通過、0 項失敗／跳過，包含新英文及普通話真人資料在完整 Session／播放時間軸／本機辨識鏈路的驗證。那是 **iPad 模擬器 CPU／CPU 備援**，並非實體 iPad 或 iPad Metal；其原始結果與本頁 Mac 核心直接／串流結果分別保存。
