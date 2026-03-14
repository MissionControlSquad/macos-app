//
//  appApp.swift
//  app
//
//  Created by DHARMIK JAGODANA on 10/03/26.
//

import SwiftUI

// MARK: - Focused Values for Menu Commands

struct NavigateAction {
    let navigate: (SidebarItem) -> Void
}

struct RefreshAction {
    let refresh: () -> Void
}

struct AddAgentAction {
    let addAgent: () -> Void
}

struct FocusedNavigateKey: FocusedValueKey {
    typealias Value = NavigateAction
}

struct FocusedRefreshKey: FocusedValueKey {
    typealias Value = RefreshAction
}

struct FocusedAddAgentKey: FocusedValueKey {
    typealias Value = AddAgentAction
}

extension FocusedValues {
    var navigate: NavigateAction? {
        get { self[FocusedNavigateKey.self] }
        set { self[FocusedNavigateKey.self] = newValue }
    }
    var refresh: RefreshAction? {
        get { self[FocusedRefreshKey.self] }
        set { self[FocusedRefreshKey.self] = newValue }
    }
    var addAgent: AddAgentAction? {
        get { self[FocusedAddAgentKey.self] }
        set { self[FocusedAddAgentKey.self] = newValue }
    }
}

@main
struct AgentCenterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
                .task {
                    ModelCatalogStore.shared.loadAndRefresh()
                }
        }
        .defaultSize(width: 1100, height: 700)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified)
        .commands {
            // Remove File > New Window since this is a single-window app
            CommandGroup(replacing: .newItem) { }

            // Navigation menu
            CommandMenu("Navigate") {
                Button("Agents") { navigate(.agents) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Sessions") { navigate(.sessions) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Logs") { navigate(.logs) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Gateway") { navigate(.gateway) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Models") { navigate(.models) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Settings") { navigate(.settings) }
                    .keyboardShortcut("6", modifiers: .command)
            }

            // Agent actions
            CommandGroup(after: .newItem) {
                Button("Add Agent...") { addAgent() }
                    .keyboardShortcut("N", modifiers: [.command, .shift])
                Divider()
                Button("Refresh") { refresh() }
                    .keyboardShortcut("R", modifiers: .command)
            }
        }

        Settings {
            SettingsSceneView()
        }
    }

    @FocusedValue(\.navigate) private var navigateAction
    @FocusedValue(\.refresh) private var refreshAction
    @FocusedValue(\.addAgent) private var addAgentAction

    private func navigate(_ item: SidebarItem) {
        navigateAction?.navigate(item)
    }

    private func refresh() {
        refreshAction?.refresh()
    }

    private func addAgent() {
        addAgentAction?.addAgent()
    }
}

/// Standalone settings wrapper for the macOS Cmd+, Settings scene.
struct SettingsSceneView: View {
    @State private var service = OpenClawService()
    @State private var gateway = GatewayWebSocket()

    var body: some View {
        SettingsView(service: service, gateway: gateway)
            .frame(minWidth: 700, minHeight: 500)
            .task {
                gateway.connect()
                await service.refreshAll()
            }
    }
}
