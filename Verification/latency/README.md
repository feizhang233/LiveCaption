# 本機串流延遲：相同測量方法的前後比較

2026-11-06，Apple M4 Pro（12 CPU 核心、24 GiB RAM），macOS 27.2（26B123）、Swift 6.4.2。使用 Tiny 多語言模型、whisper.cpp 1.9.5 / b5454、實際 Metal 推論，Debug CaptionCore。四段 Google FLEURS 真人錄音各跑一次；來源、逐字稿、CC-BY-4.0 與 SHA256 見 [fixture manifest](../../Tests/Fixtures/manifest.json)。這是 Mac 核心串流測量，**不是實體 iPad、完整 App 首幀顯示、長時間或冷開機測試**。

臨時結果提前約 **0.57–0.60 秒**，有文字變更的臨時更新中位間隔由約 **1.4–1.5 秒降至 0.8 秒**。四段最終字幕文字及時間戳完全相同，沒有丟棄音訊。但更多臨時推論增加了計算量；最早出現文字也不代表正確。

## 測量方法

- 舊 probe 在 200 ms 音訊塊的開始就提交整塊，會提前看到未播放音訊。本輪先修正：以單調時鐘等待每個塊的**末端**，才提交 PCM。baseline 和 optimized 使用同一份修正後 probe、相同 swiftc flags、相同模型與四段錄音，推論串行進行。受另一個 Session 測試干擾的初始試跑已作廢，正式 baseline 全數重跑。不能拿舊報告的延遲數字直接比較。
- 模型預先載入，時間零點是串流播放時鐘起點。首次字幕時間由 consumer 收到 `.partial` 或 `.confirmed` 事件記錄，並保留事件類型及完整文字；本輪首次事件全是臨時字幕。
- 額外以固定 **20 ms RMS ≥ 0.0002、連續 3 幀** 計算同一份原始音訊的能量起終點，兩版共用。這是獨立於產品 VAD 的能量 proxy，沒有人工音素標註，背景噪聲仍可能影響邊界。原始 probe JSON 的 `speechEnergy*` 診斷欄位採較高 0.006 門檻，對低音量 FR0 無法偵測；因此下表及 `comparison.json` 使用 `compare.swift` 從原始音訊重算的共用 0.0002 邊界，沒有重寫原始測量或補造語音。
- `inferenceTotalSeconds` 是所有實際引擎呼叫的累計耗時（含 actor 邊界），`inferenceCallCount` 是實際呼叫數。兩者包含臨時及確認推論；不是把最後一次 metrics 當成總數。最終延遲另列相對 EOF，負數代表尾端靜音尚未播放完就已確認。
- 兩版最大音訊提交遲到量都 ≤14 ms；不允許提早提交未播放的音訊。RSS 使用 macOS `getrusage().ru_maxrss`，包含模型與處理程序，非單一模型檔案大小。模型載入時間另留在各 JSON，不含於首字幕時間。

## 首次字幕與更新頻率

單位：秒，前 → 後。

| 錄音 | 能量起點 | 檔案開始→首次臨時文字 | 能量起點→首次臨時文字 | 有文字變更的更新間隔中位數 |
|---|---:|---:|---:|---:|
| JA0 | 0.02 | 1.686 → 1.088 | 1.666 → 1.068 | 1.427 → 0.812 |
| JA1 | 0.00 | 1.664 → 1.093 | 1.664 → 1.093 | 1.523 → 0.814 |
| FR0 | 2.18 | 3.675 → 3.075 | 1.495 → 0.895 | 1.410 → 0.795 |
| FR1 | 0.48 | 1.666 → 1.062 | 1.186 → 0.582 | 1.514 → 0.809 |

**不能將以上解讀為「1 秒產生正確字幕」。** JA0、JA1 兩版首條均為無關的 `ご視聴ありがとうございました`；FR1 改善後首條只有 `et`。這些是真實模型輸出，沒有硬編碼刪除。人工對照來源開頭與原始事件，首次出現相關開頭片段的時間如下；這仍不是整句正確性或逐字正確延遲指標：

| 錄音 | 首次相關片段（可能含誤字） | 檔案開始→該片段 |
|---|---|---:|
| JA0 | `インターネットで` | 3.073 → 2.672 |
| JA1 | `また来た後に` → `また来たご` | 4.679 → 4.274 |
| FR0 | `L'accident a eu lieu.` → `L'accident.` | 3.675 → 3.075 |
| FR1 | `Il ajoutait…`（來源為 `Il a ajouté…`） | 3.081 → 2.687 |

JA0／JA1／FR1 的這個人工檢視起點提前約 0.4 秒。完整 partial 與 confirmed 事件在各檔 `streaming.updates`，不得僅引用最短數字而省略內容品質。

