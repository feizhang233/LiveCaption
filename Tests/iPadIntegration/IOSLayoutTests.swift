import SwiftUI
import UIKit
import XCTest
@testable import LiveCaption

/// Native render checks use an empty, private model directory and never begin
/// recognition, download a model, or change the user's saved preferences.
final class IOSLayoutTests: XCTestCase {
    @MainActor
    func testCompactPortraitShowsAllFourDestinations() async throws {
        try await withRoot(size: CGSize(width: 320, height: 568), horizontalSizeClass: .compact) { host in
            let tabs = try XCTUnwrap(Self.descendant(UITabBarController.self, in: host),
                                    "Compact navigation must expose native tabs")
            self.assertCompactTabs(tabs)
            self.attach(host, name: "iphone-320-portrait-live")

            for (index, name) in [(2, "models"), (3, "settings")] {
                let previous = tabs.selectedTab
                let selected = tabs.tabs[index]
                tabs.selectedTab = selected
                tabs.delegate?.tabBarController?(tabs, didSelectTab: selected, previousTab: previous)
                try await Task.sleep(for: .milliseconds(700))
                host.view.layoutIfNeeded()
                let destination = try XCTUnwrap(selected.viewController)
                XCTAssertTrue(tabs.selectedTab === selected)
                XCTAssertTrue(destination.isViewLoaded, "Selected destination must be rendered")
                XCTAssertTrue(destination.view.window === host.view.window,
                              "Selected destination must be attached to the rendered window")
                self.attach(host, name: "iphone-320-portrait-\(name)")
            }
        }
    }

    @MainActor
    func testCompactLandscapeKeepsTabNavigation() async throws {
        try await withRoot(size: CGSize(width: 852, height: 393), horizontalSizeClass: .compact) { host in
            let tabs = try XCTUnwrap(Self.descendant(UITabBarController.self, in: host))
            self.assertCompactTabs(tabs)
            self.attach(host, name: "iphone-landscape-live")
        }
    }

    @MainActor
    func testAccessibilityTypeKeepsCompactNavigation() async throws {
        try await withRoot(size: CGSize(width: 320, height: 568), horizontalSizeClass: .compact,
                           dynamicTypeSize: .accessibility3) { host in
            let tabs = try XCTUnwrap(Self.descendant(UITabBarController.self, in: host))
            self.assertCompactTabs(tabs)
            self.attach(host, name: "iphone-320-accessibility3-live")
            let scroll = try XCTUnwrap(Self.scrollViews(in: host.view).first {
                $0.contentSize.height > $0.bounds.height
            }, "Large text must remain vertically scrollable")
            // Collapsing the native large title changes the scroll insets. Use
            // the settled visible content bounds rather than an earlier offset.
            for _ in 0..<3 {
                let bottom = max(-scroll.adjustedContentInset.top,
                                 scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: bottom), animated: false)
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
            }
            let visibleBottom = scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom
            XCTAssertGreaterThan(scroll.contentOffset.y, 0)
            XCTAssertGreaterThanOrEqual(visibleBottom + 1, scroll.contentSize.height,
                                       "The end of the large-text content must be reachable")
            self.attach(host, name: "iphone-320-accessibility3-bottom")
        }
    }

    @MainActor
    func testRegularIPadUsesSplitNavigation() async throws {
        try await withRoot(size: CGSize(width: 1024, height: 768), horizontalSizeClass: .regular) { host in
            XCTAssertNotNil(Self.descendant(UISplitViewController.self, in: host),
                            "Regular layouts must retain the native sidebar")
            XCTAssertNil(Self.descendant(UITabBarController.self, in: host),
                         "Regular iPad navigation must not duplicate compact tabs")
            self.attach(host, name: "ipad-regular-live")
        }
    }

    @MainActor
    private func withRoot(size: CGSize, horizontalSizeClass: UserInterfaceSizeClass,
                          dynamicTypeSize: DynamicTypeSize = .large,
                          run: (UIViewController) async throws -> Void) async throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("LiveCaption-Layout-\(UUID().uuidString)", isDirectory: true)
        let suite = "LiveCaption.LayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let models = ModelStore(storageURL: directory, defaults: defaults)
        let session = SessionController(models: models, defaults: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let root = RootView(session: session)
            .environment(\.horizontalSizeClass, horizontalSizeClass)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        let host = UIHostingController(rootView: root)
        host.traitOverrides.horizontalSizeClass = horizontalSizeClass == .compact ? .compact : .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
            defaults.removePersistentDomain(forName: suite)
            try? files.removeItem(at: directory)
        }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.width, size.width, accuracy: 1)
        XCTAssertEqual(host.view.bounds.height, size.height, accuracy: 1)
        try await run(host)
        await session.stop()
    }

    @MainActor
    private func assertCompactTabs(_ controller: UITabBarController,
                                   file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI's modern Tab API uses UITabBarController.tabs. UIKit explicitly
        // leaves viewControllers unset once this API owns the destinations.
        XCTAssertEqual(controller.tabs.count, 4, file: file, line: line)
        XCTAssertEqual(controller.tabs.map(\.title), ["即時字幕", "媒體播放", "模型管理", "設定"],
                       file: file, line: line)
        XCTAssertEqual(controller.tabBar.items?.count, 4, file: file, line: line)
        XCTAssertTrue(controller.tabs.allSatisfy { $0.isEnabled && !$0.isHidden }, file: file, line: line)
        XCTAssertFalse(controller.tabBar.isHidden, file: file, line: line)
    }

    @MainActor
    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    @MainActor
    private static func descendant<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let match = controller as? T { return match }
        for child in controller.children {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }

    @MainActor
    private func attach(_ host: UIViewController, name: String) {
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
