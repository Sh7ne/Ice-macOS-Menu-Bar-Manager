//
//  NativeClockAccessibility.swift
//  Ice
//

import AppKit
import ApplicationServices

/// Keep potentially slow Accessibility calls off the event-monitor/main thread.
actor NativeClockAccessibility {
    private var clock: AXUIElement?

    func prepare(at point: CGPoint) -> Bool {
        clock = nil
        let root = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, 0.2)
        var element: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &element) == .success,
            let element
        else { return false }
        AXUIElementSetMessagingTimeout(element, 0.2)
        var identifier: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier) == .success,
            identifier as? String == "com.apple.menuextra.clock"
        else { return false }
        // Resolve before the assertion drops: the menu bar reflows during reveal.
        clock = element
        return true
    }

    func press() -> Bool {
        guard let clock else { return false }
        return AXUIElementPerformAction(clock, kAXPressAction as CFString) == .success
    }

    func clear() {
        clock = nil
    }

    nonisolated static func notificationCenterIsOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            guard
                window[kCGWindowOwnerName as String] as? String == "Notification Center",
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                let height = bounds["Height"]
            else { return false }
            return height > 300
        }
    }
}
