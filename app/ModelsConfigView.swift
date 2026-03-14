import SwiftUI

struct ModelProvider: Identifiable {
    let id = UUID()
    let name: String
    let key: String
    let icon: String
    let description: String
    let command: String
}

private let providers: [ModelProvider] = [
    ModelProvider(
        name: "Anthropic",
        key: "anthropic",
        icon: "brain.head.profile",
        description: "Claude models (Sonnet, Opus, Haiku)",
        command: "openclaw models auth paste-token --provider anthropic"
    ),
    ModelProvider(
        name: "OpenAI",
        key: "openai",
        icon: "sparkles",
        description: "GPT models",
        command: "openclaw models auth paste-token --provider openai"
    ),
    ModelProvider(
        name: "Ollama (Local)",
        key: "ollama",
        icon: "desktopcomputer",
        description: "Run models locally with Ollama",
        command: "openclaw models auth paste-token --provider ollama"
    ),
    ModelProvider(
        name: "Google",
        key: "google",
        icon: "globe",
        description: "Gemini models",
        command: "openclaw models auth paste-token --provider google"
    ),
]

struct ModelsConfigView: View {
    @State private var shell = ShellService()
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
                            let result = await shell.run(
                                "openclaw models set \"\(defaultModel)\""
                            )
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
                    TextField("e.g. openai/gpt-5.1-codex", text: $fallbackModel)
                        .textFieldStyle(.roundedBorder)
                    Button("Set") {
                        Task {
                            let result = await shell.run(
                                "openclaw models fallbacks add \"\(fallbackModel)\""
                            )
                            resultMessage = result.exitCode == 0
                                ? "Fallback model set!" : result.output
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
    }

    // MARK: - Provider Card

    private func providerCard(_ provider: ModelProvider) -> some View {
        HStack(spacing: 12) {
            Image(systemName: provider.icon)
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.headline)
                Text(provider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Configure") {
                selectedProvider = provider
                apiKey = ""
            }
            .buttonStyle(.bordered)
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
        // Pipe the token into the auth command
        let result = await shell.run(
            "echo \"\(apiKey)\" | openclaw models auth paste-token --provider \(provider.key)"
        )

        if result.exitCode == 0 {
            resultMessage = "\(provider.name) key saved!"
            resultIsError = false
            // Dismiss after a moment
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
    ModelsConfigView()
        .frame(width: 600, height: 500)
}
