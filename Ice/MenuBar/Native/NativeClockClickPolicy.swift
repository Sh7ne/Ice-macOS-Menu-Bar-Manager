//
//  NativeClockClickPolicy.swift
//  Ice
//

import Foundation
import CoreGraphics

enum NativeClockClickPolicy {
    /// CGEvent and CGDisplayBounds both use global top-left coordinates.
    static func isInMenuBar(_ point: CGPoint, displayBounds: [CGRect], bandHeight: CGFloat) -> Bool {
        displayBounds.contains { bounds in
            bounds.contains(point) && point.y < bounds.minY + bandHeight
        }
    }

    static func isClick(from down: CGPoint, to up: CGPoint, elapsed: TimeInterval) -> Bool {
        elapsed >= 0 && elapsed <= 1 && hypot(up.x - down.x, up.y - down.y) <= 4
    }
}
