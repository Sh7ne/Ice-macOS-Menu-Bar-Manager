import Foundation

@main
struct NativeMenuBarPolicyTest {
    static func main() {
        let assignments = ["visible": 0, "hidden": 1, "always": 2, "invalid": 3, "ice": 1, "com.apple.clock": 1]
        for hidden in [false, true] {
            for alwaysHidden in [false, true] {
                let excluded = NativeMenuBarPolicy.excludedBundles(
                    sections: assignments, hidden: hidden, alwaysHidden: alwaysHidden, ownBundle: "ice"
                )
                var expected = Set<String>()
                if hidden { expected.insert("hidden") }
                if alwaysHidden { expected.insert("always") }
                precondition(excluded == expected, "Invalid section policy: \(excluded)")
            }
        }
        precondition(NativeMenuBarPolicy.excludedBundles(
            sections: [:], hidden: true, alwaysHidden: true, ownBundle: "ice"
        ).isEmpty)
        let systemAssignments = [
            "com.apple.systemuiserver": 1,
            "com.apple.KerberosMenuExtra": 2,
            "com.apple.TextInputMenuAgent": 1,
            "system:com.apple.menuextra.battery": 1,
            "system:com.apple.menuextra.sound": 2,
            "system:com.apple.menuextra.clock": 1,
            "system:com.apple.menuextra.controlcenter": 2,
            "system:com.apple.menuextra.unknown": 1,
            "com.apple.MenuBarAgent": 1,
        ]
        precondition(NativeMenuBarPolicy.excludedBundles(
            sections: systemAssignments, hidden: true, alwaysHidden: false, ownBundle: "ice"
        ) == ["com.apple.systemuiserver"])
        precondition(NativeMenuBarPolicy.excludedSystemItems(
            sections: systemAssignments, hidden: true, alwaysHidden: false
        ) == [0, 4])
        precondition(NativeMenuBarPolicy.excludedSystemItems(
            sections: systemAssignments, hidden: false, alwaysHidden: true
        ) == [5])
        precondition(NativeMenuBarPolicy.excludedSystemItems(
            sections: systemAssignments, hidden: false, alwaysHidden: false
        ).isEmpty)
        precondition(!NativeMenuBarPolicy.isManageable("system:com.apple.menuextra.clock", ownBundle: "ice"))
        precondition(!NativeMenuBarPolicy.isManageable("system:com.apple.menuextra.unknown", ownBundle: "ice"))
        precondition(NativeMenuBarPolicy.isManageable("com.apple.systemuiserver", ownBundle: "ice"))
        precondition(NativeMenuBarPolicy.systemItemNumber(for: "system:com.apple.menuextra.displays") == 3)
        let displays = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: -300, width: 1920, height: 1080),
            CGRect(x: 1512, y: 100, width: 1920, height: 1080),
        ]
        for point in [CGPoint(x: 1400, y: 12), CGPoint(x: -100, y: -288), CGPoint(x: 3300, y: 112)] {
            precondition(NativeClockClickPolicy.isInMenuBar(point, displayBounds: displays, bandHeight: 24))
        }
        for point in [CGPoint(x: 1400, y: 24), CGPoint(x: -100, y: 0), CGPoint(x: 3300, y: 12)] {
            precondition(!NativeClockClickPolicy.isInMenuBar(point, displayBounds: displays, bandHeight: 24))
        }
        precondition(!NativeClockClickPolicy.isInMenuBar(.zero, displayBounds: [], bandHeight: 24))
        precondition(NativeClockClickPolicy.isClick(from: .zero, to: CGPoint(x: 2, y: 2), elapsed: 0.1))
        precondition(!NativeClockClickPolicy.isClick(from: .zero, to: CGPoint(x: 5, y: 0), elapsed: 0.1))
        precondition(!NativeClockClickPolicy.isClick(from: .zero, to: .zero, elapsed: 2))
        precondition(!NativeClockClickPolicy.isClick(from: .zero, to: .zero, elapsed: -1))
        print("NATIVE_CLOCK_POLICY_TEST_PASS: display origins, menu band, drags and long presses")
        print("NATIVE_POLICY_TEST_PASS: section states, disabled always-hidden, invalid values, protected bundles")
    }
}
