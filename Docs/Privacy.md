# 隱私清單與實際 API 用途

核對日期：2026-11-06。[PrivacyInfo.xcprivacy](../App/Resources/PrivacyInfo.xcprivacy) 描述目前產品使用的 required-reason API，與 Mac／iPad 共用。這是依來源與目前固定依賴所做的宣告，不代表 App Store 審查、發行 archive 隱私報告或第三方完整二進位稽核已通過。

## 宣告與程式對照

| API 類別 | Reason code | 目前用途與來源 |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | 僅讀寫本 App 的外觀／字幕樣式、隱藏語氣詞、自動顯示浮窗、模型選擇、原語言、音訊來源及 Mac 啟用範圍偏好。外觀與字幕偏好由 `App/Session/AppPreferences.swift` 持有；另見 `App/Models/ModelStore.swift`、`App/Session/SessionController.swift`、`App/Session/CaptionScope.swift`。產品未使用 App Group 共用偏好或讀取其他 App 的 defaults。 |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | `SessionController` 使用 `systemUptime` 計算本次系統音訊的相對字幕時間，以及比較播放器前進量和實際經過時間以辨識跳轉；不保存或傳送裝置開機時間。匯出的 SRT 是這次工作階段內的相對時間。 |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `85F4.1` | `ModelStore.refreshStorage()` 讀取 `volumeAvailableCapacityForImportantUsageKey`／`volumeAvailableCapacityKey`，由 `ModelsView` 顯示可用儲存空間。 |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` | `ModelStore.download()` 在下載前確認模型大小加 256 MiB 餘量；不足時顯示錯誤並拒絕開始下載。容量數值不加入網路請求。 |

上述 reason 的選擇依 [Apple 的 API 分類與批准理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) 及 [理由代碼說明](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)。清單結構依 [App Privacy Configuration](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration) 與 [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)。

## 資料與網路

產品來源未整合分析／廣告／追蹤 SDK，也未提供上傳音訊、字幕或瀏覽網址的請求。清單因此設定 `NSPrivacyTracking=false`，追蹤網域與收集資料類別為空。音訊在本機辨識；歷史保留於本次工作階段，匯出由使用者選擇目的地。

0.2.0 的 iPhone／iPad 字幕 PiP 僅使用本 App 匯入的媒體與現有字幕。背景音訊模式用於真正的媒體播放，沒有新增跨 App 收音、麥克風擷取或資料上傳。隱藏語氣詞只改變顯示文字，TXT／SRT 匯出仍保留原始辨識內容。背景推論的真機可靠性另見 [平台能力與驗證界線](PlatformFeasibility.md)。

模型下載仍會連接目錄中指定的 Hugging Face 檔案服務及其重新導向端點。這些正常 HTTPS 連線會向服務端暴露連線所需的網路資訊；「本機辨識」不表示下載模型時沒有網路流量。Mac 網站範圍判斷只在記憶體讀取前台網址；儲存的清單是使用者主動新增的網域，沒有紀錄瀏覽歷史。

## 盤點範圍與後續核對

本次掃描 `App/**/*.swift`、`Packages/CaptionCore/Sources/**/*.swift`，並區分實際連入 App 的 `CaptionCore` library 與僅供開發的 `CaptionProbe`。後者也以 `systemUptime` 測量耗時，但不隨 App 交付。`CaptionCore/WhisperEngine.swift` 的 `fileSizeKey` 用於模型記憶體預估；`ModelIntegrity.swift` 的檔案大小／類型用於下載驗證。這些鍵本身不在本次核對的 Apple FileTimestamp API 列表中，來源亦未直接呼叫該列表的時間戳鍵或 `stat`／`fstat`／`getattrlist`，因此沒有僅憑檔案操作就套用任意 FileTimestamp reason。

固定的官方 whisper XCFramework（版本／SHA 見 [dependency manifest](../ThirdParty/whisper-dependency.json)）沒有附帶隱私清單。本次查看其公開 headers，並檢查 macOS、iOS device、iOS Simulator 二進位的未定義符號，未發現直接引用已列出的 required-reason entrypoints；有 `std::filesystem` 的檔案狀態介面匯入。headers／匯入符號只能提供有限證據，不能證明所有內部或間接實作行為。沒有修改第三方引擎，也不把 App 清單當作第三方獨立 framework 的替代宣告。

如更換引擎版本、加入 SDK／分析服務或修改設定、計時、檔案與空間 API，應重新盤點及核對 Apple 當時的規則。實際發行前另用 Xcode 的 archive 隱私報告確認所有 bundle；Apple 對 App 與第三方 SDK 各自宣告的要求見 [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。

本機可執行 `plutil -lint App/Resources/PrivacyInfo.xcprivacy` 驗證 plist 語法；語法通過不等於用途或發行審查通過。建置後仍需確認兩個產品 bundle 都包含 `PrivacyInfo.xcprivacy`。
