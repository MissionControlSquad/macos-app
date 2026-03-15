import SwiftUI

// MARK: - Shared Two-Step Model Picker

/// Two-step picker: first choose a provider, then choose a model from that provider.
/// Reads from the global `ModelCatalogStore.shared`.
struct ModelCatalogPicker: View {
    @Binding var selection: String
    var placeholder: String = "Choose a model..."

    @State private var selectedProvider = ""
    private var store: ModelCatalogStore { .shared }

    private var providerModels: [CatalogModel] {
        guard !selectedProvider.isEmpty else { return [] }
        return store.models(for: selectedProvider)
    }

    var body: some View {
        HStack(spacing: 6) {
            Picker("Provider", selection: $selectedProvider) {
                Text("Select provider...").tag("")
                ForEach(store.providers, id: \.self) { provider in
                    Text(provider.capitalized).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 170)
            .onChange(of: selectedProvider) {
                if !selection.isEmpty && !selection.hasPrefix(selectedProvider + "/") {
                    selection = ""
                }
            }

            Picker("Model", selection: $selection) {
                Text(selectedProvider.isEmpty ? "Choose provider first" : placeholder).tag("")
                ForEach(providerModels) { model in
                    Text(model.displayLabel).tag(model.modelKey)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 280)
            .disabled(selectedProvider.isEmpty || providerModels.isEmpty)

        }
        .onAppear {
            syncProviderFromSelection()
        }
        .onChange(of: selection) {
            syncProviderFromSelection()
        }
    }

    private func syncProviderFromSelection() {
        guard !selection.isEmpty else { return }
        let parts = selection.components(separatedBy: "/")
        if let first = parts.first, store.providers.contains(first) {
            selectedProvider = first
        }
    }
}

struct ProviderSelectionPicker: View {
    @Binding var selection: String
    var title: String = "Provider"

    private var allProviders: [String] {
        var seen = Set<String>()
        let merged = ModelCatalogStore.shared.providers + (selection.isEmpty ? [] : [selection])
        return merged.filter { seen.insert($0).inserted }.sorted()
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Select provider...").tag("")
            ForEach(allProviders, id: \.self) { provider in
                Text(provider.capitalized).tag(provider)
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 180)
    }
}

/// Reusable sheet for choosing a model (provider → model two-step picker).
/// Use with `.sheet` and provide context-specific title, description, and action.
struct ModelChooserSheet: View {
    var title: String = "Choose Model"
    var description: String = "Select a provider and model."
    var actionLabel: String = "Apply"
    var initialSelection: String = ""
    var onApply: (String) async -> Bool  // returns true on success
    var onDismiss: () -> Void

    @State private var selection: String = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title3.bold())

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ModelCatalogPicker(selection: $selection)

            if !selection.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(selection)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.bordered)

                Button(isSaving ? "Saving..." : actionLabel) {
                    Task {
                        isSaving = true
                        let success = await onApply(selection)
                        isSaving = false
                        if success { onDismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            selection = initialSelection
        }
    }
}

/// Reusable sheet for configuring an API key (provider picker + secure field).
/// Use with `.sheet` for both global and per-agent API key configuration.
struct APIKeySheet: View {
    var title: String = "Configure API Key"
    var description: String = "Select a provider and enter your API key."
    var initialProvider: String = ""
    var onSave: (String, String) async -> Bool  // (provider, apiKey) -> success
    var onValidate: ((String) async -> ProviderStatus?)? = nil  // (provider) -> status (legacy CLI check)
    var onValidateKey: ((String, String) async -> OpenClawService.APIKeyValidation)? = nil  // (provider, apiKey) -> real API check
    var onDismiss: () -> Void

    enum ValidationState: Equatable {
        case idle
        case saving
        case validating
        case valid
        case invalid(String)
    }

    @State private var provider: String = ""
    @State private var apiKey: String = ""
    @State private var validation: ValidationState = .idle

    private var isBusy: Bool {
        validation == .saving || validation == .validating
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title3.bold())

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Provider") {
                    ProviderSelectionPicker(selection: $provider)
                }

