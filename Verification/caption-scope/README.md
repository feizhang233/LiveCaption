# 前台 App／網站範圍驗證 · 2026-11-06

本次新增 Mac 系統音訊的始終／指定範圍模式；沒有新增跨語言翻譯或 iPad 跨 App 支援。

| 檢查 | 結果與證據 |
|---|---|
| Mac unsigned build | 通過，`build-mac.log` |
| iPad Simulator unsigned build | 通過，`build-ipad.log`；Mac 專屬入口不影響共用編譯 |
| 範圍匹配／持久化 | 44 項通過，`scope-policy.log`：精確 app ID、網域邊界、子網域、無效輸入、重複清單、持久化及損壞資料 |
| 工作階段整合 | 34 項通過，`scope-session.log`：真實 Tiny 模型與受控靜音 PCM adapter；7 次開始、9 次停止，不擷取使用者系統音訊 |
| 原有本機媒體回歸 | 通過，`media-session.log`：真實日語 fixture、暫停尾音、模型重用、seek、EOF、匯出及 stop 後重新載入 |
| 原有語言設定 | 通過，`language-settings.log` |
| UI 靜態 contract | strict audit 通過，`premium-audit.json`，0 findings；不取代實際 UI 操作 |
| Mac 實際 UI | DerivedData App 啟動命令成功；CUA 取得 App 狀態等待 312.8 秒後中止，未返回快照。未點擊、修改設定、請求權限或開始收音；因此無可視驗收或截圖證據 |
| 原生前台 monitor | `monitor-native.log`：目前前台身份、非支援 App 不匹配網站、停止清理通過；Safari／Chrome 無提示權限預檢回傳 permissionRequired，未取得網址 |

工作階段整合另覆蓋：空清單不載入模型／不收音，手動暫停與停止不自動復活，前台 App 切換，同瀏覽器網址／分頁，未知網址維持暫停，同一主執行序輪次的離開再返回仍取消舊 generation，跨範圍緩衝音訊拒收，自動暫停中手動暫停／停止，以及 capture.start 等待期間撤銷範圍。

主要可重跑命令：

```sh
bash Scripts/test-caption-scope.sh
bash Scripts/test-caption-scope-session.sh /path/to/ggml-tiny.bin
bash Scripts/test-session.sh /path/to/ggml-tiny.bin /path/to/ja_jp-0.wav
bash Scripts/test-language-settings.sh
bash Scripts/build.sh mac
bash Scripts/build.sh ipad-simulator
```

範圍整合測試注入前台事件與收音 adapter，不能替代真實 browser → URL → ScreenCaptureKit → 字幕的完整測試。授權後的真實瀏覽器 URL 取得、網站切換＋系統收音連續使用、Safari／Chrome／Edge／Brave 各自的已簽署 sandbox 權限及長時間運作仍待驗證。沒有安裝／發行／公證成果宣稱。模型及音訊 fixture 仍使用既有固定版本，不隨此次功能複製到原始碼庫。

設定畫面的實際 Picker 開合、鍵盤輸入、錯誤提示、增刪後恢復及窄視窗布局仍需可用的 UI 控制連線驗證；本次僅有編譯、型別檢查及靜態 contract 證據。
