# 原始碼倉庫發布範圍

這份文件說明 GitHub 原始碼交付包含什麼、如何從乾淨目錄建置，以及公開驗證紀錄的元資料處理。使用方式見 [README](../README.md)，維護入口見 [STRUCTURE](../STRUCTURE.md)。原始碼上傳不等同 App Store／TestFlight 發布、真機安裝或 Mac notarization。

## 0.2.0 本輪發布核對

本輪納入 Mac 浮動字幕與選單列背景控制、可選的語氣詞顯示過濾，以及 iPhone／iPad 本機媒體字幕 PiP。Mac 與 iOS device 建置已通過；實體行動裝置的 PiP 與長時間背景推論仍待驗證。GitHub 發布與本機 App 更新須以本輪最終提交、建置及安裝核對為準，以下舊版 tree 與快照結果僅保留為歷史證據。

本輪針對 Git tracked 與未忽略的 untracked 候選檔案掃描路徑、私鑰／常見憑據格式及簽署 Team，未發現本機使用者家目錄路徑、真實憑據或個人 Team。URL 內嵌帳密格式僅命中 `Tests/CaptionScopeChecks.swift` 的故意無效測試網址。候選二進位均為圖示及 UI 驗證 PNG；沒有模型、媒體、framework、建置產物、私人備份或 symlink。這是候選清單與格式掃描結果，最終 staged diff 仍須核對。

新增的 8 份 `Verification/` log／audit 已先原樣備份到忽略的 `BuildReports/PrivateEvidence/`，公開版本只替換本機工程路徑，4 份 JSON 均通過解析；沒有改寫測量、字幕、時間或既有 hash。可再生成的根目錄 `premium-audit.json` 已移出發布清單並加入 root-only 忽略規則，具名的 `Verification/**/premium-audit.json` 仍保留。新增驗證完成後須再檢查有無重新帶入本機元資料。

## 納入與排除

納入原生 App、CaptionCore Swift source／tests、兩份已生成 Xcode 工程與 XcodeGen 定義、Config、建置／測試腳本、第三方授權、測試資料 manifest，以及小型文字驗證證據。`Verification/` 中的 JSON、SRT、log、XCTest 文字附件是測試結果，並非 App 會顯示的預設字幕。

[.gitignore](../.gitignore) 排除引擎 framework、模型權重、音訊／影片、DerivedData／SwiftPM 產物、xcuserdata、完整 xcresult／archive／App 分發包，以及本機工具帳戶狀態、憑據與簽署材料。`BuildReports/PrivateEvidence/` 是本機保留的未泛化證據，亦排除於原始碼。小型公開摘要可保留，原始 binary、模型與完整測試 bundle 不應以 Git LFS 或其他方式默默加入本次源碼發布。

專案的 entitlement／Info.plist 定義是可追蹤設定；個人 Team、私鑰、憑證及 provisioning profile 不是。現有 bundle ID 與 probe App Group 是 `com.example` 開發占位值，接手者需自行簽署設定。

## 乾淨目錄的建置入口