                LabeledContent("API Key") {
                    SecureField("Paste your API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Validation result
            switch validation {
            case .saving:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Saving key…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .validating:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Validating key…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .valid:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("API key is valid")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            case .invalid(let reason):
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            case .idle:
                EmptyView()
            }

            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.bordered)

                if validation == .valid {
                    Button("Done") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                } else {
                    Button("Save & Validate") {
                        Task {
                            // Step 1: Validate the key with a real API call first
                            if let onValidateKey {
                                validation = .validating
                                let result = await onValidateKey(provider, apiKey)
                                if !result.isValid {
                                    validation = .invalid(result.error ?? "API key is invalid")
                                    return
                                }
                            }

                            // Step 2: Key is valid (or no real validation available) — save it
                            validation = .saving
                            let success = await onSave(provider, apiKey)
                            if success {
                                validation = .valid
                            } else {
                                validation = .invalid("Failed to save the API key. Check the key format and try again.")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(provider.isEmpty || apiKey.isEmpty || isBusy)
                }
            }
        }
        .padding(24)
        .frame(width: 450)
        .onAppear {
            provider = initialProvider
        }
        .onChange(of: provider) {
            if validation != .idle { validation = .idle }
        }
        .onChange(of: apiKey) {
            if validation != .idle { validation = .idle }
        }
    }
}

enum SidebarItem: String, Identifiable, CaseIterable {
    // Main
    case agents = "Agents"
    case sessions = "Sessions"
    case logs = "Logs"
    case gateway = "Gateway"
    case models = "Models"
    // Advanced
    case channels = "Channels"
    case memory = "Memory"
    case skillsPlugins = "Skills & Plugins"
    case tools = "Tools"
    case automation = "Automation"
    case hooks = "Hooks"
    case approvals = "Approvals"
    case devices = "Devices"
    case usageCost = "Usage & Cost"
    case terminal = "Terminal"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agents: return "person.3.fill"
        case .sessions: return "bubble.left.and.bubble.right.fill"
        case .logs: return "doc.text.magnifyingglass"
        case .gateway: return "server.rack"
        case .models: return "cpu"
        case .channels: return "message.fill"
        case .memory: return "brain"
        case .skillsPlugins: return "puzzlepiece.extension"
        case .tools: return "wrench.and.screwdriver"
        case .automation: return "clock.arrow.2.circlepath"
        case .hooks: return "link"
        case .approvals: return "checkmark.shield"
        case .devices: return "desktopcomputer"
        case .usageCost: return "chart.bar"
        case .terminal: return "terminal"
        }
    }

    enum Group: String, CaseIterable {
        case main
        case advanced = "Advanced"
    }

    var group: Group {
        switch self {
        case .agents, .sessions, .logs, .gateway, .models:
            return .main
        default:
            return .advanced
        }
    }

    static func items(in group: Group) -> [SidebarItem] {
        allCases.filter { $0.group == group }
    }
}

struct DashboardView: View {
    @State private var service = OpenClawService()
    @State private var gateway = GatewayWebSocket()
    // Selection uses a simple string: nav item rawValue or "agent:<id>"
    @State private var selection: String? = SidebarItem.agents.rawValue
    @State private var showAddAgent = false
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var openSessionId: String?

    // Confirmation dialogs
    @State private var agentToDelete: Agent?
    @State private var showDeleteConfirm = false
    @State private var showStopGatewayConfirm = false
    @State private var showUninstallGatewayConfirm = false

