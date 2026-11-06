# Whisper 模型與下載驗證

模型檔案來自 whisper.cpp 維護者的 [Hugging Face 倉庫](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1)，固定 revision `5359861c739e955e79d9a303bcbc70fb988958b1`。2026-11-06 實際取得倉庫 API 的 LFS SHA-256 與位元組數，原始欄位保存於 `Docs/model-manifest.json`。README 中的 SHA 是另一種摘要，不能當成本 App 的 SHA-256。

| 多語言模型 | 檔案位元組 | SHA-256 |
| --- | ---: | --- |
| tiny | 77,691,713 | `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` |
| base | 147,951,465 | `60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe` |
| small | 487,601,967 | `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b` |
| medium | 1,533,763,059 | `6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208` |
| large-v3-turbo | 1,624,555,275 | `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69` |
| large-v3 | 3,095,033,483 | `64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2` |

所有選項都是多語言 ggml 權重，沒有 `.en` 模型。沒有權重隨 App 或原始碼打包，也不會首次啟動就自動下載。OpenAI Whisper 權重採 MIT 授權；保留的授權全文是 `ThirdParty/Models/Whisper-LICENSE.txt`。模型轉換倉庫的 pinned model card 亦標記 MIT。

下載路徑使用上述 immutable revision，允許 Hugging Face 正常重新導向 CDN；最後必須與內建 SHA-256 及大小完全相符。網路僅用於取得模型，沒有上傳音訊或遠端推論。下載後才可離線辨識。

App 儲存位置為沙盒 Application Support 下的 `LiveCaption/Models`，並排除備份。`URLSessionDownloadTask` 直接寫磁碟，驗證以 1 MiB 區塊在背景 task 執行，避免將完整模型載入 Data。驗證成功才將暫存檔移至正式檔名並標記可用。每次啟動也重新驗證既有檔案。取消及重試使用不同 operation ID，舊回呼不能覆蓋新的下載狀態；未完成檔案不會顯示為已安裝。

同時只進行一個下載或驗證流程。下載前以系統可用空間 API 確認檔案大小外另保留 256 MiB。可用空間是當下快照，其他 App 仍可能在之後佔用磁碟；寫入錯誤會保留為真實失敗狀態。

畫面的 RAM 數字是保守規劃估值，與精確下載大小分開。它們不是實測峰值，也不是系統允許分配的保證。GPU 緩衝、解碼設定、系統負載與 iPad 的 jetsam 限制都會影響結果。大型模型不會自動選用；裝置實體記憶體低於建議值時提示使用 tiny/base/small。

整個 App 的多視窗共用一個 `ModelStore`。協調層必須在載入引擎前呼叫 `setInUse(id)`；載入失敗或卸載完成後呼叫 `setInUse(nil)`。這會阻止下載覆寫、切換或刪除正在載入/使用的模型。下載完成仍需使用者按「使用」選擇模型。

開發驗證：`bash Scripts/test-models.sh` 檢查 SHA-256、大小、符號連結、啟動驗證、損壞拒絕、選擇與刪除鎖。`bash Scripts/test-models.sh --network` 另外下載真正的 tiny，測試取消後立即重試、完整性驗證與正式可用狀態；下載到 `/tmp/live-caption-verification-models`，不寫入專案。只有開發驗證腳本需要命令列；使用 App 不需要。
