import SwiftUI

struct ModelProvider: Identifiable {
    let id = UUID()
    let name: String
    let key: String
    let icon: String
    let description: String
    /// Whether this provider requires an API key (false for Ollama, local runners)
    let requiresKey: Bool

    init(name: String, key: String, icon: String, description: String, requiresKey: Bool = true) {
        self.name = name
        self.key = key
        self.icon = icon
        self.description = description
        self.requiresKey = requiresKey
    }
}

/// All providers supported by `openclaw onboard`, matching the official docs.
/// Ordered with the most popular providers first.
private let providers: [ModelProvider] = [
    // --- Major cloud providers ---
    ModelProvider(
        name: "Anthropic",
        key: "anthropic",
        icon: "brain.head.profile",
        description: "Claude models (Sonnet, Opus, Haiku)"
    ),
    ModelProvider(
        name: "OpenAI",
        key: "openai",
        icon: "sparkles",
        description: "GPT-4.1, o3, o4 models"
    ),
    ModelProvider(
        name: "Google",
        key: "google",
        icon: "globe",
        description: "Gemini models"
    ),
    ModelProvider(
        name: "Mistral",
        key: "mistral",
        icon: "wind",
        description: "Mistral Large, Codestral, Pixtral"
    ),
    ModelProvider(
        name: "xAI",
        key: "xai",
        icon: "bolt.fill",
        description: "Grok models"
    ),
    // --- Aggregators ---
    ModelProvider(
        name: "OpenRouter",
        key: "openrouter",
        icon: "arrow.triangle.branch",
        description: "Access 100+ models via OpenRouter"
    ),
    ModelProvider(
        name: "Together AI",
        key: "together",
        icon: "square.stack.3d.up",
        description: "Llama, Mixtral, and more"
    ),
    ModelProvider(
        name: "Hugging Face",
        key: "huggingface",
        icon: "face.smiling",
        description: "Open-source models via HF Inference"
    ),
    // --- Additional providers ---
    ModelProvider(
        name: "Venice",
        key: "venice",
        icon: "building.columns",
        description: "Privacy-focused AI models"
    ),
    ModelProvider(
        name: "Moonshot",
        key: "moonshot",
        icon: "moon.fill",
        description: "Moonshot AI models"
    ),
    ModelProvider(
        name: "Kimi Coding",
        key: "kimi-coding",
        icon: "chevron.left.forwardslash.chevron.right",
        description: "Kimi coding-focused models"
    ),
    ModelProvider(
        name: "Z.AI",
        key: "zai",
        icon: "wand.and.stars",
        description: "Z.AI / GLM models"
    ),
    ModelProvider(
        name: "Xiaomi",
        key: "xiaomi",
        icon: "cpu",
        description: "Xiaomi MiLM models"
    ),
    ModelProvider(
        name: "MiniMax",
        key: "minimax",
        icon: "rectangle.compress.vertical",
        description: "MiniMax global models"
    ),
    ModelProvider(
        name: "Kilocode",
        key: "kilocode",
        icon: "terminal",
        description: "Kilocode Gateway"
    ),
    ModelProvider(
        name: "Qianfan (Baidu)",
        key: "qianfan",
        icon: "cloud.fill",
        description: "Baidu Qianfan platform"
    ),
    ModelProvider(
        name: "Qwen / Model Studio",
        key: "modelstudio",
        icon: "paintbrush",
        description: "Alibaba Model Studio (Global)"
    ),
    // --- Infrastructure ---
    ModelProvider(
        name: "LiteLLM",
        key: "litellm",
        icon: "server.rack",
        description: "Unified proxy for any LLM provider"
    ),
    ModelProvider(
        name: "Vercel AI Gateway",
        key: "vercel-ai-gateway",
        icon: "arrowshape.turn.up.right.fill",
        description: "Vercel AI Gateway proxy"
    ),
    // --- Local runners (no API key) ---
    ModelProvider(
        name: "Ollama (Local)",
        key: "ollama",
        icon: "desktopcomputer",
        description: "Run models locally with Ollama",
        requiresKey: false
    ),
    ModelProvider(
        name: "vLLM (Local)",
        key: "vllm",
        icon: "memorychip",
        description: "High-throughput local inference",
        requiresKey: false
    ),
    ModelProvider(
        name: "SGLang (Local)",
        key: "sglang",
        icon: "bolt.horizontal",
        description: "Fast local inference with SGLang",
        requiresKey: false
    ),
]

struct ModelsConfigView: View {
    var service: OpenClawService

    @State private var selectedProvider: ModelProvider?
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var resultMessage = ""
    @State private var resultIsError = false
    @State private var defaultModel = ""
    @State private var fallbackModel = ""