## 最終字幕、成本及限制

| 錄音 | 最後確認相對 EOF（秒） | 實際推論次數 | 推論累計（秒） | 峰值 RSS（MiB） | 丟棄音訊（秒） | 最終錯誤率，前後一致 |
|---|---:|---:|---:|---:|---:|---:|
| JA0 | 0.066 → 0.066 | 8 → 14 | 0.733 → 1.251 | 256.1 → 267.1 | 0 → 0 | CER 30/45 = 66.7% |
| JA1 | 0.345 → 0.371 | 10 → 19 | 1.068 → 2.447 | 243.6 → 254.2 | 0 → 0 | CER 227/46 = 493.5% |
| FR0 | −0.874 → −0.873 | 5 → 9 | 0.427 → 0.705 | 235.5 → 239.2 | 0 → 0 | WER 4/20 = 20.0% |
| FR1 | 0.131 → 0.151 | 6 → 11 | 0.599 → 1.058 | 237.4 → 242.3 | 0 → 0 | WER 18/26 = 69.2% |

最終窗口、600 ms 靜音尾留及重疊保持相同。較快的臨時更新增加推論耗時約 65–129%，不能視為節能或更快最終定稿的證明。JA1 的最終 `ぜひ` 大量重複使 CER 超過 100%；改善後一些臨時結果也有同樣重複。這四段 Tiny 品質不足以支持可用準確率承諾，確認文字未退化不代表品質已達標。CER 忽略大小寫、標點與空白，只計字母/數字；法語 WER 依非字母/數字切詞並保留重音，詳見各 `accuracy.json`。沒有測其他模型、長片、熱節流、其他硬體或實體 iPad。

App 暫停後沿用已載入模型的另一項改善、`start()` 返回時間與真實 C 模型初始化次數，見 [Session 恢復測量](session/README.md)。那是另一個指標，不能與本頁首字幕延遲相加或互相替代。

最終整合另通過 33 項核心測試、[4 項 iPad Simulator 真實推論回歸](ipad/README.md)，以及 macOS／iPad device build；[建置與來源雜湊](builds.json) 與 [核心排程回歸](../engine/latency/README.md) 保留對應證據。App 架構及日後修改的測試入口見 [STRUCTURE.md](../../STRUCTURE.md)。

## 原始證據與重現

- `baseline/`、`optimized/`：四段 JSON、whisper stderr、accuracy 與輸入／編譯產物 SHA256。
- [comparison.json](comparison.json)：由 [compare.swift](compare.swift) 產生，包含首條類型／文字、逐段延遲、更新次數、累計推論、丟棄音訊、RSS 與最終 segment 相等檢查。
- 基線完整產品及 core 原始碼快照保存在 `/tmp/live-caption-latency-baseline/Products`、`/tmp/live-caption-latency-baseline/CoreSources`；改善版產品在 `/tmp/live-caption-latency-optimized/Products`。臨時目錄不隨原始碼交付，產物 hash 隨本證據保存。兩版動態 whisper framework hash 相同；兩個 core 為不同靜態庫。
- [baseline-to-optimized.patch](baseline-to-optimized.patch) 保存本輪兩版核心的完整差異，[core-source-hashes.json](core-source-hashes.json) 保存所有核心檔案兩版 SHA256；可在獨立副本反向套用 patch 後核對 hash 還原 baseline，再重編。不要在日常開發目錄直接反向覆蓋。probe 主檔前後 SHA256 相同。

先依 [專案 README](../../README.md) 準備引擎，建置當前 core 並取得 Debug Products（需 `libCaptionCore.a`、Swift module 與 `whisper.framework`）。若要重現「前後」而非僅當前版本，必須保有相應基線產品／原始碼；不可把新 core 當成基線。音訊可用 `python3 Scripts/fetch-test-audio.py /tmp/live-caption-verification-audio` 下載，影片不參與本輪測量。模型應是已校驗的 Tiny，檔案不放入倉庫。

```sh
bash Verification/latency/build-probe.sh /path/to/DebugProducts /tmp/CaptionProbe
# 測量時不要同時執行另一個推論、模擬器效能測試或其他重負載。
bash Verification/latency/run-benchmark.sh /tmp/CaptionProbe \
  /path/to/ggml-tiny.bin /tmp/live-caption-verification-audio /tmp/new-results
# baseline/optimized 皆備妥後，重算比較（不再執行辨識）。
xcrun swift Verification/latency/compare.swift Verification/latency \
  /tmp/live-caption-verification-audio > /tmp/comparison.json
```

`build-probe.sh`、`run-benchmark.sh` 通過 shell 語法檢查；後者實際執行改善版四段測量，`compare.swift` 已實際產生本比較。開發工具與 Python 僅用於取樣及驗證；App 執行不依賴它們。
