# Live Caption

公開原始碼倉庫：[feizhang233/LiveCaption](https://github.com/feizhang233/LiveCaption)。

原生 Swift／SwiftUI 即時原文字幕 App，支援 **macOS 26＋、iOS 26＋與 iPadOS 26＋**。內建官方 whisper.cpp；音訊在本機辨識，模型由使用者在 App 內下載及選擇。使用者不需要 Python、命令列引擎、API key、背景伺服器或連接埠。

0.2.0 將 Mac 主視窗整理為字幕控制中心：大型浮動字幕開關、選單列控制與收起主視窗，方便讓字幕留在其他 App 上方。iPhone／iPad 新增本機媒體的系統子母畫面（PiP）字幕；它只處理本 App 播放的檔案，不能擷取 Safari 或其他 App 的聲音。**本輪 47 項核心／15 項模擬器測試已通過；iPhone／iPad 真機背景執行仍待驗收**，歷史測試不代表新功能已通過；全螢幕、多螢幕及長時間情境也仍有限制。完整狀態見 [驗收矩陣](Docs/Acceptance.md)。

後續開發與維護請先讀 [專案結構與維護指南](STRUCTURE.md)：包含目錄責任、資料流、取消與時間軸不變條件，以及各層修改後的測試入口。

GitHub 原始碼的納入／排除範圍、乾淨目錄建置與驗證紀錄元資料處理，見 [倉庫發布說明](Docs/Repository.md)。

## 使用流程

1. 開啟「模型管理」，查看檔案大小、記憶體估計及可用空間；下載模型，等待大小與 SHA-256 驗證完成後按「使用模型」。不會自動下載大型模型。
2. 在「即時字幕」或「媒體播放」選擇來源與原語言。首次預設日語，之後記住上次選擇；提供法語、英文、中文（普通話）、可選自動偵測及固定引擎支援的其他語言。中文輸出繁簡字形由模型決定，沒有額外字形轉換，也不保證所有中文方言。辨識設定為原文轉寫，沒有翻譯功能。
3. 匯入本機音訊／影片，按「開始字幕」。Mac 也提供其他 App 的系統音訊來源；按大型「顯示浮動字幕」，可將字幕拖至影片下方，再收起主視窗。頂部選單列的字幕圖示提供開關、開始／暫停、停止及重新開啟主視窗。iPhone／iPad 在匯入媒體及選好模型後，可按「開啟浮動字幕」使用系統子母畫面。
4. 使用暫停、繼續、停止；停止會取消推論並釋放模型。確認字幕保留在當次工作階段，可匯出 TXT／SRT；關閉 App 前請先匯出。

「設定」提供系統／淺色／深色、字幕字體、大小、顏色、行數、透明／Liquid Glass／純色背景及適用的不透明度。導航與控制面板使用原生 Liquid Glass；字幕閱讀區優先維持對比，尊重減少透明度及提高對比。Mac 浮窗預設為無邊框、透明底的置中字幕，以深色陰影維持可讀性；滑鼠移入才顯示拖移、縮放及選項控制，剛開啟時也會短暫提示。可切換「顯示背景」、置頂、點擊穿透與指定螢幕；主視窗的即時字幕／媒體播放頁和 App 選單提供恢復穿透控制。Mac 多視窗共用同一個辨識工作階段；iPhone／iPad 使用單一視窗與播放工作階段，避免重複建立子母畫面預覽。

「不顯示語氣詞」預設關閉；開啟後，明確選擇日語、英文、法語或中文時會保守隱藏獨立的猶豫詞，例如「えっと」「um」「euh」「嗯」。自動偵測及其他語言保持原樣；有實際語意的詞與詞內片段不會一律刪除。這只改變字幕與歷史列表的顯示，原始辨識紀錄和 TXT／SRT 匯出不變；只有語氣詞的句子不顯示。

Mac 收起或關閉主視窗後，已開始的辨識與浮窗繼續運作；從選單列控制停止，或退出 App。iPhone／iPad 的浮動模式使用 CPU 辨識並播放真正的本機媒體，速度與耗電取決於裝置及模型；建議先使用 Tiny／Base。子母畫面的大小與位置由系統控制，並非 Mac 的透明自由浮窗。一般切到背景會停止辨識；只有啟動中的本機媒體子母畫面路徑允許繼續，關閉背景子母畫面會停止辨識。此路徑的真機持續背景運行尚未驗證。

設定依功能分為「通用」「字幕樣式」「啟用範圍」（僅 Mac）「辨識與效能」「隱私與資料」「關於」。上方分類列只顯示所選分類的項目，窄視窗改用下拉選單；切換分類會保留尚未提交的網站輸入及進行中的權限請求。

Mac／iPhone／iPad 已附正式 App 圖示；[圖示母圖與重建方式](Design/AppIcon/README.md) 保留生成提示詞及各平台尺寸入口。「關於」讀取目前 App 的版本與建置編號，並提供專案原始碼及第三方授權。兩平台共用的 [隱私清單](Docs/Privacy.md) 記錄本機偏好、工作階段計時與模型儲存空間檢查的 API 用途；本輪打包與畫面驗證見 [收尾紀錄](Verification/app-polish/README.md)。

快捷鍵：`⌘O` 匯入、`⌘Return` 開始／暫停、`⌘.` 停止、`⇧⌘L` 顯示／隱藏浮窗、`⌥⌘L` 關閉浮窗點擊穿透。這些是 App 內快捷鍵；使用其他 App 時可從選單列操作。

Mac「設定 → 啟用範圍」可選 **始終產生字幕**（預設）或 **僅在指定 App／網站**。選擇系統音訊並按「開始字幕」後，只有目前前台 App 或網站符合清單時才啟用；切走會自動暫停，返回後繼續。手動暫停／停止後不會自行恢復。設定與清單會保留；本機媒體播放及 iPhone／iPad 不受此規則影響。

App 可從已開啟清單或 .app 選檔加入。網站以網域及其子網域比對，例如 `youtube.com` 包含 `www.youtube.com`；輸入首頁網址即可，不接受個別頁面路徑。App 與網站符合任一項即可；加入整個瀏覽器 App 代表該瀏覽器所有網頁都允許。網站判斷支援 Safari、Chrome、Edge、Brave，需先在設定按「設定瀏覽器權限」明確授權讀取目前網址。無權限、逾時或無法辨識網址時保持暫停；網址不儲存、不讀取頁面內容。App 切換由系統通知判斷，同一瀏覽器內的分頁／網址每 0.75 秒檢查一次，故不是零延遲。這是依前台狀態啟停整體系統音訊，不是依音訊來源隔離其他 App。詳細規則及測試見 [字幕啟用範圍](Docs/CaptionScope.md)。

iPhone 與 iPad 窄視窗使用底部四分頁；iPad 寬版與 Mac 保留側欄。小螢幕控制列、模型操作及大字級字幕歷史可改為直排，手機支援直向與左右橫向。適配與驗證紀錄見 [iOS 適配](Verification/ios-adaptation/README.md)。

## 開發建置

已提供 [LiveCaption.xcodeproj](LiveCaption.xcodeproj)，**直接用 Xcode 開啟，無須安裝 XcodeGen**。本次編譯環境為 Xcode 27.2（27B52）／Swift 6.4.2；deployment target 為 26.0。Xcode 26 的相容性尚未實測，建議使用本次驗證版本。

命令列建置需選用完整 Xcode 的 Developer 目錄；只有 Command Line Tools 不足以建置 iPad target。此次驗證在 Apple Silicon Mac 執行；平台音訊與工作階段測試腳本固定編譯 arm64，未驗證 Intel Mac。模擬器執行測試另需在 Xcode 安裝 iOS／iPadOS 26＋ runtime。

首次取得原始碼時，開發者需下載並校驗固定的官方 XCFramework：

```sh
bash Scripts/fetch-whisper.sh
open LiveCaption.xcodeproj
```

已存在且可用的 `Packages/CaptionCore/Frameworks/whisper.xcframework` 不必重複下載。二進位與模型權重排除於版本控制；App 發行包會內含引擎，不要求使用者執行上述腳本。下載腳本使用 macOS 內建 curl、shasum、unzip，不需要 Python。

Xcode scheme：

| Scheme | 用途 |
|---|---|
| `LiveCaptionMac` | 原生 macOS App |
| `LiveCaptioniPad` | 原生 iPhone／iPad 通用 App／模擬器（保留既有名稱與 bundle ID） |

亦可執行無簽署的編譯／連結驗證，不會安裝或發布 App：

```sh
bash Scripts/build.sh mac
bash Scripts/build.sh ios-simulator
bash Scripts/build.sh ios-device
# 同時驗證 Mac 與 iOS Simulator（舊 ipad-* 參數仍可用）
bash Scripts/build.sh all
```

`CAPTION_BUILD_DIR` 可指定 DerivedData 路徑，`CAPTION_CONFIGURATION` 可選 `Debug`／`Release`。一般開啟專案不需要重新生成；只有維護 `project.yml` 後才使用開發工具 XcodeGen 2.46.0 同步產生專案。

## 簽署與權限

- **Mac**：在 `LiveCaptionMac → Signing & Capabilities` 選擇自己的 Team，必要時把 `com.example.livecaption.mac` 改為唯一 bundle ID。產品使用 App Sandbox；網路權限只用於模型下載，本機檔案透過系統選檔／存檔介面授權。
- **系統收音**：使用 ScreenCaptureKit，不安裝虛擬音效驅動。首次開始時由系統要求錄製權限；被拒時到「系統設定 → 隱私權與安全性 → 螢幕與系統音訊錄製」允許 App，必要時重新開啟。此版不擷取麥克風、不保存螢幕影片。
- **iPhone／iPad 真機**：為 `LiveCaptioniPad` 選自己的 Team、唯一 bundle ID，啟用裝置 Developer Mode，再由 Xcode Run。一般產品不需要 App Group；音訊背景能力僅用於真正的本機媒體與系統子母畫面，不播放靜音來維持執行。未啟動子母畫面時進入背景會停止辨識。
- **研究用廣播**：另開 [Experimental/ReplayKitProbe.xcodeproj](Experimental/ReplayKitProbe.xcodeproj)。host 與 extension 需要同一個已簽署 App Group；26 版 ReplayKit 設定及 27 版新的 ScreenCaptureKit 公開研究路徑見 [平台可行性](Docs/PlatformFeasibility.md)。這個診斷 App 不做語音辨識，也不嵌入一般產品；27＋替代路徑尚未實作或真機驗證。

Unsigned build 通過不代表真機簽署、安裝、權限授予或功能已驗證；本交付沒有進行 App Store／TestFlight 發布或 Mac notarization。

## 共用核心與依賴

`App/Media` 以 AVFoundation 讀取本機媒體，跟隨實際播放位置供應 PCM；`App/Platform/macOS` 提供 ScreenCaptureKit 與 NSPanel，`App/Platform/iOS` 提供本機媒體字幕的系統子母畫面。這些介面連接 `Packages/CaptionCore` 的音訊正規化、音量型 VAD、重疊分段、序列化 whisper.cpp 推論、臨時／確認字幕及 TXT／SRT 資料模型。核心的 `CaptionDisplayFilter` 僅處理顯示文字；`App/Session` 協調取消、跳轉、子母畫面生命週期與帶 generation 的字幕事件；`App/Models` 共用下載、儲存與完整性驗證。

引擎固定 **whisper.cpp 1.9.5**／commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`，採官方 `b5454` XCFramework 並鎖定 SHA-256，詳見 [依賴 manifest](ThirdParty/whisper-dependency.json)。本版使用可用的 Metal／Accelerate／CPU；未提供 Core ML encoder 資產，因此**不宣稱 Core ML 加速已啟用或驗證**。

模型包含多語言 tiny、base、small、medium、large-v3-turbo、large-v3，沒有 `.en` 選項。檔案存於 App 沙盒的 `Application Support/LiveCaption/Models`；只有下載且驗證成功才標為可用，支援取消、重試、切換及刪除使用中以外的模型。[模型來源與雜湊](Docs/Models.md) 區分精確檔案大小與估計執行記憶體需求。

第三方引擎與模型的 MIT 聲明保留於 [ThirdParty](ThirdParty) 及 App 內附的 `ThirdPartyNotices.txt`。三個技術參考專案的版本、授權、依賴與不採用項目列於 [原始碼稽核](Docs/ReferenceAudit.md)。未引入 Tauri、React、Python 或遠端推論服務作為 App 執行依賴。

## 驗證與目前限制

以下連結保留既有版本的驗證證據。0.2.0 新增的選單列／收起主視窗、語氣詞顯示過濾及本機媒體子母畫面需以 [本輪驗收清單](Docs/Acceptance.md#020-本輪發布驗證) 的獨立結果判定；目前不宣稱真機背景字幕已驗收。

- [程式整理與一致性檢查](Verification/code-cleanup/README.md)：共用頁面／自適應控制、偏好儲存、模型／媒體清理與測試編譯流程，含本輪回歸及原生畫面。
- [英文／中文驗證](Verification/languages/README.md)：Tiny、Base 的真人英文／普通話直接及串流辨識，另有六項 iPad Simulator App 整合測試；完整保留誤辨與模型幻覺。
- [延遲優化實測](Verification/latency/README.md)：首次臨時結果與更新更早、忙時避免無效重算、pause 後重用已載入模型；列出轉寫品質、推論成本及測量限制。
- [Bug 自查與修復](Docs/BugAudit.md)：暫停尾音、相鄰字幕漏字、過時結果、模型啟動校驗與媒體生命週期等修正，含修改前失敗及最新回歸證據。
- [核心實測](Verification/engine/README.md)：Apple M4 Pro 上以 tiny 辨識兩段日語、兩段法語真人音訊；包含逐字稿、錯誤率、串流延遲、取消、靜音及約三分鐘重播記憶體紀錄。tiny 在部分樣本有明顯錯誤，不能等同電影字幕品質。
- [Base 模型實測](Verification/base/README.md)：相同四段真人音訊的原文轉寫、SRT、CER／WER、推論時間及 RSS。日語兩段誤差較 tiny 低，法語一段較低、一段較高；不是準確率承諾或即時延遲驗收。
- [App 工作階段整合測試](Verification/session-integration.md)：真實播放器與推論串接、暫停、兩種跳轉、正常 EOF、非重疊匯出、清除與釋放。
- [iPad 模擬器整合測試](Verification/ipad/README.md)：四項真人音訊／影片測試通過，包含預設加速要求的 CPU 備援；不代表實體 iPad 或背景辨識已驗證。
- [模型／媒體測試](Docs/Validation-Models-Media.md)：真實 tiny 下載、取消立即重試、SHA-256、損壞拒絕，以及媒體播放、暫停、跳轉與時間軸。
- [平台可行性與離線 PCM 測試](Docs/PlatformFeasibility.md)：有界收音入口、重採樣、時間戳及獨立 ReplayKit／PiP probe；明確分開編譯證據與真機證據。
- [驗收矩陣](Docs/Acceptance.md)：完整 UI 回歸、兩小時連續運行、大型模型、背景音樂／多人說話、iPad 真機、DRM、全螢幕和混合縮放多螢幕仍有待測項。

開發檢查可執行 `swift test --package-path Packages/CaptionCore`、`bash Scripts/test-models.sh`、`bash Scripts/test-platform-audio.sh` 及 `bash Scripts/test-media.sh /path/to/audio.wav`。可選的 `Scripts/fetch-test-audio.py` 只供開發者取得有授權的測試音訊；App 與 Xcode 建置完全不依賴它。
