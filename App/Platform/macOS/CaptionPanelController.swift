#if os(macOS)
import AppKit
import SwiftUI

private let captionPanelFrameName = "LiveCaption.SubtitlePanel"
private let captionPanelMinimumSize = NSSize(width: 320, height: 144)

/// Native, non-activating subtitle panel. All geometry uses AppKit points.
/// The main window always remains the recovery surface for click-through mode.
@MainActor
final class CaptionPanelController {
    private var panel: CaptionPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var clickThrough = false
    private var alwaysOnTop = true
    var screenNames: [String] { NSScreen.screens.map(\.localizedName) }

    func show<Content: View>(content: Content) {
        let panel: CaptionPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = CaptionPanel(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 170),
                styleMask: [.borderless, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Live Caption 字幕"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.isMovableByWindowBackground = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            self.panel = panel
            if !panel.setFrameUsingName(captionPanelFrameName) { selectScreen(index: 0) }
            panel.setFrameAutosaveName(captionPanelFrameName)
        }
        let root = AnyView(content.frame(minWidth: captionPanelMinimumSize.width,
                                         minHeight: captionPanelMinimumSize.height).id(UUID()))
        if let hostingView {
            hostingView.rootView = root
        } else {
            let hostingView = NSHostingView(rootView: root)
            // Publish only the explicit minimum, keeping ideal content changes
            // from resizing the panel while captions and hover controls update.
            hostingView.sizingOptions = [.minSize]
            self.hostingView = hostingView
            panel.contentView = hostingView
        }
        panel.minSize = captionPanelMinimumSize
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

    func resize(to width: CGFloat) {
        guard let panel else { return }
        resize(to: NSSize(width: width, height: panel.frame.height))
    }

    /// Button/menu alternative to dragging the corner grip.
    func resize(to size: NSSize) {
        guard let panel, size.width.isFinite, size.height.isFinite else { return }
        let width = max(panel.minSize.width, size.width)
        let height = max(panel.minSize.height, size.height)
        let proposed = NSRect(x: panel.frame.midX - width / 2, y: panel.frame.maxY - height,
                              width: width, height: height)
        let available = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        panel.setFrame(available.map { CaptionPanelPlacement.restoredFrame(proposed, on: $0) } ?? proposed,
                       display: true)
        panel.saveFrame(usingName: captionPanelFrameName)
    }

    private func constrainToVisibleScreen() {
        guard let panel else { return }
        if panel.frame.width < panel.minSize.width || panel.frame.height < panel.minSize.height {
            resize(to: panel.frame.size)
        }
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

/// A native drag region avoids relying on hit testing in transparent SwiftUI text.
/// Place it beside controls, rather than over them, to leave buttons clickable.
struct CaptionPanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CaptionDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CaptionDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// Borderless windows have no reliable visible resize corner; keep a native grip.
struct CaptionPanelResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CaptionResizeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CaptionResizeView: NSView {
    private var originalFrame: NSRect?
    private var originalMouse = NSPoint.zero

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.7).setStroke()
        let grip = NSBezierPath()
        grip.lineWidth = 1.5
        grip.lineCapStyle = .round
        for inset in stride(from: CGFloat(0), through: 6, by: 3) {
            grip.move(to: NSPoint(x: bounds.maxX - 6 - inset, y: bounds.minY + 5))
            grip.line(to: NSPoint(x: bounds.maxX - 5, y: bounds.minY + 6 + inset))
        }
        grip.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        originalFrame = window?.frame
        originalMouse = NSEvent.mouseLocation
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let originalFrame else { return }
        let mouse = NSEvent.mouseLocation
        let width = max(window.minSize.width, originalFrame.width + mouse.x - originalMouse.x)
        let height = max(window.minSize.height, originalFrame.height - mouse.y + originalMouse.y)
        let proposed = NSRect(x: originalFrame.minX, y: originalFrame.maxY - height,
                              width: width, height: height)
        // Keep the top-left corner stable unless the new size would leave the display.
        let available = window.screen?.visibleFrame
        window.setFrame(available.map { CaptionPanelPlacement.restoredFrame(proposed, on: $0) } ?? proposed,
                        display: true)
    }
    override func mouseUp(with event: NSEvent) {
        originalFrame = nil
        window?.saveFrame(usingName: captionPanelFrameName)
    }
}
#endif
