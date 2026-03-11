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
                    Text(model.displayLabel).tag(model.key)
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

    private var catalogProviders: [String] { ModelCatalogStore.shared.providers }
    private var quickProviders: [String] { ["anthropic", "openai", "google", "mistral", "openrouter", "ollama", "huggingface", "venice"] }

    private var allProviders: [String] {
        var seen = Set<String>()
        let merged = catalogProviders + quickProviders + (selection.isEmpty ? [] : [selection])
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

enum SidebarSection: String, CaseIterable {
    case main = "Dashboard"
    case manage = "Manage"
    case system = "System"
}

enum SidebarItem: String, Identifiable {
    case agents = "Agents"
    case gateway = "Gateway"
    case models = "Models"
    case channels = "Channels"
    case logs = "Logs"
    case memory = "Memory"
    case skills = "Skills & Plugins"
    case cron = "Automation"
    case hooks = "Hooks"
    case settings = "Settings"
    case terminal = "Terminal"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agents: return "person.3.fill"
        case .gateway: return "server.rack"
        case .models: return "cpu"
        case .channels: return "message.fill"
        case .logs: return "doc.text.magnifyingglass"
        case .memory: return "brain.head.profile"
        case .skills: return "puzzlepiece.extension.fill"
        case .cron: return "clock.arrow.2.circlepath"
        case .hooks: return "link.circle.fill"
        case .settings: return "gearshape"
        case .terminal: return "terminal.fill"
        }
    }

    var section: SidebarSection {
        switch self {
        case .agents, .gateway, .models: return .main
        case .channels, .logs, .memory, .skills, .cron, .hooks: return .manage
        case .settings, .terminal: return .system
        }
    }

    static let allItems: [SidebarItem] = [
        .agents, .gateway, .models,
        .channels, .logs, .memory, .skills, .cron, .hooks,
        .settings, .terminal
    ]
}

struct DashboardView: View {
    @State private var service = OpenClawService()
    @State private var selectedItem: SidebarItem? = .agents
    @State private var customCommand = ""
    @State private var showAddAgent = false
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var selectedAgent: Agent?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .task {
            await service.refreshAll()
            startAutoRefresh()
        }
        .onDisappear {
            autoRefreshTask?.cancel()
        }
        .sheet(isPresented: $showAddAgent) {
            addAgentSheet
        }
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

