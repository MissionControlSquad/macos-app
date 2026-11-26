//
//  appApp.swift
//  AgentCenter
//
//  Created by DHARMIK JAGODANA on 10/03/26.
//  Copyright © 2026 Jagodana LLC. Licensed under the MIT License (see LICENSE).
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

// MARK: - App

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
            // Remove File > New Window (single-window app)
            CommandGroup(replacing: .newItem) { }

            // App menu: About
            CommandGroup(replacing: .appInfo) {
                Button("About AgentCenter") {
                    showAboutWindow()
                }
            }

            // Agent actions (after newItem since we replaced it)
            CommandGroup(after: .newItem) {
                Button("Add Agent...") { addAgent() }
                    .keyboardShortcut("N", modifiers: [.command, .shift])
                Divider()
                Button("Refresh") { refresh() }
                    .keyboardShortcut("R", modifiers: .command)
            }

            // Navigate menu
            CommandMenu("Navigate") {
                Section {
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
                }

                Divider()

                Section {
                    Button("Channels") { navigate(.channels) }
                        .keyboardShortcut("6", modifiers: .command)
                    Button("Tools") { navigate(.tools) }
                        .keyboardShortcut("7", modifiers: .command)
                    Button("Automation") { navigate(.automation) }
                        .keyboardShortcut("8", modifiers: .command)
                    Button("Terminal") { navigate(.terminal) }
                        .keyboardShortcut("9", modifiers: .command)
                }
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("AgentCenter Help") {
                    if let url = URL(string: "https://agentcenter.cloud") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("OpenClaw Documentation") {
                    if let url = URL(string: "https://docs.openclaw.ai") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Report an Issue...") {
                    if let url = URL(string: "https://github.com/MissionControlSquad/macos-app/issues/new/choose") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        // Settings window (Cmd+,)
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

    private func showAboutWindow() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let alert = NSAlert()
        alert.messageText = "AgentCenter"
        alert.informativeText = """
        Version \(version) (\(build))
        Mission Control for Your OpenClaw Agents

        © 2026 Jagodana LLC. Released under the MIT License.
        https://agentcenter.cloud
        """
        alert.alertStyle = .informational

        // Use app icon
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Visit Website")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://agentcenter.cloud") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Settings Scene View

struct SettingsSceneView: View {
    @State private var service = OpenClawService()
    @State private var selectedTab = "general"

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(service: service)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")

            ConnectionSettingsTab(service: service)
                .tabItem { Label("Connection", systemImage: "network") }
                .tag("connection")
        }
        .frame(width: 500, height: 400)
        .task {
            await service.refreshAll()
        }
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var service: OpenClawService

    var body: some View {
        Form {
            Section("Default Model") {
                if let model = service.modelsStatus?.defaultModel, !model.isEmpty {
                    LabeledContent("Current Model") {
                        Text(model)
                            .font(.body.monospaced())
                    }
                } else {
                    LabeledContent("Current Model") {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Agent Workspace") {
                LabeledContent("Default Path") {
                    Text("~/.openclaw/workspace")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
                    Text("\(version) (\(build))")
                }
                LabeledContent("Website") {
                    Link("agentcenter.cloud", destination: URL(string: "https://agentcenter.cloud")!)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await service.fetchModelsStatus()
        }
    }
}

private struct ConnectionSettingsTab: View {
    @Bindable var service: OpenClawService

    var body: some View {
        Form {
            Section("Gateway") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(service.gatewayStatus?.running == true ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(service.gatewayStatus?.running == true ? "Running" : "Stopped")
                    }
                }
                if let port = service.gatewayStatus?.gatewayPort {
                    LabeledContent("Port") {
                        Text("\(port)")
                            .font(.body.monospaced())
                    }
                }
                if let bindMode = service.gatewayStatus?.gateway?.bindMode {
                    LabeledContent("Bind Mode") {
                        Text(bindMode)
                    }
                }
            }

            Section("OpenClaw CLI") {
                LabeledContent("Path") {
                    Text("/opt/homebrew/bin/openclaw")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await service.fetchGatewayStatus()
        }
    }
}
