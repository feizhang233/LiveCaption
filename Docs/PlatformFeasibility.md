# 平台能力與驗證界線

## 決策

0.2.0 的 iPhone／iPad 產品已加入本機媒體字幕子母畫面（PiP）：使用者匯入本機音訊或影片，開啟浮動字幕後，可透過系統 PiP 在其他 App 上方觀看字幕。來源仍是本 App 播放的媒體，不能擷取其他 App 的聲音。Mac 則使用獨立字幕面板與選單列控制，主視窗可收起。

產品 PiP 已接入主 App，但實體 iPhone／iPad 的背景音訊、長時間推論、記憶體與耗電尚未完成端到端驗證。開啟時改用 CPU，只有 PiP 已啟動或正在啟動、且本機媒體工作階段符合條件時才保留背景辨識；否則進入背景會停止並釋放模型。PiP 關閉或啟動失敗會還原加速偏好，在背景時並停止辨識。Mac 與 iOS device 建置已通過；編譯不等同真機驗收。

研究用 ReplayKit／PiP 工具仍獨立放在 `Experimental/ReplayKitProbe.xcodeproj`；它不連伺服器，不裝載 Whisper，畫面明確標示「診斷資料，非辨識字幕」。跨 App 音訊與下述 27＋ ScreenCaptureKit 路徑仍屬獨立研究，沒有隨本輪產品 PiP 一起完成。

## macOS 實作

`MacSystemAudioCapture` 使用 ScreenCaptureKit，取得使用者的螢幕與系統音訊錄製權限；排除本 App 音訊，接收 48 kHz stereo buffer，透過共用 `PCMNormalizer`／`AVAudioConverter` 降為 16 kHz mono Float32。轉換在 serial queue，輸出時間從本次 capture 的第一個 presentation timestamp 起算；遇格式改變或時間不連續會重建轉換器。輸出只有一個 `AsyncStream` 消費者，入口最多保存最近 8 塊音訊；超量時淘汰最舊音訊並累計略過秒數，保留原始時間戳。取消消費者會觸發相同 capture generation 的清理，舊 stream 不可停止後來的新 capture。沒有錄製／儲存畫面，只有必要的低頻小尺寸 screen stream 被即時丟棄。API 行為見 [Apple ScreenCaptureKit capturesAudio](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio) 與 [channelCount](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/channelcount)。

`CaptionPanelController` 是非啟用式 NSPanel，可拖移、縮放、置頂、跨 Spaces／全螢幕輔助、點擊穿透。位置及大小使用 AppKit 點，避免混用 Retina 像素。主視窗提供穿透開關／重設位置；移除顯示器後重新顯示會將完全離屏的面板移回可見螢幕。系統權限、全螢幕第三方播放器和混合縮放多螢幕仍需實際測試，不能由 collectionBehavior 旗標推論成功。

權限被拒時顯示設定路徑；音訊回呼中斷則上報錯誤。持續沒有音訊或全零 buffer 可能來自暫停、靜音、來源政策或受保護內容，**無法僅憑靜音判定 DRM**，提示應列出可能原因。App 內媒體則可使用 `AVAsset.hasProtectedContent` 明確拒絕不可讀取的保護內容。

## iPadOS 26：ReplayKit 與跨程序傳輸

Apple 公開 [RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler) 提供 app 音訊與麥克風等 sample callback。這只證明 API 入口存在，不保證任意 App／受保護影片都會交付可辨識音訊。使用者須透過系統 broadcast picker 主動開始；本專案 probe 忽略 video 與 mic payload，僅處理 `.audioApp`。

probe 以 16 kHz mono PCM、每塊 0.25 秒、32 個循環 slot 寫入 App Group。每塊含 session UUID、sequence、presentationTime 及 sample rate；原子替換 slot 使讀取者不看到半寫入檔案，最多保留最近 8 秒。新 session 清除舊音訊，正常停止時刪除；被系統終止時可由 host 的「刪除殘留診斷音訊」清理。共享目錄排除備份。任何未來消費者都必須檢查 session、sequence 缺口與 stale age，不能在 App 恢復後回放積壓音訊當作即時字幕。