    var body: some View {
        Form {
            Section {
                Text("Configure your AI provider credentials. Keys are stored locally by OpenClaw.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(providers) { provider in
                    providerCard(provider)
                }
            } header: {
                Text("API Keys")
            }

            Section {
                Text("Set the primary and fallback models for your agents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Primary:")
                        .frame(width: 70, alignment: .trailing)
                    TextField("e.g. anthropic/claude-sonnet-4-6", text: $defaultModel)
                        .textFieldStyle(.roundedBorder)
                    Button("Set") {
                        Task {
                            let result = await service.setDefaultModel(defaultModel)
                            resultMessage = result.exitCode == 0
                                ? "Default model set!" : result.output
                            resultIsError = result.exitCode != 0
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(defaultModel.isEmpty)
                }

                HStack {
                    Text("Fallback:")
                        .frame(width: 70, alignment: .trailing)
                    TextField("e.g. openai/gpt-4.1", text: $fallbackModel)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        Task {
                            let result = await service.addFallback(model: fallbackModel)
                            resultMessage = result.exitCode == 0
                                ? "Fallback model added!" : result.output
                            resultIsError = result.exitCode != 0
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(fallbackModel.isEmpty)
                }
            } header: {
                Text("Default Models")
            }

            if !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(.callout)
                    .foregroundStyle(resultIsError ? Color.red : Color.green)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Model Providers")
        .sheet(item: $selectedProvider) { provider in
            apiKeySheet(provider)
        }
        .task {
            // Load current default model into the text field
            if let current = service.modelsStatus?.defaultModel {
                defaultModel = current
            }
        }
    }

    // MARK: - Provider Card

    /// Find the provider status from the service's cached modelsStatus
    private func providerStatus(for key: String) -> ProviderStatus? {
        service.modelsStatus?.providers.first { $0.provider == key }
    }

    private func providerCard(_ provider: ModelProvider) -> some View {
        HStack(spacing: 12) {
            Image(systemName: provider.icon)
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    if let status = providerStatus(for: provider.key) {
                        Image(systemName: status.authenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(status.authenticated ? .green : .red)
                            .font(.caption)
                        Text(status.authenticated ? "Configured" : "Not authenticated")
                            .font(.caption)
                            .foregroundStyle(status.authenticated ? .green : .secondary)
                    } else {
                        Text(provider.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let status = providerStatus(for: provider.key), status.authenticated {
                Button("Change Key") {
                    selectedProvider = provider
                    apiKey = ""
                    resultMessage = ""
                }
                .buttonStyle(.bordered)
            } else {
                Button(provider.requiresKey ? "Add Key" : "Enable") {
                    if provider.requiresKey {
                        selectedProvider = provider
                        apiKey = ""
                        resultMessage = ""
                    } else {
                        // No key needed (e.g. Ollama) — configure directly
                        Task {
                            isSaving = true
                            let result = await service.configureProvider(provider: provider.key, apiKey: "")
                            resultMessage = result.exitCode == 0
                                ? "\(provider.name) enabled!" : result.output
                            resultIsError = result.exitCode != 0
                            isSaving = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - API Key Sheet

    private func apiKeySheet(_ provider: ModelProvider) -> some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Paste your \(provider.name) API key below. It will be stored locally by OpenClaw and never sent anywhere except to the provider.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    SecureField("API Key", text: $apiKey)
                }

                if !resultMessage.isEmpty {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(resultIsError ? Color.red : Color.green)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    selectedProvider = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    Task { await saveApiKey(provider) }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Save Key")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.isEmpty || isSaving)
            }
            .padding()
        }
        .navigationTitle("Configure \(provider.name)")
        .frame(width: 460, height: 280)
    }

    private func saveApiKey(_ provider: ModelProvider) async {
        isSaving = true

        // Step 1: Validate the key with a real API call
        resultMessage = "Validating key…"
        resultIsError = false
        let validation = await OpenClawService.validateAPIKey(provider: provider.key, apiKey: apiKey)
        if !validation.isValid {
            resultMessage = validation.error ?? "Invalid API key"
            resultIsError = true
            isSaving = false
            return
        }

        // Step 2: Key is valid — save via openclaw onboard (non-interactive)
        resultMessage = "Saving key…"
        let result = await service.configureProvider(provider: provider.key, apiKey: apiKey)

        if result.exitCode == 0 {
            resultMessage = "\(provider.name) key validated and saved!"
            resultIsError = false
            try? await Task.sleep(for: .seconds(1))
            selectedProvider = nil
        } else {
            resultMessage = result.output.isEmpty ? "Failed to save key" : result.output
            resultIsError = true
        }
        isSaving = false
    }
}

#Preview {
    ModelsConfigView(service: OpenClawService())
        .frame(width: 600, height: 500)
}
