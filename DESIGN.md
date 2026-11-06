---
version: alpha
colors:
  primary: '#276B99'
  readingSurface: '#101923'
  captionText: '#FFFFFF'
  secondaryText: '#A9BDCA'
typography:
  interface:
    fontFamily: 'SF Pro, system-ui, sans-serif'
  captions:
    fontFamily: 'SF Pro, Hiragino Sans, PingFang TC, system-ui, sans-serif'
  timecode:
    fontFamily: 'SF Mono, ui-monospace, monospace'
spacing:
  compact: '8px'
  standard: '16px'
  generous: '24px'
rounded:
  panel: '20px'
  control: '12px'
components:
  CaptionStage:
    backgroundColor: '{colors.readingSurface}'
    textColor: '{colors.captionText}'
  ControlSurface:
    rounded: '{rounded.panel}'
  PrimaryAction:
    backgroundColor: '{colors.primary}'
  CaptionMetadata:
    textColor: '{colors.secondaryText}'
---

## Overview
A quiet companion that normally stays in the background. The main window is a control centre for starting captions, choosing their source and managing models; the floating caption action is the clearest entry point. Mac users can put subtitles below another app's video, tuck away the main window and return through the menu bar. Native product interface, Traditional Chinese UI with language endonyms. Japanese source audio does not imply a Japan-market business flow.

The signature is unobtrusive floating text, with a cinema-like stage and explicit temporary/confirmed state inside the app. iPhone and iPad use a system PiP window for this app's local media, with its platform limits visible beside the action. Never add fabricated waveforms, sample subtitles, decorative dashboards or marketing cards.

## Colors
`App/UI/Theme.swift` owns the palette above. `App/Session/AppPreferences.swift` owns saved appearance choices, using the same injected UserDefaults store as the session. Controls use system semantic primary/secondary surfaces and the blue accent. Caption reading defaults to white on an opaque dark background, independently of the application theme. Errors include text and a recovery action.

## Typography
System dynamic interface type; captions use an adjustable 18–64 pt system sans font with natural Japanese, French and Chinese shaping. Timecodes use monospaced digits. History wraps full text and is selectable; stage line count affects only the visible stage.

## Layout
NavigationSplitView on Mac and regular iPad; compact iOS layouts use a native bottom TabView with a NavigationStack per destination. Four destinations: 即時字幕, 媒體播放, 模型管理, 設定. RootView owns one selection shared by both navigation layouts, so model guidance and successful imports select the correct destination. Compact content uses 16 pt outer padding; regular content uses 24 pt. Controls and model actions wrap using ViewThatFits; model lists and history own their scrolling. Accessibility Dynamic Type stacks transcript timecodes above text. Minimum Mac window 660 x 520. iPhone portrait/landscape and iPad split view retain all actions; video preserves its aspect ratio without a fixed minimum height. Native tab bars, navigation bars and sheets own safe-area insets.

Mac windows share one recognition session. iPhone and iPad support one app window and one playback session; only the media destination hosts the PiP preview. The live destination links to that owner rather than mounting the same UIKit display surface again.

Settings uses peer categories: 通用, 字幕樣式, 啟用範圍 (Mac only), 辨識與效能, 隱私與資料, 關於. A native segmented Picker sits above the grouped Form and falls back to a labeled menu when its content does not fit. Only the selected category's Form content is visible; the Form owns vertical scrolling. Keep the existing app sidebar as the only navigation column.

Mac live/media pages put the full-width floating-caption button before secondary options. Its label, icon and ON/OFF state make visibility clear without relying on color. Keep session controls and “收起主視窗” nearby; move detailed placement and appearance choices into the shared options menu. The menu-bar panel offers the same floating action, session state and controls, filler visibility, click-through recovery and a route back to the main window. Hiding the main window must not imply stopping recognition.

## Elevation & Depth
Native glassEffect on control strips and floating controls only. Caption background user choice: transparent, glass or solid; Reduce Transparency and Increased Contrast force readable opaque backing. The Mac floating subtitle defaults to text only, with a dark text edge/shadow over a fully clear window. A separately saved “顯示背景” preference opts into the shared caption background. No decorative motion; Reduce Motion always respected.

## Shapes
20 pt panels, 12 pt small controls, native rounded controls elsewhere. Glass has native material opacity; only transparent/solid applicable backgrounds expose opacity control.

The App icon combines the caption frame, five audio bars and two subtitle strokes on the existing cinema-blue palette. Masters and generation provenance live in `Design/AppIcon`; `Scripts/generate-app-icons.sh` exports the shared AppIcon catalog. iPad uses an opaque square for the system mask; the macOS raster has transparent outer padding and a rounded tile. It is a static asset, not an Icon Composer layered icon.

## Components
Canonical owners: CaptionStage, SessionControls, StatusStrip, TranscriptHistory, ModelRow, GlassPanel. CaptionWorkspaceView composes the live and media destinations from the same controls, status and history. AdaptiveControls owns horizontal-to-vertical control groups; CaptionPageContent owns their scroll surface, width and outer padding through CaptionLayout. TranscriptRow owns timestamp/text arrangement for both primary and alternative results. RootView owns navigation and import/export presentation; CaptionExport keeps document content, filename and type together. All screens share session status, model selection and subtitle preferences.

FloatingCaptionView hosts CaptionStage's overlay variant inside a borderless, non-activating Mac panel. Empty captions leave the reading surface clear. The compact native control strip appears for three seconds on opening, on hover, or while VoiceOver is active; its reserved space never moves the caption. CaptionPanelDragHandle and CaptionPanelResizeHandle own native pointer gestures. FloatingCaptionOptions is shared with the main window for keyboard-accessible width presets, screen placement and reset. SessionController owns visibility, topmost and click-through state and applies every change to CaptionPanelController, independent of which page is visible. CaptionTheme remains the canonical palette; the text edge uses semantic black and the saved ink remains shared.

DesktopCaptionToggle owns the prominent Mac action; BackgroundCaptionControls composes the menu-bar panel. MobileFloatingCaptionControls owns the iOS entry action, visible preview and preparation/error guidance; CaptionPictureInPictureController owns the system PiP lifecycle. Its system-sized surface is not a transparent desktop overlay. Local media and a ready model are prerequisites; CPU use and the inability to capture another app's audio are explained next to the action. Actual device background behavior remains a release-validation item.

CaptionDisplayFilter owns optional display-only filler removal for explicitly selected Japanese, English, French and Chinese. SessionController applies it consistently to stage, floating captions and history; auto-detection and other languages remain unchanged. Never mutate the recorded transcript or exports. A filler-only cue clears the floating text instead of repeating a previous subtitle.

## Do's and Don'ts
Use native Button, Picker, Form, List, Slider, FileImporter and FileExporter. Keep destructive model deletion behind a named confirmation. Keep click-through recovery in the main window and menu bar. Keep Stop distinct from hiding a window. Do not imply PiP captures Safari or keeps arbitrary work alive; it accompanies real local-media playback. Do not hide errors in disappearing toasts.