不連續音訊會捨棄未完成封包，以新來源時間重新組包，避免把缺口兩側資料寫成假連續時間軸；預設檔案保護為 `.completeFileProtectionUnlessOpen`。相關回歸、浮窗恢復及 PiP 暫停修正見 [平台自查紀錄](../Verification/platform-bug-review.md)。

App Group 是資料交換機制，不是執行排程機制。Apple 的 [extension programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html) 說明 extension 記憶體預算比前景 App 小，且資源壓力可導致終止；沒有在這裡承諾一個通用的 MB 上限。probe 不載入任何 Whisper 模型，也不宣稱 tiny 能安全放進 extension。

## 背景生命週期與 PiP

產品的 `CaptionPictureInPictureController` 使用 sample-buffer PiP 顯示目前字幕，時間軸、播放／暫停及跳轉回到同一個本機媒體工作階段。僅在系統 delegate 確認後顯示已開啟；不支援、無法啟動與逾時會提供狀態。`UIBackgroundModes=audio` 與 `AVAudioSession` 的播放模式服務於真正的匯入媒體，沒有無聲音軌或假的背景保活來源。停止會取消仍在準備的 PiP 請求，避免模型載入完成後重新啟動已停止的工作階段。

Apple 的 [sample-buffer PiP content source](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class/init%28samplebufferdisplaylayer%3Aplaybackdelegate%3A%29) 可承載自訂影格；probe 用實際診斷狀態文字生成 CVPixelBuffer，使用公開 playback delegate、renderer 背壓及單調 host-clock 時間。只有 `pictureInPictureControllerDidStartPictureInPicture` 回呼才顯示成功，失敗保留系統錯誤。不使用 private KVC，不偽裝視訊通話。

PiP 的顯示能力不代表 Whisper inference 取得永久背景 CPU/GPU 時間。[Apple 背景執行指引](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time) 的有限延長機制也不是長時間即時推論保證。probe 沒有 `UIBackgroundModes`，沒有無聲音軌，沒有假 VoIP／背景音訊。若系統拒絕這個無實際媒體播放的 PiP probe，結果應記為失敗，不能為了通過而加入虛假背景模式。

## iPadOS 27：ScreenCaptureKit 替代路徑

