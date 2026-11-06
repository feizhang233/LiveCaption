#if os(macOS)
import AppKit
import SwiftUI

/// Native, non-activating subtitle panel. All geometry uses AppKit points.
/// The main window always remains the recovery surface for click-through mode.
@MainActor
final class CaptionPanelController {
    private var panel: CaptionPanel?
    private var clickThrough = false
    private var alwaysOnTop = true
    var isVisible: Bool { panel?.isVisible == true }
    var screenNames: [String] { NSScreen.screens.map(\.localizedName) }

    func show<Content: View>(content: Content) {
        let panel: CaptionPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = CaptionPanel(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 170),
                styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Live Caption 字幕"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 320, height: 100)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            self.panel = panel
            if !panel.setFrameUsingName("LiveCaption.SubtitlePanel") { selectScreen(index: 0) }
            panel.setFrameAutosaveName("LiveCaption.SubtitlePanel")
        }
        panel.contentView = NSHostingView(rootView: content)
        panel.ignoresMouseEvents = clickThrough
        panel.level = alwaysOnTop ? .statusBar : .normal
        constrainToVisibleScreen()
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
    func setClickThrough(_ enabled: Bool) {
        clickThrough = enabled
        panel?.ignoresMouseEvents = enabled
    }
    func setAlwaysOnTop(_ enabled: Bool) {
        alwaysOnTop = enabled
        panel?.level = enabled ? .statusBar : .normal
    }
    func selectScreen(index: Int) {
        guard let panel, NSScreen.screens.indices.contains(index) else { return }
        let available = NSScreen.screens[index].visibleFrame
        panel.setFrame(CaptionPanelPlacement.frame(size: panel.frame.size, on: available), display: true)
    }
    func resetPosition() { selectScreen(index: 0) }

    private func constrainToVisibleScreen() {
        guard let panel else { return }
        let screens = NSScreen.screens
        guard let screen = screens.max(by: {
            let left = $0.visibleFrame.intersection(panel.frame)
            let right = $1.visibleFrame.intersection(panel.frame)
            return left.width * left.height < right.width * right.height
        }) else { return }
        let intersection = screen.visibleFrame.intersection(panel.frame)
        if intersection.width < 80 || intersection.height < 40 {
            selectScreen(index: 0)
        } else if !screen.visibleFrame.contains(panel.frame) {
            // A saved large panel can still partly intersect a smaller display.
            // Checking only for a completely off-screen panel leaves it clipped.
            panel.setFrame(CaptionPanelPlacement.restoredFrame(panel.frame, on: screen.visibleFrame), display: true)
        }
    }
}

/// Pure placement calculation so screen changes can be checked without opening a window.
enum CaptionPanelPlacement {
    static func frame(size: NSSize, on available: NSRect) -> NSRect {
        let inset = min(16, max(0, min(available.width, available.height) / 2))
        let width = max(0, min(size.width, available.width - inset * 2))
        let height = max(0, min(size.height, available.height - inset * 2))
        let y = min(available.minY + 40, available.maxY - inset - height)
        return NSRect(x: available.midX - width / 2, y: max(available.minY + inset, y), width: width, height: height)
    }

    static func restoredFrame(_ frame: NSRect, on available: NSRect) -> NSRect {
        let fitted = self.frame(size: frame.size, on: available)
        let x = min(max(frame.minX, available.minX), available.maxX - fitted.width)
        let y = min(max(frame.minY, available.minY), available.maxY - fitted.height)
        return NSRect(x: x, y: y, width: fitted.width, height: fitted.height)
    }
}

private final class CaptionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
#endif