    // Action feedback
    @State private var toast = ToastState()

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
                .navigationTitle("AgentCenter")
        } detail: {
            detailView
        }
        .toastOverlay(toast)
        .onChange(of: selection) {
            // Clear stale session ID when switching away from an agent
            openSessionId = nil
        }
        .task {
            // Wire gateway into service and model catalog for WebSocket-first operations
            service.gateway = gateway
            ModelCatalogStore.shared.gateway = gateway
            gateway.connect()
            await service.refreshAll()
            startAutoRefresh()
        }
        .onDisappear {
            autoRefreshTask?.cancel()
        }
        .sheet(isPresented: $showAddAgent) {
            addAgentSheet
        }
        .confirmationDialog(
            "Delete Agent",
            isPresented: $showDeleteConfirm,
            presenting: agentToDelete
        ) { agent in
            Button("Delete \"\(agent.displayName ?? agent.name)\"", role: .destructive) {
                Task {
                    let agentName = agent.displayName ?? agent.name
                    let result = await service.deleteAgent(name: agent.name)
                    if result.exitCode == 0 {
                        toast.show("Agent \"\(agentName)\" deleted")
                    } else {
                        toast.show("Failed to delete agent: \(result.output)", isError: true)
                    }
                    // Navigate away if viewing the deleted agent
                    if selection == "agent:\(agent.id)" {
                        selection = SidebarItem.agents.rawValue
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { agent in
            Text("This will unbind all channel routes, remove the agent registry entry, and trash its workspace and session data. This cannot be undone.")
        }
        .confirmationDialog(
            "Stop Gateway",
            isPresented: $showStopGatewayConfirm
        ) {
            Button("Stop Gateway", role: .destructive) {
                runGatewayAction(label: "Stop Gateway") { await service.stopGateway() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stopping the gateway will disconnect all active agent sessions and channels. Are you sure?")
        }
        .confirmationDialog(
            "Uninstall Gateway Service",
            isPresented: $showUninstallGatewayConfirm
        ) {
            Button("Uninstall", role: .destructive) {
                runGatewayAction(label: "Uninstall Gateway") { await service.runCommand("openclaw gateway uninstall") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the gateway background service. You can reinstall it later. Are you sure?")
        }
        // Menu bar command bindings
        .focusedSceneValue(\.navigate, NavigateAction { item in
            selection = item.rawValue
        })
        .focusedSceneValue(\.refresh, RefreshAction {
            Task { await service.refreshAll() }
        })
        .focusedSceneValue(\.addAgent, AddAgentAction {
            showAddAgent = true
        })
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled {
                    await service.refreshAll()
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.items(in: .main)) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item.rawValue)
                        .badge(badgeCount(for: item))
                }
            }

            if !service.agents.isEmpty {
                Section("Agents · \(service.agents.count)") {
                    ForEach(service.agents) { agent in
                        HStack(spacing: 8) {
                            if let emoji = agent.emoji, !emoji.isEmpty {
                                Text(emoji)
                                    .accessibilityHidden(true)
                            } else {
                                Circle()
                                    .fill(agentColor(agent.agentStatus))
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)
                            }
                            Text(agent.displayName ?? agent.name)
                                .lineLimit(1)
                        }
                        .tag("agent:\(agent.id)")
                        .accessibilityLabel("\(agent.displayName ?? agent.name), \(agent.agentStatus.label)")
                        .contextMenu {
                            Button("Delete Agent", role: .destructive) {
                                agentToDelete = agent
                                showDeleteConfirm = true
                            }
                        }
                    }
                }
            }



            Section("Advanced") {
                ForEach(SidebarItem.items(in: .advanced)) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item.rawValue)
                        .badge(badgeCount(for: item))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Circle()
                    .fill(gateway.isConnected ? Color.green : service.gatewayStatus?.running == true ? Color.yellow : Color.red)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(gateway.isConnected ? "Connected" : service.gatewayStatus?.running == true ? "Running" : "Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Gateway status: \(gateway.isConnected ? "Connected" : service.gatewayStatus?.running == true ? "Running" : "Offline")")
        }
    }

    private func badgeCount(for item: SidebarItem) -> Int {
        switch item {
        case .gateway, .approvals:
            return gateway.pendingApprovals.count
        default:
            return 0
        }
    }

    // MARK: - Detail

    /// Resolve the selected agent from the string-based selection tag.
    private var selectedAgent: Agent? {
        guard let selection, selection.hasPrefix("agent:") else { return nil }
        let agentId = String(selection.dropFirst("agent:".count))
        return service.agents.first { $0.id == agentId }
    }

    @ViewBuilder
    private var detailView: some View {
        if let agent = selectedAgent {
            AgentDetailView(agent: agent, service: service, initialSessionId: openSessionId, onDeleted: {
                selection = SidebarItem.agents.rawValue
            })
            .id(agent.id)
        } else {
            switch selection {
            case SidebarItem.sessions.rawValue:
                SessionsListView(service: service) { agent, sessionId in
                    openSessionId = sessionId
                    selection = "agent:\(agent.id)"
                }
            case SidebarItem.logs.rawValue:
                LogsView(service: service)
            case SidebarItem.gateway.rawValue:
                gatewayView
            case SidebarItem.models.rawValue:
                modelsView
            // Advanced
            case SidebarItem.channels.rawValue:
                ChannelsView(service: service)
            case SidebarItem.memory.rawValue:
                MemoryView(service: service)
            case SidebarItem.skillsPlugins.rawValue:
                SkillsPluginsView(service: service)
            case SidebarItem.tools.rawValue:
                ToolsCatalogView(gateway: gateway)
            case SidebarItem.automation.rawValue:
                CronView(service: service, gateway: gateway)
            case SidebarItem.hooks.rawValue:
                HooksView(service: service)
            case SidebarItem.approvals.rawValue:
                ApprovalsView(gateway: gateway)
            case SidebarItem.devices.rawValue:
                DevicesView(gateway: gateway)
            case SidebarItem.usageCost.rawValue:
                UsageCostView(gateway: gateway, service: service)
            case SidebarItem.terminal.rawValue:
                TerminalView(service: service)
            default:
                agentsView
            }
        }
    }

    // MARK: - Agents View

    private var agentsView: some View {
        Group {
            if service.isLoading && service.agents.isEmpty {
                LoadingStateView(message: "Loading agents...")
            } else if service.agents.isEmpty {
                EmptyStateView(
                    icon: "person.3",
                    title: "No Agents",
                    message: "Create your first agent to get started.",
                    actionLabel: "Add Agent",
                    action: { showAddAgent = true }
                )
            } else {
                List {
                    ForEach(service.agents) { agent in
                        agentRow(agent)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = "agent:\(agent.id)"
                            }
                    }
                }
            }
        }
        .navigationTitle("Agents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddAgent = true
                } label: {
                    Label("Add Agent", systemImage: "plus")
                }
                .help("Add a new agent")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await service.fetchAgents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh agents")
            }
        }
    }

    private func agentRow(_ agent: Agent) -> some View {
        HStack(spacing: 12) {
            // Emoji or status icon
            Group {
                if let emoji = agent.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.title)
                } else {
                    Image(systemName: agent.agentStatus.icon)
                        .font(.title2)
                        .foregroundStyle(agentColor(agent.agentStatus))
                }
            }
            .frame(width: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.displayName ?? agent.name)
                        .font(.headline)
                    if agent.displayName != nil {
                        Text("(\(agent.name))")
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                Text(agent.workspace)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if let count = agent.bindingsCount, count > 0 {
                        StatusBadge(label: "\(count) binding\(count == 1 ? "" : "s")", color: Color.accentColor)
                    }
                    if agent.isDefault == true {
                        StatusBadge(label: "Default", color: Color.green)
                    }
                }
            }

            Spacer()

            Text(agent.agentStatus.label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(agentColor(agent.agentStatus).opacity(0.15))
                .foregroundStyle(agentColor(agent.agentStatus))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Show Details") {
                selection = "agent:\(agent.id)"
            }
            Button("Copy Agent Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(agent.name, forType: .string)
            }
            Divider()
            Button("Delete Agent", role: .destructive) {
                agentToDelete = agent
                showDeleteConfirm = true
            }
        }
    }

    // MARK: - Gateway View

    @State private var gatewayIsActing = false
    @State private var configKey = ""
    @State private var configValue = ""
    @State private var configOutput = ""
    @State private var configToast = ToastState()
    @State private var doctorOutput = ""

    private var gatewayView: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status
                    GroupBox {
                        HStack(spacing: 12) {
                            Image(systemName: service.gatewayStatus?.running == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(service.gatewayStatus?.running == true ? Color.green : Color.red)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.gatewayStatus?.running == true ? "Gateway is Running" : "Gateway is Stopped")
                                    .font(.title2.bold())
                                if let port = service.gatewayStatus?.gatewayPort {
                                    Text("Port: \(port)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                if let bindMode = service.gatewayStatus?.gateway?.bindMode {
                                    Text("Bind: \(bindMode)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                if let pid = service.gatewayStatus?.pid {
                                    Text("PID: \(pid)")
                                        .font(.caption)
                                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                }
                            }

                            Spacer()
                        }
                    } label: {
                        SectionHeader("Status")
                    }

                    // Controls
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                if service.gatewayStatus?.running == true {
                                    Button {
                                        showStopGatewayConfirm = true
                                    } label: {
                                        Label("Stop", systemImage: "stop.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(gatewayIsActing)

                                    Button {
                                        runGatewayAction(label: "Restart Gateway") { await service.restartGateway() }
                                    } label: {
                                        Label("Restart", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(gatewayIsActing)
                                } else {
                                    Button {
                                        runGatewayAction(label: "Start Gateway") { await service.startGateway() }
                                    } label: {
                                        Label(gatewayIsActing ? "Starting..." : "Start Gateway", systemImage: "play.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(gatewayIsActing)
                                }

                                Button {
                                    runGatewayAction(label: "Health Check") { await service.gatewayHealth() }
                                } label: {
                                    Label("Health Check", systemImage: "heart.text.square")
                                }
                                .buttonStyle(.bordered)
                                .disabled(gatewayIsActing)
                            }

                            // Advanced service management
                            DisclosureGroup("Advanced") {
                                HStack(spacing: 12) {
                                    Button {
                                        runGatewayAction(label: "Reinstall Service") { await service.installGateway() }
                                    } label: {
                                        Label("Reinstall Service", systemImage: "square.and.arrow.down")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button {
                                        showUninstallGatewayConfirm = true
                                    } label: {
                                        Label("Uninstall Service", systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.top, 4)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } label: {
                        SectionHeader("Controls", description: "Manage the gateway service")
                    }

                    // Operation log
                    if !service.gatewayLog.isEmpty {
                        GroupBox {
                            ScrollView {
                                Text(service.gatewayLog)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                        } label: {
                            HStack(spacing: 6) {
                                SectionHeader("Operation Log")
                                if gatewayIsActing {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Running…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    service.gatewayLog = ""
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Dashboard link
                    if service.gatewayStatus?.running == true {
                        let port = service.gatewayStatus?.gatewayPort ?? 18789
                        GroupBox {
                            HStack {
                                Image(systemName: "globe")
                                Text("http://127.0.0.1:\(port)/")
                                    .font(.callout.monospaced())
                                Spacer()
                                Button("Open in Browser") {
                                    if let url = URL(string: "http://127.0.0.1:\(port)/") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        } label: {
                            SectionHeader("Dashboard", description: "Web-based gateway interface")
                        }
                    }

                    // Configuration
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                TextField("e.g. gateway.mode", text: $configKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))

                                TextField("Leave empty to read", text: $configValue)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))

                                Button("Get") {
                                    Task {
                                        let r = await service.configGet(configKey)
                                        configOutput = r.output
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(configKey.isEmpty)

                                Button("Set") {
                                    Task {
                                        let r = await service.configSet(configKey, value: configValue)
                                        configToast.show(r.exitCode == 0 ? "\(configKey) updated" : r.output, isError: r.exitCode != 0)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(configKey.isEmpty || configValue.isEmpty)
                            }

                            HStack(spacing: 6) {
                                Text("Common keys:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach([
                                    "gateway.mode",
                                    "gateway.port",
                                    "agents.defaults.model.primary",
                                    "session.dmScope",
                                ], id: \.self) { key in
                                    Button(key) { configKey = key }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                }
                            }

                            if !configOutput.isEmpty {
                                Text(configOutput)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    } label: {
                        SectionHeader("Configuration", description: "Read and write config values using dot-path notation")
                    }

                    // Diagnostics
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Button {
                                    Task {
                                        let r = await service.runDoctor()
                                        doctorOutput = r.output
                                    }
                                } label: {
                                    Label("Run Doctor", systemImage: "stethoscope")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    Task {
                                        let r = await service.configValidate()
                                        doctorOutput = r.output
                                    }
                                } label: {
                                    Label("Validate Config", systemImage: "checkmark.shield")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    Task {
                                        let r = await service.runCommand("openclaw doctor --repair")
                                        doctorOutput = r.output
                                    }
                                } label: {
                                    Label("Auto-Fix", systemImage: "wrench.and.screwdriver")
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button("Open Config File") {
                                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                                    let url = URL(fileURLWithPath: "\(home)/.openclaw/openclaw.json")
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .buttonStyle(.bordered)
                            }

                            if !doctorOutput.isEmpty {
                                ScrollView {
                                    Text(doctorOutput)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 300)
                            }
                        }
                    } label: {
                        SectionHeader("Diagnostics", description: "Health checks and troubleshooting")
                    }

                    ToastBanner(toast: configToast)
                }
                .padding()
        }
        .navigationTitle("Gateway")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if gatewayIsActing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await service.fetchGatewayStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh gateway status")
                }
            }
        }
    }

    private func runGatewayAction(label: String = "Action", _ action: @escaping () async -> CommandResult) {
        Task {
            gatewayIsActing = true
            let result = await action()
            gatewayIsActing = false
            toast.show(result.exitCode == 0 ? "\(label) completed successfully" : "\(label) failed: \(String(result.output.prefix(100)))", isError: result.exitCode != 0)
        }
    }

    // MARK: - Models View

    @State private var modelsToast = ToastState()
    @State private var showChangeModelSheet = false
    @State private var showConfigureAPISheet = false
    @State private var showAddFallbackSheet = false
    @State private var configProviderName = ""
    @State private var fallbackModels: [String] = []
    @State private var fallbacksLoaded = false
    @State private var isSavingFallbackOrder = false
    @State private var validatingProvider = ""
    @State private var removingProvider: String?
    @State private var providerValidationResults: [String: Bool] = [:]  // provider -> isValid

    private var hasDefaultModel: Bool {
        guard let m = service.modelsStatus?.defaultModel, !m.isEmpty else { return false }
        return true
    }

    private var modelsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Default Model
                GroupBox {
                    if hasDefaultModel {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .font(.title2)
                                .foregroundStyle(.accent)

                            Text(service.modelsStatus?.defaultModel ?? "")
                                .font(.headline.monospaced())

                            Spacer()

                            Button("Change") {
                                showChangeModelSheet = true
                            }
                            .buttonStyle(.bordered)
                        }

                        // Fallback count hint
                        if !fallbackModels.isEmpty {
                            Divider()
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)

                                Text("\(fallbackModels.count) fallback\(fallbackModels.count == 1 ? "" : "s") configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()
                            }
                        }
                    } else {
                        // No default model — prominent CTA
                        VStack(spacing: 12) {
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)

                            Text("No Default Model")
                                .font(.headline)

                            Text("Choose a model to start using your agents. You can change it anytime.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Set Default Model") {
                                showChangeModelSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } label: {
                    SectionHeader("Default Model")
                }

                // Fallback Models
                GroupBox {
                    if !fallbacksLoaded {
                        // Loading state
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading fallback models…")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else if fallbackModels.isEmpty {
                        // Empty state
                        VStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No fallback models")
                                .font(.headline)
                            Text("When the primary model fails or hits rate limits, fallback models are tried in order.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Add Fallback Model") {
                                showAddFallbackSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else {
                        // Fallback list with reorder
                        VStack(spacing: 0) {
                            ForEach(Array(fallbackModels.enumerated()), id: \.offset) { index, model in
                                HStack(spacing: 8) {
                                    // Reorder controls
                                    VStack(spacing: 0) {
                                        Button {
                                            moveFallback(from: index, direction: .up)
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.caption2.weight(.semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(index == 0 || isSavingFallbackOrder)
                                        .foregroundStyle(index == 0 ? .quaternary : .secondary)

                                        Button {
                                            moveFallback(from: index, direction: .down)
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.caption2.weight(.semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(index == fallbackModels.count - 1 || isSavingFallbackOrder)
                                        .foregroundStyle(index == fallbackModels.count - 1 ? .quaternary : .secondary)
                                    }
                                    .frame(width: 16)

                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    Text(model)
                                        .font(.body.monospaced())

                                    Spacer()

                                    Button {
                                        Task {
                                            let r = await service.removeFallback(model: model)
                                            modelsToast.show(r.exitCode == 0 ? "Removed \(model)" : r.output, isError: r.exitCode != 0)
                                            await refreshFallbacks()
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove fallback")
                                }
                                .padding(.vertical, 5)
                                if index < fallbackModels.count - 1 {
                                    Divider()
                                        .padding(.leading, 42)
                                }
                            }
                        }

                        HStack {
                            Spacer()
                            Button {
                                showAddFallbackSheet = true
                            } label: {
                                Label("Add Fallback", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Clear All") {
                                Task {
                                    let r = await service.runCommand("openclaw models fallbacks clear")
                                    modelsToast.show(r.exitCode == 0 ? "All fallbacks cleared" : r.output, isError: r.exitCode != 0)
                                    await refreshFallbacks()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 6)
                    }
                } label: {
                    HStack(spacing: 6) {
                        SectionHeader(
                            "Fallback Models",
                            count: fallbackModels.isEmpty ? nil : fallbackModels.count,
                            description: isSavingFallbackOrder ? nil : "Tried in order when the primary model fails"
                        )
                        if isSavingFallbackOrder {
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Providers
                GroupBox {
                    if let providers = service.modelsStatus?.providers, !providers.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                                providerRow(provider)
                                if index < providers.count - 1 {
                                    Divider()
                                }
                            }
                        }

                        HStack {
                            Spacer()
                            Button {
                                configProviderName = ""
                                showConfigureAPISheet = true
                            } label: {
                                Label("Add API Key", systemImage: "key")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 6)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "network.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No providers configured")
                                .font(.headline)
                            Text("Add an API key to connect to a model provider like OpenAI, Anthropic, or Google.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                configProviderName = ""
                                showConfigureAPISheet = true
                            } label: {
                                Label("Add API Key", systemImage: "key")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } label: {
                    SectionHeader(
                        "Providers",
                        count: service.modelsStatus?.providers.isEmpty == false ? service.modelsStatus?.providers.count : nil,
                        description: "API keys and provider authentication"
                    )
                }

                ToastBanner(toast: modelsToast)
            }
            .padding()
        }
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await service.fetchModelsStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh models status")
            }
        }
        .sheet(isPresented: $showChangeModelSheet) {
            ModelChooserSheet(
                title: hasDefaultModel ? "Change Default Model" : "Set Default Model",
                description: "Select a provider and model to use as the default for all agents.",
                actionLabel: "Set Default",
                initialSelection: hasDefaultModel ? (service.modelsStatus?.defaultModel ?? "") : "",
                onApply: { model in
                    let result = await service.setDefaultModel(model)
                    if result.exitCode == 0 {
                        modelsToast.show("Default model set to \(model)")
                    } else {
                        modelsToast.show(result.output, isError: true)
                    }
                    return result.exitCode == 0
                },
                onDismiss: { showChangeModelSheet = false }
            )
        }
        .sheet(isPresented: $showConfigureAPISheet) {
            APIKeySheet(
                title: "Configure API Key",
                description: "Enter your API key to authenticate with a provider. Keys are stored locally by OpenClaw.",
                initialProvider: configProviderName,
                onSave: { provider, apiKey in
                    let result = await service.configureProvider(provider: provider, apiKey: apiKey)
                    if result.exitCode == 0 {
                        modelsToast.show("\(provider.capitalized) API key configured")
                    } else {
                        modelsToast.show(result.output, isError: true)
                    }
                    return result.exitCode == 0
                },
                onValidateKey: { provider, apiKey in
                    await OpenClawService.validateAPIKey(provider: provider, apiKey: apiKey)
                },
                onDismiss: { showConfigureAPISheet = false }
            )
        }
        .sheet(isPresented: $showAddFallbackSheet) {
            ModelChooserSheet(
                title: "Add Fallback Model",
                description: "Choose a model to add to the fallback chain. Fallbacks are tried in order when the primary model fails.",
                actionLabel: "Add Fallback",
                onApply: { model in
                    let r = await service.addFallback(model: model)
                    modelsToast.show(r.exitCode == 0 ? "Fallback \(model) added" : r.output, isError: r.exitCode != 0)
                    if r.exitCode == 0 { await refreshFallbacks() }
                    return r.exitCode == 0
                },
                onDismiss: { showAddFallbackSheet = false }
            )
        }
        .task {
            await refreshFallbacks()
        }
    }

    private func refreshFallbacks() async {
        let r = await service.listFallbacks()
        // Output format: "Fallbacks (N):\n- model/a\n- model/b"
        // When empty: "Fallbacks (0):\n- none"
        // Parse only lines starting with "- ", strip prefix, exclude "none" placeholder
        let lines = r.output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
            .filter { $0 != "none" }
        fallbackModels = lines
        fallbacksLoaded = true
    }

    private enum MoveDirection { case up, down }

    private func moveFallback(from index: Int, direction: MoveDirection) {
        let newIndex = direction == .up ? index - 1 : index + 1
        guard newIndex >= 0, newIndex < fallbackModels.count else { return }
        guard !isSavingFallbackOrder else { return }

        // Optimistic reorder for instant feedback
        let moved = fallbackModels[index]
        fallbackModels.remove(at: index)
        fallbackModels.insert(moved, at: newIndex)

        // Persist the new order
        let newOrder = fallbackModels
        isSavingFallbackOrder = true
        Task {
            let r = await service.reorderFallbacks(models: newOrder)
            isSavingFallbackOrder = false
            if r.exitCode != 0 {
                modelsToast.show("Reorder failed: \(r.output)", isError: true)
                await refreshFallbacks() // revert to server state
            }
        }
    }

    

    // MARK: - Provider Row

    private func providerRow(_ provider: ProviderStatus) -> some View {
        HStack(spacing: 10) {
            // Status icon — shows validation result if available, otherwise auth status
            if validatingProvider == provider.name {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
            } else if let isValid = providerValidationResults[provider.name] {
                Image(systemName: isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isValid ? Color.green : Color.orange)
                    .font(.title3)
            } else {
                Image(systemName: provider.authenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(provider.authenticated ? Color.green : Color.red)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name.capitalized)
                    .font(.body.weight(.medium))

                if validatingProvider == provider.name {
                    Text("Validating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let isValid = providerValidationResults[provider.name] {
                    Text(isValid ? "Key validated successfully" : "Validation failed — key may be invalid")
                        .font(.caption)
                        .foregroundStyle(isValid ? .green : .orange)
                } else {
                    Text(provider.authenticated ? "Authenticated" : "No API key configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if provider.authenticated {
                Button("Validate") {
                    Task {
                        validatingProvider = provider.name
                        providerValidationResults.removeValue(forKey: provider.name)
                        let result = await service.validateProviderLive(provider: provider.name)
                        providerValidationResults[provider.name] = result.isValid
                        validatingProvider = ""
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!validatingProvider.isEmpty || removingProvider == provider.name)

                Button("Change Key") {
                    configProviderName = provider.name
                    showConfigureAPISheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Add Key") {
                    configProviderName = provider.name
                    showConfigureAPISheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Remove button — available for all providers
            Button {
                Task {
                    removingProvider = provider.name
                    _ = await service.removeProviderAuth(provider: provider.name)
                    removingProvider = nil
                    providerValidationResults.removeValue(forKey: provider.name)
                    modelsToast.show("\(provider.name.capitalized) removed")
                }
            } label: {
                if removingProvider == provider.name {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(removingProvider != nil)
            .help("Remove \(provider.name.capitalized) provider")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Add Agent Sheet

    @State private var newAgentName = ""
    @State private var newAgentWorkspace = ""
    @State private var addAgentError = ""

    private var addAgentSheet: some View {
        VStack(spacing: 16) {
            Text("Add Agent")
                .font(.title2.bold())

            TextField("Agent name (e.g. my-agent)", text: $newAgentName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 350)

            HStack {
                TextField("Workspace path", text: $newAgentWorkspace)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        newAgentWorkspace = url.path
                    }
                }
            }
            .frame(width: 350)

            if !addAgentError.isEmpty {
                Text(addAgentError)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }

            HStack {
                Button("Cancel") { showAddAgent = false }
                    .buttonStyle(.bordered)
                Button("Create") {
                    Task {
                        let result = await service.addAgent(
                            name: newAgentName,
                            workspace: newAgentWorkspace.isEmpty ? "~/.openclaw/workspace-\(newAgentName)" : newAgentWorkspace
                        )
                        if result.exitCode == 0 {
                            showAddAgent = false
                            let createdName = newAgentName
                            newAgentName = ""
                            newAgentWorkspace = ""
                            addAgentError = ""
                            toast.show("Agent \"\(createdName)\" created successfully")
                        } else {
                            addAgentError = result.output
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newAgentName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func agentColor(_ status: AgentStatus) -> Color {
        switch status {
        case .online, .working: return Color.green
        case .idle: return Color.yellow
        case .offline: return Color.red
        case .unknown: return Color(nsColor: .tertiaryLabelColor)
        }
    }
}
// MARK: - Sessions List View

struct SessionsListView: View {
    @Bindable var service: OpenClawService
    var onOpenSession: (Agent, String) -> Void

    @State private var gateway = GatewayWebSocket()
    @State private var gatewaySessions: [GatewaySession] = []
    @State private var cliSessions: [AgentSession] = []
    @State private var isLoading = true
    @State private var filterAgent = ""
    @State private var usingGateway = false

    private var filteredSessions: [GatewaySession] {
        if filterAgent.isEmpty {
            return gatewaySessions
        }
        return gatewaySessions.filter { $0.agentId == filterAgent }
    }

    private var agentIds: [String] {
        Array(Set(gatewaySessions.compactMap(\.agentId))).sorted()
    }

    var body: some View {
        Group {
            if isLoading && gatewaySessions.isEmpty {
                LoadingStateView(message: "Loading sessions...")
            } else if filteredSessions.isEmpty {
                EmptyStateView(
                    icon: "bubble.left.and.bubble.right",
                    title: "No Sessions",
                    message: "No conversation sessions found. Send a message to an agent to start one."
                )
            } else {
                List {
                    ForEach(filteredSessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationSubtitle("\(filteredSessions.count) session\(filteredSessions.count == 1 ? "" : "s")")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ConnectionBadge(isConnected: usingGateway, connectedLabel: "Gateway", offlineLabel: "CLI")
            }
            ToolbarItem(placement: .automatic) {
                Picker("Agent", selection: $filterAgent) {
                    Text("All Agents").tag("")
                    ForEach(agentIds, id: \.self) { agentId in
                        Text(agentId).tag(agentId)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadSessions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help("Refresh sessions")
            }
        }
        .task {
            gateway.connect()
            // Give the gateway a moment to connect
            try? await Task.sleep(for: .seconds(1))
            await loadSessions()
        }
    }

    private func sessionRow(_ session: GatewaySession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let agentId = session.agentId {
                        Text(agentId)
                            .font(.callout.bold())
                    }
                    if let displayName = session.displayName {
                        StatusBadge(label: displayName, color: Color.accentColor)
                    }
                }

                Text(session.key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let model = session.model {
                        Label(model, systemImage: "cpu")
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .lineLimit(1)
                    }
                    if let totalTokens = session.totalTokens {
                        Label("\(totalTokens) tokens", systemImage: "number")
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                    if let updatedAt = session.updatedAt {
                        Text(formatDate(updatedAt))
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
            }

            Spacer()

            Button("Open Chat") {
                openSession(session)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open Chat") {
                openSession(session)
            }
            Divider()
            Button("Copy Session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.key, forType: .string)
            }
        }
    }

    private func openSession(_ session: GatewaySession) {
        guard let agentId = session.agentId else { return }
        // Pass the session key — AgentDetailView can match by key or sessionId
        let id = session.key

        if let agent = service.agents.first(where: { $0.name == agentId }) {
            onOpenSession(agent, id)
        }
    }

    private func loadSessions() async {
        isLoading = true

        // Try gateway first for real-time data
        if gateway.isConnected {
            do {
                let response = try await gateway.sessionsList()
                gatewaySessions = (response.sessions ?? [])
                    .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
                usingGateway = true
                isLoading = false
                return
            } catch {
                print("[Sessions] Gateway failed: \(error), falling back to CLI")
            }
        }

        // Fallback: use CLI sessions and convert to GatewaySession format
        let cli = await service.fetchSessions()
        gatewaySessions = cli.map { s in
            GatewaySession(
                key: s.key,
                kind: s.kind,
                displayName: nil,
                chatType: nil,
                origin: nil,
                updatedAt: s.updatedAt,
                sessionId: s.sessionId,
                systemSent: nil,
                abortedLastRun: nil,
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: nil,
                totalTokensFresh: nil,
                modelProvider: nil,
                model: s.model,
                contextTokens: nil,
                lastChannel: nil
            )
        }
        .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        usingGateway = false
        isLoading = false
    }

    private func formatDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