Apple 現行 [ScreenCaptureKit 文件](https://developer.apple.com/documentation/screencapturekit) 已涵蓋 iOS／iPadOS，說明它取代 ReplayKit 的串流／鏡像用途，不再需要 broadcast extension，並推薦系統 `SCContentSharingPicker`。文件 metadata 與本機 Xcode 27.2 headers 均將 iPadOS 入口標為 **27.0 起可用**；這不能當作本產品最低支援的 iPadOS 26 能力。ReplayKit broadcast API 則在 27.0 標記棄用，並非本次已證明其 runtime 移除。逐項 SDK 查核見 [相容性稽核](ReferenceAudit.md)。

Apple 的 [背景模式文件](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes) 已列出正式 **Screen Capture** capability／`UIBackgroundModes` 值 `screen-capture`，用途是背景擷取及串流螢幕內容。因此，27＋確實有值得實作驗證的公開替代路徑；不能把 26 版 probe 的生命週期限制說成所有版本都沒有公開 API。此能力仍不能直接推論為任意 Whisper CPU／GPU 工作的持續執行保證。

下一個獨立實驗應以 `#available(iOS 27.0, *)` 隔離：使用者透過系統 picker 選取內容 → `SCStream` `.audio` → 有界 PCM 緩衝 → 主程序本機推論；依官方要求配置 `NSScreenCaptureUsageDescription` 與真正的 Screen Capture capability。先量測背景音訊交付、推論是否持續、記憶體／熱限制，再驗證字幕 PiP、權限撤銷及受保護內容。Mac 的 display filter initializer 和部分 stream 更新方法在 iOS 明列不可用，不能直接搬用現有 Mac 收音實作。

**本次只完成公開文件及 SDK 可用性查核，未實作／編譯／真機驗證此 27＋路徑**；產品及既有 probe 未加入 `screen-capture` 模式。iPadOS 26 的本機媒體方案保留，現有 ReplayKit probe 僅作 26 版研究；兩條路徑須分開驗收。

## 研究工具建置與簽署

直接在 Xcode 開啟 `Experimental/ReplayKitProbe.xcodeproj`，選 scheme `LiveCaptionProbe`。此工具不需要產品 Whisper framework。專案已生成；只有改動 YAML 後才需要開發工具 XcodeGen 2.46.0：

```sh
xcodegen generate --spec Experimental/project.yml --project Experimental
xcodebuild -project Experimental/ReplayKitProbe.xcodeproj -scheme LiveCaptionProbe \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/live-caption-probe-derived CODE_SIGNING_ALLOWED=NO build
```

真機執行前，在兩個 target 選擇自己的同一個 Team，將 `com.example.livecaption.probe` 改為唯一 bundle ID（extension 為 `<host bundle ID>.broadcast`）。使用能配置 App Groups 的 Team，在 Apple Developer 建立同一個 App Group；host 和 extension 的 App ID／provisioning profile 都必須包含該群組，並將專案的 `LIVE_CAPTION_APP_GROUP` 改為同一識別碼。不使用任何參考專案作者的 Team ID。一般 signing／entitlement 配置無法用 unsigned simulator build 代替驗證。

## 待真機執行的驗收矩陣

| 場景 | 觀察與通過條件 | 本次狀態 |
|---|---|---|
| iPad 26：其他 App 播放無保護日語／法語音訊 | `.audioApp` 計數增加、格式／PTS 有效、8 秒 ring 有新 sequence | 待真機 |
| iPad 26：主 App 在前景／分割畫面／背景 | 分別記錄 callback、IPC 延遲、缺塊及主 App tick 停止時間 | 待真機 |
| iPhone／iPad 產品：本機媒體字幕 PiP 起動、停止、復原 | delegate 成功或具體錯誤；播放／暫停／跳轉與主 App 同步 | 已實作並通過建置；待真機 |
| iPad：鎖屏、離開 10／30 分鐘、其他 App 前景 | 記錄 suspension/jetsam；不宣稱背景推論 | 待真機 |
| iPhone／iPad 產品：PiP 的 CPU inference／RSS | 真正音訊及模型，記錄熱降頻、記憶體壓力、長時間漏字與關閉後清理 | 待真機；PiP 使用 CPU，probe 不做推論 |
| iPad 27：ScreenCaptureKit | 系統 picker → SCStream 音訊；正式 screen-capture 模式下的 CPU／GPU、PiP、記憶體及權限實測 | 官方文件／SDK 入口已查核；程式與真機待做 |
| macOS：拒絕／撤銷錄製權限 | 顯示明確錯誤、停止時釋放 capture | 待互動測試 |
| macOS：Safari／其他播放器全螢幕 | 字幕可見、無焦點竊取、穿透可恢復 | 待互動測試 |
| macOS：Retina + 非 Retina、外接螢幕拔插 | 面板不離屏、尺寸以點一致、可拖移與重設 | 待實際多螢幕 |
| 受保護／靜音／沒有音軌 | 不產生假字幕；可操作提示、停止正常 | 待媒體實測 |

已完成：macOS 平台程式碼以 `arm64-apple-macos26.0` 通過 Swift typecheck；診斷 App＋ReplayKit extension 的 iOS Simulator 與 iPad device unsigned `xcodebuild` 均通過（Xcode 27.2 SDK、deployment 26.0）。這是編譯／連結證據，不是安裝、簽署或背景功能驗證。`bash Scripts/test-platform-audio.sh` 另以合成 PCM 建立真正 CMSampleBuffer，離線驗證 100 秒連續 48 kHz stereo → 16 kHz mono 轉換、44.1 kHz、格式切換、前向時間間隔、來源時鐘回退及重設；轉換緩衝延遲在該測試的 40 ms 容許值內。另驗證最新 8 塊入口上限、淘汰秒數、終止及消費者取消。此測試不建立 SCStream、不請求錄製權限，也不生成字幕，不能替代真實收音／辨識測試。產品核心的結果見 [核心實測](../Verification/engine/README.md)，整體狀態見 [驗收矩陣](Acceptance.md)。以上待測項沒有被標為已通過。