    private var sidebar: some View {
        List(selection: $selectedItem) {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                Section(section.rawValue) {
                    ForEach(SidebarItem.allItems.filter { $0.section == section }) { item in
                        Button {
                            selectedItem = item
                            selectedAgent = nil
                        } label: {
                            Label(item.rawValue, systemImage: item.icon)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Quick Actions") {
                Button {
                    Task { await service.refreshAll() }
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }

                Button {
                    Task { await service.runDoctor() }
                } label: {
                    Label("Run Doctor", systemImage: "stethoscope")
                }
            }

            // Live agent list in sidebar
            if !service.agents.isEmpty {
                Section("Agents (\(service.agents.count))") {
                    ForEach(service.agents) { agent in
                        Button {
                            selectedAgent = agent
                            selectedItem = .agents
                        } label: {
                            HStack(spacing: 6) {
                                if let emoji = agent.emoji, !emoji.isEmpty {
                                    Text(emoji)
                                } else {
                                    Image(systemName: agent.agentStatus.icon)
                                        .foregroundStyle(agentColor(agent.agentStatus))
                                }
                                Text(agent.displayName ?? agent.name)
                                    .font(.callout)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Gateway status badge
            Section("Status") {
                HStack {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(service.gatewayStatus?.running == true ? .green : .red)
                    Text("Gateway")
                        .font(.callout)
                    Spacer()
                    Text(service.gatewayStatus?.running == true ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("OpenClaw")
        .toolbar {
            ToolbarItem {
                if service.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let selectedAgent {
            AgentDetailView(agent: selectedAgent, service: service)
        } else {
            switch selectedItem {
            case .agents:
                agentsView
            case .gateway:
                gatewayView
            case .models:
                modelsView
            case .channels:
                ChannelsView(service: service)
            case .logs:
                LogsView(service: service)
            case .memory:
                MemoryView(service: service)
            case .skills:
                SkillsPluginsView(service: service)
            case .cron:
                CronView(service: service)
            case .hooks:
                HooksView(service: service)
            case .settings:
                SettingsView(service: service)
            case .terminal:
                terminalView
            case nil:
                agentsView
            }
        }
    }

    // MARK: - Agents View

    private var agentsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agents")
                    .font(.title.bold())
                Spacer()
                Button {
                    showAddAgent = true
                } label: {
                    Label("Add Agent", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await service.fetchAgents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            if service.agents.isEmpty {
                ContentUnavailableView {
                    Label("No Agents", systemImage: "person.slash")
                } description: {
                    Text("Create your first agent to get started.")
                } actions: {
                    Button("Add Agent") {
                        showAddAgent = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(service.agents) { agent in
                        agentRow(agent)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedAgent = agent
                            }
                    }
                }
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

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.displayName ?? agent.name)
                        .font(.headline)
                    if agent.displayName != nil {
                        Text("(\(agent.name))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(agent.workspace)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if let count = agent.bindingsCount, count > 0 {
                        Text("\(count) binding\(count == 1 ? "" : "s")")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if agent.isDefault == true {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
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
            Button("Delete Agent") {
                Task { await service.deleteAgent(name: agent.name) }
            }
        }
    }

    // MARK: - Gateway View

    @State private var gatewayActionResult = ""
    @State private var gatewayActionIsError = false
    @State private var gatewayIsActing = false

    private var gatewayView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Gateway")
                    .font(.title.bold())
                Spacer()
                if gatewayIsActing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await service.fetchGatewayStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status card
                    HStack(spacing: 12) {
                        Image(systemName: service.gatewayStatus?.running == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(service.gatewayStatus?.running == true ? .green : .red)

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
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Control buttons
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Controls")
                            .font(.headline)

                        HStack(spacing: 12) {
                            if service.gatewayStatus?.running == true {
                                Button {
                                    runGatewayAction { await service.stopGateway() }
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                }
                                .buttonStyle(.bordered)
                                .disabled(gatewayIsActing)

                                Button {
                                    runGatewayAction { await service.restartGateway() }
                                } label: {
                                    Label("Restart", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .disabled(gatewayIsActing)
                            } else {
                                Button {
                                    runGatewayAction { await service.startGateway() }
                                } label: {
                                    Label(gatewayIsActing ? "Starting..." : "Start Gateway", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(gatewayIsActing)
                            }

                            Button {
                                runGatewayAction { await service.gatewayHealth() }
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
                                    runGatewayAction { await service.installGateway() }
                                } label: {
                                    Label("Reinstall Service", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    runGatewayAction { await service.runCommand("openclaw gateway uninstall") }
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
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Operation log
                    if !service.gatewayLog.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Operation Log")
                                    .font(.headline)
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
                                    gatewayActionResult = ""
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }

                            ScrollView {
                                Text(service.gatewayLog)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Dashboard link
                    if service.gatewayStatus?.running == true {
                        let port = service.gatewayStatus?.gatewayPort ?? 18789
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
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
        }
    }

    private func runGatewayAction(_ action: @escaping () async -> CommandResult) {
        Task {
            gatewayIsActing = true
            let result = await action()
            gatewayActionResult = result.output
            gatewayActionIsError = result.exitCode != 0
            gatewayIsActing = false
        }
    }

    // MARK: - Models View

    @State private var configProviderName = ""
    @State private var configApiKey = ""
    @State private var modelConfigResult = ""
    @State private var modelConfigIsError = false
    @State private var selectedModel = ""

    private var modelsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Models")
                    .font(.title.bold())
                Spacer()
                Button {
                    Task { await service.fetchModelsStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Current model config
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Configuration")
                            .font(.headline)

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
                                    modelConfigResult = result.exitCode == 0
                                        ? "Default model set to \(selectedModel)"
                                        : result.output
                                    modelConfigIsError = result.exitCode != 0
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
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Providers with configure buttons
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Providers")
                            .font(.headline)

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
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Configure API Key
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Configure API Key")
                            .font(.headline)

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
                                    modelConfigResult = result.exitCode == 0
                                        ? "\(configProviderName) API key configured successfully"
                                        : result.output
                                    modelConfigIsError = result.exitCode != 0
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
                                .foregroundStyle(.tertiary)
                            ForEach(["anthropic", "openai", "mistral", "openrouter", "huggingface"], id: \.self) { name in
                                Button(name) {
                                    configProviderName = name
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Status message
                    if !modelConfigResult.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: modelConfigIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            Text(modelConfigResult)
                        }
                        .font(.callout)
                        .foregroundStyle(modelConfigIsError ? .red : .green)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((modelConfigIsError ? Color.red : Color.green).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Model Catalog")
                                .font(.headline)
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
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding()
            }
        }
    }

    private func providerRow(_ provider: ProviderStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: provider.authenticated == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(provider.authenticated == true ? .green : .red)
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
                Text("Connected")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(10)
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Terminal View

    private var terminalView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Terminal")
                    .font(.title.bold())
                Spacer()
                if service.isRunningCommand {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(service.commandHistory) { result in
                        commandResultView(result)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.textBackgroundColor))

            Divider()

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.green)

                TextField("Enter command...", text: $customCommand)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { runCustomCommand() }

                Button("Run") { runCustomCommand() }
                    .buttonStyle(.borderedProminent)
                    .disabled(customCommand.isEmpty || service.isRunningCommand)
            }
            .padding()
        }
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
                    .foregroundStyle(.red)
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
                            newAgentName = ""
                            newAgentWorkspace = ""
                            addAgentError = ""
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
    }

    // MARK: - Helpers

    private func commandResultView(_ result: CommandResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("$ \(result.command)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)
                Spacer()
                Text(result.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if result.exitCode != 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Text(result.output.isEmpty ? "(no output)" : result.output)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(result.exitCode == 0 ? Color.primary : Color.red)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func runCustomCommand() {
        guard !customCommand.isEmpty else { return }
        let cmd = customCommand
        customCommand = ""
        Task { await service.runCommand(cmd) }
    }

    private func agentColor(_ status: AgentStatus) -> Color {
        switch status {
        case .online, .working: return .green
        case .idle: return .yellow
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}
