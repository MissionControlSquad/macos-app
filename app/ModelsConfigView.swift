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
        VStack(spacing: 0) {
            HStack {
                Text("Model Providers")
                    .font(.title.bold())
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Provider Cards
                    Section {
                        Text("API Keys")
                            .font(.headline)
                        Text("Configure your AI provider credentials. Keys are stored locally by OpenClaw.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        ForEach(providers) { provider in
                            providerCard(provider)
                        }
                    }

                    Divider()

                    // Default Model Config
                    Section {
                        Text("Default Models")
                            .font(.headline)
                        Text("Set the primary and fallback models for your agents.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Primary:")
                                    .frame(width: 70, alignment: .trailing)
                                TextField("e.g. anthropic/claude-sonnet-4-6", text: $defaultModel)
                                    .textFieldStyle(.roundedBorder)
                                Button("Set") {
                                    Task {
                                        let result = await shell.run(
                                            "openclaw config set default-model \"\(defaultModel)\""
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
                                            "openclaw config set fallback-model \"\(fallbackModel)\""
                                        )
                                        resultMessage = result.exitCode == 0
                                            ? "Fallback model set!" : result.output
                                        resultIsError = result.exitCode != 0
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(fallbackModel.isEmpty)
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if !resultMessage.isEmpty {
                        Text(resultMessage)
                            .font(.callout)
                            .foregroundStyle(resultIsError ? .red : .green)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
        }
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
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - API Key Sheet

    private func apiKeySheet(_ provider: ModelProvider) -> some View {
        VStack(spacing: 16) {
            Text("Configure \(provider.name)")
                .font(.title2.bold())

            Text("Paste your \(provider.name) API key below. It will be stored locally by OpenClaw and never sent anywhere except to the provider.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)

            HStack {
                Button("Cancel") {
                    selectedProvider = nil
                }
                .buttonStyle(.bordered)

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
                .disabled(apiKey.isEmpty || isSaving)
            }

            if !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(resultIsError ? .red : .green)
            }
        }
        .padding(24)
        .frame(width: 500)
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
}
