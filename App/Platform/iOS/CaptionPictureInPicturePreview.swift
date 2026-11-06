#if os(iOS)
import SwiftUI
import UIKit

/// Keep this preview on screen until the user starts PiP. System PiP takes over
/// the same display layer; the Session-owned controller survives view changes.
struct CaptionPictureInPicturePreview: UIViewRepresentable {
    let controller: CaptionPictureInPictureController

    func makeUIView(context: Context) -> CaptionPictureInPictureSurface {
        controller.surface
    }

    func updateUIView(_ uiView: CaptionPictureInPictureSurface, context: Context) {
        controller.refresh()
    }
}
#endif
