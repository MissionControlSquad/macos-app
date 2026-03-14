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

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
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

enum SidebarItem: String, Identifiable, CaseIterable {
    case agents = "Agents"
    case sessions = "Sessions"
    case logs = "Logs"
    case gateway = "Gateway"
    case models = "Models"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agents: return "person.3.fill"
        case .sessions: return "bubble.left.and.bubble.right.fill"
        case .logs: return "doc.text.magnifyingglass"
        case .gateway: return "server.rack"
        case .models: return "cpu"
        case .settings: return "gearshape"
        }
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
                    let result = await service.deleteAgent(name: agent.name)
                    if result.exitCode == 0 {
                        toast.show("Agent \"\(agent.displayName ?? agent.name)\" deleted")
                        if selection == "agent:\(agent.id)" {
                            selection = SidebarItem.agents.rawValue
                        }
                    } else {
                        toast.show("Failed to delete agent: \(result.output)", isError: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { agent in
            Text("This will permanently remove \"\(agent.displayName ?? agent.name)\" and its configuration. This action cannot be undone.")
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
                ForEach(SidebarItem.allCases) { item in
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
        case .gateway:
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
            AgentDetailView(agent: agent, service: service, initialSessionId: openSessionId)
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
            case SidebarItem.settings.rawValue:
                SettingsView(service: service, gateway: gateway)
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

    private var gatewayView: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status card
                    GroupBox("Status") {
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
                    }

                    // Control buttons
                    GroupBox("Controls") {
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
                            HStack {
                                Text("Operation Log")
                                Spacer()
                                if gatewayIsActing {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Running...")
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
                                Text("Dashboard: http://127.0.0.1:\(port)/")
                                    .font(.callout)
                                Spacer()
                                Button("Open in Browser") {
                                    if let url = URL(string: "http://127.0.0.1:\(port)/") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
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

    @State private var configProviderName = ""
    @State private var configApiKey = ""
    @State private var modelsToast = ToastState()
    @State private var selectedModel = ""

    private var modelsView: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Current model config
                    GroupBox("Active Configuration") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Default Model:")
                                    .foregroundStyle(.secondary)
                                Text(service.modelsStatus?.defaultModel ?? "Not set")
                                    .font(.system(.body, design: .monospaced))
                            }

                            HStack {
                                Text("Fallback Models:")
                                    .foregroundStyle(.secondary)
                                Text(service.modelsStatus?.fallbacks?.joined(separator: ", ") ?? "Not set")
                                    .font(.system(.body, design: .monospaced))
                            }

                            // Set default model via dropdown
                            HStack(spacing: 8) {
                                ModelCatalogPicker(selection: $selectedModel)
                                    .frame(maxWidth: .infinity)

                                Button("Set Default") {
                                    Task {
                                        let result = await service.setDefaultModel(selectedModel)
                                        modelsToast.show(result.exitCode == 0 ? "Default model set to \(selectedModel)" : result.output, isError: result.exitCode != 0)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedModel.isEmpty)

                                Button {
                                    ModelCatalogStore.shared.refresh()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .help("Refresh model list from OpenClaw")
                            }
                            .padding(.top, 4)
                        }
                    }

                    // Providers with configure buttons
                    GroupBox("Providers") {
                        if let providers = service.modelsStatus?.providers, !providers.isEmpty {
                            ForEach(providers) { provider in
                                providerRow(provider)
                            }
                        } else {
                            Text("No providers found. Run a scan to discover available providers.")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }

                    // Configure API Key
                    GroupBox("Configure API Key") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Enter your API key to authenticate with a provider. The key is stored locally by OpenClaw.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                TextField("Provider (e.g. anthropic, openai)", text: $configProviderName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 250)

                                SecureField("API Key", text: $configApiKey)
                                    .textFieldStyle(.roundedBorder)

                                Button("Save") {
                                    Task {
                                        let result = await service.configureProvider(
                                            provider: configProviderName,
                                            apiKey: configApiKey
                                        )
                                        modelsToast.show(result.exitCode == 0 ? "\(configProviderName) API key configured successfully" : result.output, isError: result.exitCode != 0)
                                        if result.exitCode == 0 {
                                            configApiKey = ""
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(configProviderName.isEmpty || configApiKey.isEmpty)
                            }

                            // Quick provider buttons
                            HStack(spacing: 8) {
                                Text("Quick select:")
                                    .font(.caption)
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                ForEach(["anthropic", "openai", "mistral", "openrouter", "huggingface"], id: \.self) { name in
                                    Button(name) {
                                        configProviderName = name
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    ToastBanner(toast: modelsToast)

                    // Model management actions
                    HStack(spacing: 12) {
                        Button {
                            Task { await service.runCommand("openclaw models scan --json") }
                        } label: {
                            Label("Scan Models", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            ModelCatalogStore.shared.refresh()
                        } label: {
                            Label("Refresh Catalog", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    // Model catalog status
                    let catalog = ModelCatalogStore.shared
                    GroupBox {
                        if !catalog.debugLog.isEmpty {
                            DisclosureGroup("Debug Log") {
                                ScrollView {
                                    Text(catalog.debugLog)
                                        .font(.system(.caption2, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 200)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } label: {
                        HStack {
                            Text("Model Catalog")
                            Spacer()
                            Text("\(catalog.models.count) models, \(catalog.providers.count) providers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if catalog.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
    }

    private func providerRow(_ provider: ProviderStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: provider.authenticated == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(provider.authenticated == true ? Color.green : Color.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.body.weight(.medium))
                Text(provider.authenticated == true ? "Authenticated" : "No API key configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if provider.authenticated != true {
                Button("Configure") {
                    configProviderName = provider.name
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                StatusBadge(label: "Connected", color: Color.green)
            }
        }
        .padding(6)
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

