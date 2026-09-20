//
//  NativeMenuBarLayoutPane.swift
//  Ice
//

import SwiftUI

struct NativeMenuBarLayoutPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var manager: NativeMenuBarManager
    @State private var isConfirmingExperimentalHiding = false
    @State private var searchText = ""

    private var filteredItems: [NativeMenuBarSnapshot.Item] {
        manager.items.filter { searchText.isEmpty || $0.name.localizedStandardContains(searchText) || $0.id.localizedStandardContains(searchText) }
    }

    var body: some View {
        IceForm(spacing: 16) {
            IceSection {
                Toggle("Experimental hiding", isOn: Binding(
                    get: { manager.experimentalHidingEnabled },
                    set: { enabled in
                        if enabled {
                            isConfirmingExperimentalHiding = true
                        } else {
                            manager.experimentalHidingEnabled = false
                        }
                    }
                ))
                Text("Some system icons are unavailable while hidden. Clicking the date briefly reveals icons to open Notification Center, then hides them again.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            IceSection(options: .plain) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search menu bar items", text: $searchText)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search menu bar items")
                    Button {
                        Task { await manager.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                    .disabled(manager.isRefreshing)
                }
                if let error = manager.error {
                    Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                if filteredItems.isEmpty {
                    Text(manager.isRefreshing ? "Loading..." : "No matching menu bar items.")
                        .foregroundStyle(.secondary)
                }
            }
            itemGroup("Apps", items: filteredItems.filter { !NativeMenuBarPolicy.isSystem($0.id) })
            itemGroup("System Items", items: filteredItems.filter { NativeMenuBarPolicy.isSystem($0.id) })
        }
        .confirmationDialog("Enable experimental hiding?", isPresented: $isConfirmingExperimentalHiding) {
            Button("Enable") { manager.experimentalHidingEnabled = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("macOS may hide additional system icons. Ice briefly reveals icons when opening Notification Center from the date. Show all sections or disable this option to restore normal system behavior.")
        }
        .task { await manager.refresh() }
    }

    @ViewBuilder
    private func itemGroup(_ title: LocalizedStringKey, items: [NativeMenuBarSnapshot.Item]) -> some View {
        if !items.isEmpty {
            IceSection(title) {
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: NativeMenuBarSnapshot.Item) -> some View {
        HStack(spacing: 12) {
            itemIcon(item)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).fixedSize(horizontal: false, vertical: true)
                if item.id == NativeMenuBarPolicy.systemHost {
                    Text("Shared system process; items hide together")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if NativeMenuBarPolicy.isManageable(item.id, ownBundle: Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice") {
                Picker(item.name, selection: Binding(
                    get: { manager.sections[item.id] ?? 0 },
                    set: { manager.setSection($0, for: item.id) }
                )) {
                    Text("Visible").tag(0)
                    Text("Hidden").tag(1)
                    if appState.settings.advanced.enableAlwaysHiddenSection || manager.sections[item.id] == 2 {
                        Text("Always-Hidden").tag(2)
                    }
                }
                .labelsHidden().frame(width: 150)
            } else {
                Label("System-managed", systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .trailing)
                    .help("macOS does not support independently hiding this item.")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func itemIcon(_ item: NativeMenuBarSnapshot.Item) -> some View {
        if
            !NativeMenuBarPolicy.isSystem(item.id),
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.id)
        {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: systemSymbol(for: item.id))
                .font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }

    private func systemSymbol(for id: String) -> String {
        if id == NativeMenuBarPolicy.systemHost { return "clock.arrow.circlepath" }
        switch NativeMenuBarPolicy.systemItemNumber(for: id) {
        case 0: return "battery.100percent"
        case 1: return "antenna.radiowaves.left.and.right"
        case 2: return "clock"
        case 3: return "display"
        case 4: return "keyboard"
        case 5: return "speaker.wave.2"
        case 6: return "wifi"
        case 7: return "rectangle.on.rectangle"
        case 8: return "switch.2"
        default: return "gearshape"
        }
    }
}
