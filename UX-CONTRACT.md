# UI contract

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Select/Listbox | SwiftUI Picker | Settings / ModelStore | native menu, segmented | builds + manual UI |
| Form | SwiftUI Form | AppPreferences | settings | builds + manual UI |
| Scrollbar | SwiftUI List / ScrollView | system settings | native | manual UI |
| Toast | StatusStrip | SessionController / ModelStore | persistent inline states | builds + manual UI |
| CRUD | ModelStore / ModelRow | verified model catalog | download, cancel, retry, delete, select | model checks |
| Navigation | RootView | AppPage | native NavigationSplitView | Mac + iPad UI |
| File upload | fileImporter | MediaController | local security-scoped read | playback verification |

Download → progress → verification → installed; errors retain retry. Cancel removes the temporary file. Selection only accepts verified models. Active model is unloaded before switching/deleting. No model auto-download.

Start loads the selected model, then begins actual audio ingestion. Pause stops ingestion and finalizes its tail. Stop cancels work, clears the temporary line, and releases model resources; history remains. New source clears session history explicitly in the import action. Seeking invalidates inflight results. First-confirmed timeline text remains immutable; exact overlapping boundary matches may be deduplicated. Ambiguous replay results are preserved separately and can be exported as TXT; primary SRT remains disjoint.

All four destinations use the same labels and persistent status. Disabled actions have visible explanations. User data is local; there is no cloud, analytics or background keep-alive. Caption history is bounded to 10,000 primary cues and 1,000 alternative records. Reaching capacity stops recognition and asks for export before clearing; earlier text is never silently deleted.

App theme: system/light/dark. Font, color, line count and background apply to stage and Mac overlay. Native material opacity is not simulated with whole-view opacity. Higher contrast and reduced transparency override transparent caption backgrounds. No repeating animation.
