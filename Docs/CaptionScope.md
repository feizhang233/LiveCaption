# Mac 字幕啟用範圍

2026-11-06 新增，依使用者確認的「目前前台 App／網頁，切走後暫停」行為實作。沿用原文字幕功能，沒有新增跨語言翻譯。

## 操作與規則

- 設定 → 啟用範圍：始終產生字幕（首次預設）／僅在指定 App／網站。
- 選擇系統音訊，按開始字幕才啟用工作階段。沒有符合的前台內容時顯示等待狀態，不載入模型或開始收音；首次符合後才開始。
- 符合任一 App 或網站規則即可。App 以 bundle identifier 精確匹配；網站以網域或真正子網域匹配，`notyoutube.com` 不匹配 `youtube.com`。加入瀏覽器 App 代表允許該瀏覽器的所有頁面。
- 網站接受裸網域或 HTTP(S) 首頁網址；不默默把含路徑、查詢、帳密或連接埠的輸入擴大為整站規則，這類輸入會顯示更正提示。
- 切走後停止系統收音、取消待辨識音訊及臨時字幕。保留已確認歷史及已載入模型；返回後重用模型。快速切走再返回也必須先取消舊音訊工作。
- 自動等待時可按「暫停自動字幕」。手動暫停／停止後，前台切換不會復活工作階段。停止會卸載模型；模式及清單變更不清除字幕歷史。
- 規則只作用於 Mac 系統音訊；App 內本機媒體播放不受影響。iPad 沒有跨 App 前台／網站辨識入口。
- 這是前台條件控制整體系統音訊擷取，並非按播放聲音的 App 隔離音源。符合條件時，其他 App 同時發聲也可能進入字幕。

## 網頁與權限

支援 Safari、Google Chrome、Microsoft Edge、Brave。一般 App 只使用 NSWorkspace 的前台識別；網站規則使用唯讀 Apple Events 取得目前視窗分頁網址。輪詢不啟動瀏覽器、不自動請求權限。使用者需從「設定瀏覽器權限」明確允許各瀏覽器；未允許、逾時、瀏覽器無視窗或非 HTTP(S) 網址均不匹配網站規則。

網址只留在記憶體內進行比對，不保存瀏覽歷史或讀取頁面內容。始終模式不監看前台；沒有網站規則時不讀網址。App 啟用通知立即失效前一個頁面，鎖屏／休眠通知也清除前台。分頁／網址每 750 ms 輪詢一次，單次讀取逾時 600 ms，不能視為零延遲識別。

Mac 保留 App Sandbox，使用限定四個瀏覽器 ID 的 Apple Events 例外、hardened runtime automation entitlement 及明確用途說明。尚未進行 App Store 例外申請或發行簽署驗收。

API 依據：[Apple Events 權限預檢](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet)、[Apple Events 傳送](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/sendevent(options:timeout:))、[Automation entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.automation.apple-events)、[Sandbox Apple Events 例外](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)。屬性代碼依本機 Safari.sdef／Chrome scripting.sdef 及 [Chromium scripting.sdef](https://chromium.googlesource.com/chromium/src.git/+/lkgr/chrome/browser/ui/cocoa/applescript/scripting.sdef) 查核。

## 程式責任與驗證入口

- `App/Session/CaptionScope.swift`：可獨立測試的匹配規則與 UserDefaults 設定；損壞的已存模式回退到限制模式。
- `App/Platform/macOS/ForegroundContextMonitor.swift`：主動 App、網站、權限、逾時與過期回覆失效。
- `App/Session/SessionController.swift`：自動啟停、手動控制、音訊與字幕事件閘門。
- `App/UI/CaptionScopeSettingsView.swift`：原生 Picker、應用清單／選檔、網站輸入與權限入口。
- `bash Scripts/test-caption-scope.sh`：規則與持久化回歸。
- `bash Scripts/test-caption-scope-session.sh /path/to/ggml-tiny.bin`：真實模型、可控收音 adapter 及前台事件的整合回歸。
- `Scripts/build.sh mac`／`ipad-simulator`：平台編譯。實際執行證據與未完成情境列於 `Verification/caption-scope/README.md`。