本次目標為使用者選定的公開倉庫 [feizhang233/LiveCaption](https://github.com/feizhang233/LiveCaption)。發布前從實際 staged Git tree `7a715ada72d3ccc1c3792b81444e575a483fffaa` 匯出到新的 `/tmp` 目錄，僅另外放入先前已校驗的官方 XCFramework，再執行 `bash Scripts/build.sh all`；Mac 與 iPad Simulator 均 exit 0。新語言來源檔已包含於該 tree。這次沒有把 framework 加入 Git，也沒有聲稱再次從網路下載；網路 bootstrap 的 SHA 驗證由下述早期乾淨快照獨立證明。建置後只補入文件與驗證摘要，程式來源不變。

取得來源後，先用 [fetch-whisper.sh](../Scripts/fetch-whisper.sh) 下載官方固定版本 XCFramework，校驗 [依賴 manifest](../ThirdParty/whisper-dependency.json) 中的 SHA-256，再開啟已生成的 [LiveCaption.xcodeproj](../LiveCaption.xcodeproj)：

```sh
bash Scripts/fetch-whisper.sh
open LiveCaption.xcodeproj
bash Scripts/build.sh all
bash Scripts/build.sh ipad-device
```

`all` 驗證 Mac 與 iPad Simulator，device 需另跑。一般 clone 不需要 XcodeGen，也不需要 Python、模型權重或測試錄音才能建置 App。App 使用者在產品中選擇、下載並校驗模型；開發測試資料另按 [Fixtures](../Tests/Fixtures/README.md) 取得。首次下載需要網路，已驗證模型的推論在本機執行。

2026-11-06 曾把排除 framework／模型／建置目錄的 **222 檔來源快照**複製到新的暫存目錄，實際執行 bootstrap 成功，官方引擎 SHA-256 符合 manifest，隨後 Mac 與 iPad Simulator unsigned build 均 exit 0。該次快照在本輪新語言介面接入前取得，**只證明 bootstrap 與當時乾淨快照的建置入口**；最終提交包含哪些檔案及其建置結果，須以最終 staged／archive 的驗證為準。不得拿舊快照結果替代更新後版本的驗收。

## 公開證據只泛化本機元資料

發布前將命中的既有證據原樣複製到 `BuildReports/PrivateEvidence/<原相對路徑>`，再在公開版本僅替換：

- 本機工程的絕對路徑 → `<PROJECT_ROOT>`。
- 本機使用者家目錄 → `<USER_HOME>`。
- 與本專案無關的模擬器自訂名稱 → `iPad Simulator`。

`iPad Simulator` 在這些歷史檔案中是泛化後的顯示名稱，不表示測試使用實體裝置或更換了模擬器。裝置型號、UDID、OS、執行時間、失敗／跳過數、推論文字、字幕 JSON 及已有 SHA 數值保持不變。

發布檢查先處理 20 份既有證據，涉及核心測試 log、UI 稽核的工程路徑，以及 iPad 的 test-summary／test-results／attachment manifest 和一份說明文件；本輪新增的語言證據也在產生完成後按相同規則備份及處理。每份原檔均先保存；差異檢查只允許上述字串替換，JSON 仍可解析。

這表示**公開的部分 log／摘要／manifest 已不是原始 xcresult 匯出檔逐位元不變的副本**，不能宣稱其檔案 hash 仍與未泛化版本相同。未改動的字幕 JSON 及測量內容仍維持原有對照結果；原始來源證據保留在本機私人備份。若日後重算泛化檔案的 hash，應另標註「公開元資料泛化版」，不要覆蓋歷史原始檔 hash 而改寫驗證歷史。

本輪新增語言證據若仍由其他工作寫入，應等產生完成後再掃描與處理，不在寫入途中改檔。每次後續提交也要檢查新 log 是否重新帶入使用者路徑或其他專案的裝置名稱。

## 提交前的實際核對

第一輪來源盤點為 222 個可讀文字檔、836,956 bytes，最大單檔 34,105 bytes；沒有 symlink 或未識別二進位。後續英文／中文驗證會增加小型來源與文字結果，最終檔案數與大小應以提交清單為準，不沿用第一輪數字當成發布版規模。

當時針對候選文字內容檢查 GitHub／AWS／Google key 形狀、private-key block、URL 內嵌帳密及個人簽署 Team 模式，未命中；沒有讀取被排除的憑據檔或在報告中輸出 token。檔名與內容規則掃描是本次檢查範圍，不能替代提交者對最終 staged diff 的確認。

最終核對應直接使用 Git 的擬提交檔案清單與 staged diff：確認新增來源及必要 Xcode references 有納入、`.gitignore` 真正排除了私人備份與 binary，再以 tracked-only archive 驗證 bootstrap／建置。若用既有已校驗 framework 協助建置 archive，需說明其來源，且不把 framework 加入提交。

授權全文保留在 [ThirdParty](../ThirdParty) 與 App 內的 notices；測試真人錄音依 [資料來源與 CC BY 4.0](../Tests/Fixtures/README.md) 保留歸屬。本次沒有替專案新增或推定自身的 LICENSE，第三方授權保留與專案自身授權是分開記錄的事項。
