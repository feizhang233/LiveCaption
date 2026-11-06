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
A quiet companion to a film: content has the largest uninterrupted area; playback and recognition controls form a compact strip below it. Native product interface, Traditional Chinese UI with language endonyms. Japanese source audio does not imply a Japan-market business flow.

The signature is a cinema-like caption stage with a discrete timecode and explicit temporary/confirmed state. Never add fabricated waveforms, sample subtitles, decorative dashboards or marketing cards.

## Colors
`App/UI/Theme.swift` owns the palette above. Controls use system semantic primary/secondary surfaces and the blue accent. Caption reading defaults to white on an opaque dark background, independently of the application theme. Errors include text and a recovery action.

## Typography
System dynamic interface type; captions use an adjustable 18–64 pt system sans font with natural Japanese, French and Chinese shaping. Timecodes use monospaced digits. History wraps full text and is selectable; stage line count affects only the visible stage.

## Layout
NavigationSplitView on Mac and regular iPad, native collapsing sidebar in narrow layouts. Four destinations: 即時字幕, 媒體播放, 模型管理, 設定. Controls wrap using ViewThatFits; model lists and history own their scrolling. Minimum Mac window 660 x 520. Portrait iPad and split view retain all actions.

## Elevation & Depth
Native glassEffect on control strips and floating controls only. Caption background user choice: transparent, glass or solid; Reduce Transparency and Increased Contrast force readable opaque backing. No decorative motion; Reduce Motion always respected.

## Shapes
20 pt panels, 12 pt small controls, native rounded controls elsewhere. Glass has native material opacity; only transparent/solid applicable backgrounds expose opacity control.

## Components
Canonical owners: CaptionStage, SessionControls, StatusStrip, TranscriptHistory, ModelRow, GlassPanel. All screens share session status, model selection and subtitle preferences. The floating Mac panel hosts the same CaptionStage.

## Do's and Don'ts
Use native Button, Picker, Form, List, Slider, FileImporter and FileExporter. Keep destructive model deletion behind a named confirmation. Keep click-through recovery in the main window. Do not imply PiP keeps arbitrary work alive. Do not hide errors in disappearing toasts.
