import SwiftUI

struct SettingsView: View {
    @Bindable var service: OpenClawService
    @State private var selectedTab = SettingsTab.global

    enum SettingsTab: String, CaseIterable {
        case global = "Global"
        case agents = "Per-Agent"
        case fallbacks = "Fallbacks"
        case config = "Config"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title.bold())
                Spacer()
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
            }
            .padding()

            Divider()

            switch selectedTab {
            case .global:
                GlobalSettingsTab(service: service)
            case .agents:
                AgentSettingsTab(service: service)
            case .fallbacks:
                FallbacksTab(service: service)
            case .config:
                ConfigTab(service: service)
            }
        }
    }
}

// MARK: - Global Settings Tab

private struct GlobalSettingsTab: View {
    @Bindable var service: OpenClawService
    @State private var defaultModel = ""
    @State private var providerName = ""
    @State private var apiKey = ""
    @State private var result = ""
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Current status
                VStack(alignment: .leading, spacing: 10) {
                    Text("Model Configuration")
                        .font(.headline)

                    HStack {
                        Text("Default Model:")
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                        Text(service.modelsStatus?.defaultModel ?? "Not set")
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("Fallback Models:")
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                        Text(service.modelsStatus?.fallbacks?.joined(separator: ", ") ?? "Not set")
                            .font(.system(.body, design: .monospaced))
                    }

                    Divider()

                    // Set default model
                    HStack {
                        Text("Set Default:")
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                        ModelCatalogPicker(selection: $defaultModel)
                        Button("Apply") {
                            Task {
                                let r = await service.setDefaultModel(defaultModel)
                                result = r.exitCode == 0 ? "Default model updated" : r.output
                                isError = r.exitCode != 0
                                if r.exitCode == 0 { defaultModel = "" }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(defaultModel.isEmpty)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Provider auth
                VStack(alignment: .leading, spacing: 10) {
                    Text("Provider Authentication")
                        .font(.headline)

                    Text("Configure API keys for model providers. These apply globally to all agents unless overridden per-agent.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    // Provider list
                    if let providers = service.modelsStatus?.providers, !providers.isEmpty {
                        ForEach(providers) { provider in
                            HStack(spacing: 10) {
                                Image(systemName: provider.authenticated == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(provider.authenticated == true ? .green : .red)
                                Text(provider.name)
                                    .font(.body.weight(.medium))
                                Spacer()
                                if provider.authenticated == true {
                                    Text("Authenticated")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                } else {
                                    Button("Configure") {
                                        providerName = provider.name
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Divider()

                    // Add API key
                    Text("Add / Update API Key")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 8) {
                        ProviderSelectionPicker(selection: $providerName)

                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            Task {
                                let r = await service.configureProvider(provider: providerName, apiKey: apiKey)
                                result = r.exitCode == 0
                                    ? "\(providerName) API key saved"
                                    : r.output
                                isError = r.exitCode != 0
                                if r.exitCode == 0 { apiKey = "" }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(providerName.isEmpty || apiKey.isEmpty)
                    }

                    // Environment variable hint
                    DisclosureGroup("Alternative: Environment Variables") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You can also set API keys via environment variables in ~/.openclaw/.env:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("ANTHROPIC_API_KEY=sk-ant-...\nOPENAI_API_KEY=sk-...\nGOOGLE_API_KEY=...")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color(.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
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

                // Model catalog summary
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
                        }
                        Button {
                            catalog.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Result
                if !result.isEmpty {
                    resultBanner(result, isError: isError)
                }
            }
            .padding()
        }
        .task {
            await service.fetchModelsStatus()
        }
    }
}

// MARK: - Per-Agent Settings Tab

private struct AgentSettingsTab: View {
    @Bindable var service: OpenClawService
    @State private var selectedAgent: Agent?
    @State private var agentModel = ""
    @State private var agentProvider = ""
    @State private var agentApiKey = ""
    @State private var result = ""
    @State private var isError = false

    var body: some View {
        HSplitView {
            // Agent list
            List(service.agents, selection: $selectedAgent) { agent in
                Button {
                    selectedAgent = agent
                } label: {
                    HStack(spacing: 6) {
                        if let emoji = agent.emoji, !emoji.isEmpty {
                            Text(emoji)
                        } else {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.displayName ?? agent.name)
                                .font(.callout.weight(.medium))
                            Text(agent.name)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .listRowBackground(selectedAgent?.id == agent.id ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160, maxWidth: 220)

            // Agent settings
            if let agent = selectedAgent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Agent info header
                        HStack(spacing: 10) {
                            if let emoji = agent.emoji, !emoji.isEmpty {
                                Text(emoji).font(.largeTitle)
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.displayName ?? agent.name)
                                    .font(.title2.bold())
                                Text("Agent ID: \(agent.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Workspace: \(agent.workspace)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Divider()

                        // Per-agent model
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Model Override")
                                .font(.headline)

                            Text("Set a specific model for this agent. Leave empty to use the global default.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            HStack {
                                ModelCatalogPicker(
                                    selection: $agentModel,
                                    placeholder: "Use global default"
                                )

                                Button("Apply") {
                                    Task {
                                        let r = await service.setAgentModel(agent: agent.name, model: agentModel)
                                        result = r.exitCode == 0
                                            ? "Model set for \(agent.name)"
                                            : r.output
                                        isError = r.exitCode != 0
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(agentModel.isEmpty)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Per-agent auth
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Agent API Key")
                                .font(.headline)

                            Text("Configure a provider API key specifically for this agent. This overrides the global key.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ProviderSelectionPicker(selection: $agentProvider)

                                SecureField("API Key", text: $agentApiKey)
                                    .textFieldStyle(.roundedBorder)

                                Button("Save") {
                                    Task {
                                        let r = await service.configureAgentAuth(
                                            agent: agent.name,
                                            provider: agentProvider,
                                            apiKey: agentApiKey
                                        )
                                        result = r.exitCode == 0
                                            ? "\(agentProvider) key saved for \(agent.name)"
                                            : r.output
                                        isError = r.exitCode != 0
                                        if r.exitCode == 0 { agentApiKey = "" }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(agentProvider.isEmpty || agentApiKey.isEmpty)
                            }

                            Text("Auth store: ~/.openclaw/agents/\(agent.name)/agent/auth-profiles.json")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Agent config info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Agent Configuration")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 4) {
                                configRow("Agent ID", agent.name)
                                configRow("Workspace", agent.workspace)
                                if let dir = agent.agentDir {
                                    configRow("Agent Dir", dir)
                                }
                                configRow("Default", agent.isDefault == true ? "Yes" : "No")
                                if let count = agent.bindingsCount {
                                    configRow("Bindings", "\(count)")
                                }
                                if let routes = agent.routes, !routes.isEmpty {
                                    configRow("Routes", routes.joined(separator: ", "))
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        if !result.isEmpty {
                            resultBanner(result, isError: isError)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView {
                    Label("Select an Agent", systemImage: "person.circle")
                } description: {
                    Text("Choose an agent from the list to configure its model and API keys.")
                }
            }
        }
        .task {
            if service.agents.isEmpty {
                await service.fetchAgents()
            }
        }
    }

    private func configRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Fallbacks Tab

private struct FallbacksTab: View {
    @Bindable var service: OpenClawService
    @State private var fallbacksOutput = ""
    @State private var newFallback = ""
    @State private var result = ""
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Fallback Chain")
                            .font(.headline)
                        Spacer()
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("When the primary model fails, OpenClaw tries fallback models in order.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if fallbacksOutput.isEmpty {
                        Text("No fallbacks configured.")
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                    } else {
                        Text(fallbacksOutput)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Divider()

                    HStack {
                        ModelCatalogPicker(selection: $newFallback)

                        Button("Add Fallback") {
                            Task {
                                let r = await service.addFallback(model: newFallback)
                                result = r.exitCode == 0 ? "Fallback added" : r.output
                                isError = r.exitCode != 0
                                if r.exitCode == 0 {
                                    newFallback = ""
                                    await refresh()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newFallback.isEmpty)

                        Button("Clear All") {
                            Task {
                                let r = await service.runCommand("openclaw models fallbacks clear")
                                result = r.exitCode == 0 ? "All fallbacks cleared" : r.output
                                isError = r.exitCode != 0
                                await refresh()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if !result.isEmpty {
                    resultBanner(result, isError: isError)
                }
            }
            .padding()
        }
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        let r = await service.listFallbacks()
        fallbacksOutput = r.output
    }
}

// MARK: - Config Tab

private struct ConfigTab: View {
    @Bindable var service: OpenClawService
    @State private var configKey = ""
    @State private var configValue = ""
    @State private var configOutput = ""
    @State private var result = ""
    @State private var isError = false
    @State private var doctorOutput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Config get/set
                VStack(alignment: .leading, spacing: 10) {
                    Text("Configuration")
                        .font(.headline)

                    Text("Read and write OpenClaw config values using dot-path notation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Key (e.g. gateway.mode)", text: $configKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 200)

                        TextField("Value (leave empty to read)", text: $configValue)
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
                                result = r.exitCode == 0 ? "\(configKey) updated" : r.output
                                isError = r.exitCode != 0
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(configKey.isEmpty || configValue.isEmpty)
                    }

                    // Common config keys
                    HStack(spacing: 6) {
                        Text("Common keys:")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Diagnostics
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Diagnostics")
                            .font(.headline)
                        Spacer()
                        Button {
                            Task {
                                let r = await service.runDoctor()
                                doctorOutput = r.output
                            }
                        } label: {
                            Label("Run Doctor", systemImage: "stethoscope")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            Task {
                                let r = await service.configValidate()
                                doctorOutput = r.output
                            }
                        } label: {
                            Label("Validate Config", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            Task {
                                let r = await service.runCommand("openclaw doctor --repair")
                                doctorOutput = r.output
                            }
                        } label: {
                            Label("Auto-Fix", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !doctorOutput.isEmpty {
                        ScrollView {
                            Text(doctorOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                        .padding(10)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Config file path
                VStack(alignment: .leading, spacing: 6) {
                    Text("Config File")
                        .font(.headline)
                    Text("~/.openclaw/openclaw.json")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Button("Open in Finder") {
                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                        let url = URL(fileURLWithPath: "\(home)/.openclaw/openclaw.json")
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if !result.isEmpty {
                    resultBanner(result, isError: isError)
                }
            }
            .padding()
        }
    }
}

// MARK: - Shared Helpers

private func resultBanner(_ text: String, isError: Bool) -> some View {
    HStack(spacing: 6) {
        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        Text(text)
    }
    .font(.callout)
    .foregroundStyle(isError ? .red : .green)
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background((isError ? Color.red : Color.green).opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 10))
}
