# 暫停恢復與模型重用

2026-11-06，在 Apple M4 Pro／24 GiB、Xcode 27.2 執行實際 `SessionController`、AVPlayer／AVAssetReader 與 multilingual tiny CPU 推論。輸入為同一真人法語錄音的 H.264／AAC MP4，靜音播放。沒有假辨識結果。

## 修改

原先每次 `start()` 都呼叫 `WhisperEngine.load`，即使 pause 已保留 C context，仍先釋放再重載權重及配置工作區。現在 Session 記錄成功的 `LoadedConfiguration(modelURL, requestedGPU)`；配置相同且實際 `engine.loadedModelURL` 匹配才重用。模型或 GPU 要求改變會重載，stop 完成卸載後清除快取。

## 觀察

| 指標 | 修改前 | 最終修改後 |
|---|---:|---:|
| 三次 pause／seek／EOF 後繼續的 `start()` 中位耗時 | 56.6 ms | 9.1 ms |
| 同樣五次 start 實際 C model init 次數 | 5 | 2 |
| 初次開始與 stop 後重新開始 | 都載入 | 都載入 |

這是「媒體已就緒、模型已校驗後，呼叫 start 到返回 running」的耗時，**不是首字、模型下載或整個 App 冷啟動延遲**。每版一個程序、每程序三個恢復樣本；不代表任意裝置／模型的百分比保證。初次開始的數值有保留，但不宣稱冷啟動變快。

兩版完整回歸均通過：遲到輪詢、實際 pause 尾音、原生 pause 後單次恢復、seek、EOF、主字幕不重疊、clear／stop 拒絕過時事件、模型釋放，以及 stop 後重新載入。C init 次數從實際引擎 stderr 計算，可在 [before.log](before.log) 與 [after.log](after.log) 核對；耗時及字幕在 [before.json](before.json)、[after.json](after.json)，匯總為 [comparison.json](comparison.json)。

修改前使用固定 baseline core；修改後使用最終低延遲 core。比較聚焦模型生命週期；兩版 start 的返回點都在下一次播放辨識之前。正式兩版測量未與其他推論同時執行。中途與另一個暖機測量重疊的那次 run 已排除，不納入上述數值。

```sh
bash Scripts/test-session.sh /path/ggml-tiny.bin /path/fr-native-video.mp4 /path/CaptionCoreProducts fr
```

依賴及資料來源見 [主延遲基準](../README.md)。這不是實體 iPad、Mac 系統收音或大型模型的測量。
