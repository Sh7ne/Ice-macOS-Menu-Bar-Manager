//
//  NativeMenuBarManager.swift
//  Ice
//

import AppKit
import Combine
import OSLog

/// An independent, bundle-based backend; never fabricates legacy window IDs.
@MainActor
final class NativeMenuBarManager: ObservableObject {
    static var isRequired: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }
    static let sectionsKey = "NativeMenuBarSections"

    @Published private(set) var items = [NativeMenuBarSnapshot.Item]()
    @Published private(set) var sections: [String: Int] = UserDefaults.standard.dictionary(forKey: sectionsKey) as? [String: Int] ?? [:]
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false
    @Published var experimentalHidingEnabled = UserDefaults.standard.bool(forKey: "NativeMenuBarExperimentalHiding") {
        didSet {
            clockTask?.cancel()
            UserDefaults.standard.set(experimentalHidingEnabled, forKey: "NativeMenuBarExperimentalHiding")
            applyVisibility()
        }
    }

    private weak var appState: AppState?
    private let reader = NativeMenuBarSnapshot()
    private let logger = Logger(category: "NativeMenuBarManager")
    private var cancellables = Set<AnyCancellable>()
    private var assertion: AnyObject?
    private var revision = 0
    private var lastAllowed: Set<String>?
    private var lastAllowedSystemItems: Set<Int>?
    private var ready = false
    private let clockReader = NativeClockAccessibility()
    private var clockMonitor: EventMonitor?
    private var clockMouseDown: (point: CGPoint, time: TimeInterval)?
    private var clockTask: Task<Void, Never>?
    private var isRelayingClock = false

    func performSetup(with appState: AppState) {
        self.appState = appState
        Publishers.MergeMany(appState.menuBarManager.sections.map { $0.controlItem.$state })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)
        appState.settings.advanced.$enableAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak appState] _ in
                if let section = appState?.menuBarManager.section(withName: .alwaysHidden) {
                    if section.isEnabled { section.hotkey?.enable() } else { section.hotkey?.disable() }
                }
                self?.applyVisibility()
            }
            .store(in: &cancellables)
        let workspace = NSWorkspace.shared.notificationCenter
        Publishers.Merge3(
            workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification),
            workspace.publisher(for: NSWorkspace.didWakeNotification)
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.restore()
            Task { await self?.refresh() }
        }
        .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.ready = false
                self?.clockTask?.cancel()
                self?.clockMonitor?.stop()
                self?.restore()
            }
            .store(in: &cancellables)
        clockMonitor = .startGlobal(for: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleClockEvent(event)
        }
        Task { await refresh() }
    }

    func setSection(_ section: Int, for bundle: String) {
        guard NativeMenuBarPolicy.isManageable(bundle, ownBundle: Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice") else { return }
        if section == 0 {
            sections.removeValue(forKey: bundle)
        } else if section == 1 || section == 2 {
            sections[bundle] = section
        }
        UserDefaults.standard.set(sections, forKey: Self.sectionsKey)
        applyVisibility()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let snapshot = await reader.read() else {
            ready = false
            failOpen("Menu bar access is unavailable. Check Accessibility permission.")
            return
        }
        // The old divider windows no longer exist. Only infer the ordinary
        // hidden group when the saved layout and main-display Ice icon agree.
        if
            UserDefaults.standard.object(forKey: Self.sectionsKey) == nil,
            UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position Ice.ControlItem.Hidden") != nil,
            let ownItem = snapshot.items.first(where: { $0.id == Bundle.main.bundleIdentifier }),
            ownItem.frame.minY >= -5, ownItem.frame.minY < 50
        {
            sections = Dictionary(uniqueKeysWithValues: snapshot.items.compactMap { item in
                guard
                    !NativeMenuBarPolicy.isSystem(item.id), item.id != ownItem.id,
                    abs(item.frame.minY - ownItem.frame.minY) < 5,
                    item.frame.maxX <= ownItem.frame.minX
                else { return nil }
                return (item.id, 1)
            })
            UserDefaults.standard.set(sections, forKey: Self.sectionsKey)
        }
        var known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in snapshot.items { known[item.id] = item }
        // Retain hidden apps across snapshots and restarts, including apps not running.
        for bundle in sections.keys where known[bundle] == nil {
            let name = NativeMenuBarPolicy.isSystem(bundle) ? NativeMenuBarPolicy.fallbackName(for: bundle)
                : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                    .map { $0.deletingPathExtension().lastPathComponent } ?? bundle
            known[bundle] = .init(id: bundle, name: name, frame: .zero)
        }
        items = known.values.filter { $0.id != Bundle.main.bundleIdentifier }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ready = true
        applyVisibility()
    }

    private func applyVisibility() {
        guard ready, let appState else { return }
        guard !isRelayingClock else { return }
        guard experimentalHidingEnabled else {
            restore()
            error = nil
            return
        }
        let hidden = appState.menuBarManager.section(withName: .hidden)?.isHidden ?? false
        let alwaysHidden = appState.settings.advanced.enableAlwaysHiddenSection &&
            (appState.menuBarManager.section(withName: .alwaysHidden)?.isHidden ?? false)
        let excluded = NativeMenuBarPolicy.excludedBundles(
            sections: sections,
            hidden: hidden,
            alwaysHidden: alwaysHidden,
            ownBundle: Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice"
        )
        let excludedSystemItems = NativeMenuBarPolicy.excludedSystemItems(
            sections: sections, hidden: hidden, alwaysHidden: alwaysHidden
        )
        let allowedSystemItems = NativeMenuBarPolicy.allSystemItems.subtracting(excludedSystemItems)
        guard !excluded.isEmpty || !excludedSystemItems.isEmpty else {
            restore()
            error = nil
            return
        }
        guard IceNativeMenuBarAvailable() else {
            failOpen("This macOS build does not support native menu bar hiding.")
            return
        }
        let bundles = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            .union(items.map(\.id).filter { !$0.hasPrefix(NativeMenuBarPolicy.systemPrefix) })
            .union([Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice"])
        let allowed = bundles.subtracting(excluded)
        guard allowed != lastAllowed || allowedSystemItems != lastAllowedSystemItems else { return }
        restore()
        let currentRevision = revision
        lastAllowed = allowed
        lastAllowedSystemItems = allowedSystemItems
        assertion = IceActivateMenuBarAssertion(allowed.sorted(), allowedSystemItems.sorted().map { NSNumber(value: $0) }) { [weak self] failure in
            Task { @MainActor in
                guard let self, self.revision == currentRevision else { return }
                if let failure {
                    self.failOpen(failure.localizedDescription)
                } else {
                    self.error = nil
                    self.logger.info("Native hiding active for \(excluded.count) app(s), \(excludedSystemItems.count) system control(s)")
                }
            }
        } as AnyObject?
        if assertion == nil { failOpen("Unable to activate native menu bar hiding.") }
    }

    private func failOpen(_ message: String) {
        restore()
        error = message
        logger.error("\(message, privacy: .public)")
    }

    private func handleClockEvent(_ event: NSEvent) {
        guard let point = event.cgEvent?.location else { return }
        if event.type != .leftMouseUp {
            // A new click cancels delayed work, never swallows an unrelated mouse-up.
            clockTask?.cancel()
            clockMouseDown = nil
            guard
                event.type == .leftMouseDown, assertion != nil, experimentalHidingEnabled,
                event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
            else { return }
            let displays = NSScreen.screens.compactMap { screen -> CGRect? in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
                return CGDisplayBounds(id)
            }
            let bandHeight = NSScreen.screens.map { max(24, $0.safeAreaInsets.top) }.max() ?? 24
            guard
                NativeClockClickPolicy.isInMenuBar(point, displayBounds: displays, bandHeight: bandHeight),
                !NativeClockAccessibility.notificationCenterIsOpen()
            else { return }
            clockMouseDown = (point, event.timestamp)
            return
        }
        defer { clockMouseDown = nil }
        guard
            let down = clockMouseDown, clockTask == nil,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            NativeClockClickPolicy.isClick(from: down.point, to: point, elapsed: event.timestamp - down.time)
        else { return }
        let requestRevision = revision
        clockTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRelayingClock = false
                self.clockTask = nil
                self.applyVisibility()
            }
            guard
                await self.clockReader.prepare(at: point), !Task.isCancelled,
                self.revision == requestRevision, self.assertion != nil,
                self.experimentalHidingEnabled
            else { return }
            self.isRelayingClock = true
            self.restore()
            let relayRevision = self.revision
            // MenuBarAgent applies invalidation asynchronously. The user's original
            // mouse-up has already been delivered; no synthetic mouse events are needed.
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard self.revision == relayRevision else { return }
                for attempt in 1...2 {
                    guard !Task.isCancelled, self.revision == relayRevision else { return }
                    if NativeClockAccessibility.notificationCenterIsOpen() { break }
                    let pressed = await self.clockReader.press()
                    self.logger.info("Clock Accessibility action \(attempt) sent: \(pressed)")
                    try await Task.sleep(for: .milliseconds(300))
                }
                let opened = NativeClockAccessibility.notificationCenterIsOpen()
                self.logger.info("Clock relay finished; Notification Center visible: \(opened)")
            } catch { }
            await self.clockReader.clear()
        }
    }

    private func restore() {
        revision += 1
        IceInvalidateMenuBarAssertion(assertion)
        assertion = nil
        lastAllowed = nil
        lastAllowedSystemItems = nil
    }
}
