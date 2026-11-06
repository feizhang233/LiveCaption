# Live Caption App 圖示

2026-11-06，使用內建 imagegen 製作。藍色電影閱讀背景、白色字幕框、青色聲音條與兩行字幕構成同一標誌；不含語言字母，沿用 DESIGN.md 的主色與閱讀背景色。

- `live-caption-ipad-1024.png`：不含 alpha 的完整方形，讓系統套用外框。
- `live-caption-mac-1024.png`：透明外緣與圓角藍色圖塊，用於傳統 macOS AppIcon 各尺寸。
- `bash Scripts/generate-app-icons.sh`：僅以 macOS 內建 sips 匯出尺寸，寫入 `App/Resources/Assets.xcassets/AppIcon.appiconset`；不呼叫生成服務、不需 Python 或網路。

兩個母圖均為 1024 × 1024，生成結果使用 sips 等比例縮小。Mac 圖塊與外緣由 imagegen 製作，未以程式重繪。此次使用現有 AppIcon asset catalog 路徑，沒有製作 Icon Composer 分層玻璃／動態外觀資產；深色與著色樣式由系統衍生。

## 主圖提示詞

```text
Use case: logo-brand
Asset type: production app icon master for Live Caption, a native macOS and iPad app that turns local audio into original-language subtitles.
Primary request: Create one exceptional, minimal, instantly readable app icon combining an audio waveform and subtitle lines into a single coherent mark.
Scene/backdrop: full-bleed square deep cinema-blue background, with a restrained smooth blue lighting gradient based on #276B99 and #101923. The artwork fills the entire square, edge to edge, with NO rounded outer corners, NO outside padding, NO transparency.
Subject: a centered, bold ivory-white rounded rectangular caption window outline. Inside this window a short set of five blue-white rounded vertical waveform bars occupies the upper portion, and two crisp horizontal white subtitle strokes occupy the lower portion. The frame is a single simple continuous silhouette, almost a speech caption panel, with a tiny restrained tail. All forms are bold and spacious enough to read at 32 pixels. Balanced optical center. One symbol, no extra objects.
Style/medium: refined native Apple application icon artwork; precise geometry, subtle soft dimensional edge and quiet luminous depth, strong contrast, clean restrained finish. No photorealistic surface.
Composition/framing: straight-on square 1024x1024 master artwork, mark centered and occupying approximately 64 percent of the square. Ample blue within the square around the mark.
Color palette: deep cinema navy #101923, signature blue #276B99, icy cyan highlight, warm white.
Text: none.
Avoid: any letters or words including CC, subtitles as real text, microphones, headphones, play buttons, translation symbols, globes, sparkles, busy waves, multiple tiles, product mockups, device frames, white margins, outer squircle masks, drop shadows outside the artwork, watermarks.
```

## Mac 適配提示詞

```text
Edit target: the generated Live Caption master. Preserve the blue gradient, white caption frame, cyan waveform and two white subtitle strokes. Uniformly scale the entire artwork into a centered 824 × 824 tile on a 1024 × 1024 canvas, clip the tile to a native rounded square with approximately 180 pixel corner radii, and keep the outside actually transparent with a subtle tight shadow. No redesign, new marks, text, perspective or mockup.
```

圖示格式依 [Apple：以 asset catalog 設定 App 圖示](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) 與 [App Icon Type](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/AppIconType.html)。
