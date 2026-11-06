# Live Caption

Native iOS/iPadOS 26+ / macOS 26+ local original-language captions on iPhone, iPad and Mac. No translation, server, Python runtime, virtual audio driver, or automatic model downloads. Japanese and French first; English, Chinese and optional language detection.

The first supported iPhone/iPad source is an imported local media file while the app is active. Compact iOS layouts use bottom tabs; regular iPad and Mac use a sidebar. ReplayKit / PiP diagnostics are a separately built feasibility target, not a promise of background inference. Mac also captures system audio using ScreenCaptureKit.

User-selected multilingual model downloads require exact size and SHA256 verification before use. Model files live in Application Support. Captions remain in the session until export or explicit clearing. Local audio/video is read through a security-scoped user selection and not uploaded.

Media timestamps are asset timeline seconds. Pause stops audio ingestion; seek invalidates pending recognition and resets audio windows. System audio uses a session clock. Never display demo text as a recognition result.
