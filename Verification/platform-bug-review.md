# 平台程式自查與回歸

2026-11-06，範圍為 macOS 收音／字幕浮窗及獨立 ReplayKit／PiP 診斷工具。此次沒有開啟視窗、啟動廣播、擷取音訊或要求錄製權限，也沒有修改 Session／UI／Models／Media／CaptionCore。

## 修正

| 問題 | 修正 | 驗證界線 |
|---|---|---|
| ReplayKit 診斷 ring 對時間缺口容許 100 ms，會把 60 ms 斷訊兩側的音訊組成時間戳不正確的單一封包；80 ms 重疊也會被拼接 | 超過一個 sample 的缺口／重疊即捨棄未完成封包，以新來源時間開始；真正連續音訊仍合併 | 實際 writer 的缺口、重疊、連續組包回歸通過 |
| 浮窗切到較小螢幕時裁切高度但固定向上偏移 40 pt，最大高度可超出可見區上緣 8 pt；部分可見的舊大浮窗也不會恢復完整可見 | 同時限制位置與尺寸；重新顯示時修正部分離屏的儲存 frame | 實際幾何函式對小螢幕、超大 frame、負座標及部分離屏回歸通過；未開啟 NSPanel |
| PiP 暫停 delegate 原本只改狀態，仍繼續產生新影格 | 暫停時停止送幀並凍結 timebase；恢復時對齊目前 host clock，通知 AVKit 更新狀態 | Simulator／device 編譯通過；實際 PiP 互動仍待 iPad 驗證 |

另補強 ReplayKit 錯誤清理：先釋放 converter／刪除暫存音訊，解鎖後才通知框架停止，不依賴框架一定回呼 `broadcastFinished`。PiP 同步播放狀態以鎖保護，UI／timebase 更新明確切回 MainActor；延後到達的啟動回呼會遵守已提出的停止要求。無法配置 timebase、pixel buffer 或繪圖 context 時顯示失敗，不送出未繪製影格。這些生命週期防護通過編譯，未宣稱已實測框架所有回呼交錯。

## 實際執行

`bash Scripts/test-platform-audio.sh /tmp/live-caption-core-build/out/Products/Debug`：exit 0。測試直接編譯本版平台／診斷原始碼，沒有建立 SCStream 或 SampleHandler 實例。涵蓋：

- Mac 100 秒 48 kHz stereo → 16 kHz mono、44.1／16 kHz、右聲道、格式變化及來源時鐘回退。
- 最新 8 塊有界入口、淘汰秒數、終止及消費者取消。
- ReplayKit converter 10 秒右聲道音訊、60 ms 時間缺口、格式／時鐘重設。
- 實際寫入及讀回 ring JSON：缺口／重疊、連續組包、最多 32 個槽、固定 payload、session ID、最新 8 秒及刪除。
- 浮窗幾何恢復，不建立視窗、不依賴當前顯示器配置。

合成 ring 測試明確採普通原子暫存檔；將 iOS 檔案保護選項用於此次 Mac 測試時曾遇到讀取權限錯誤，因此**沒有把該測試當成 iPad 鎖屏資料可用性的證據**。診斷產品的預設寫入仍保留 `.completeFileProtectionUnlessOpen`，未降低其檔案保護。

以下兩個最終命令均 exit 0，使用 Xcode 27.2、deployment 26.0，沒有安裝或啟動 App：

```sh
xcodebuild -quiet -project Experimental/ReplayKitProbe.xcodeproj \
  -scheme LiveCaptionProbe -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/live-caption-probe-review-simulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project Experimental/ReplayKitProbe.xcodeproj \
  -scheme LiveCaptionProbe -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/live-caption-probe-review-device CODE_SIGNING_ALLOWED=NO build
```

測試日誌：`/tmp/live-caption-platform-bug-review.log`、`/tmp/live-caption-probe-review-simulator.log`、`/tmp/live-caption-probe-review-device.log`。這些是本機暫存紀錄；可透過上述命令重新執行。

仍待測：Mac 真實系統音訊及權限、浮窗全螢幕／多螢幕／穿透互動、iPad 廣播／PiP、背景存活、檔案保護與記憶體上限。離線回歸與編譯成功不代表上述項目已通過。
