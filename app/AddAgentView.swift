import SwiftUI

struct AddAgentView: View {
    @State private var shell = ShellService()
    @State private var agentName = ""
    @State private var workspacePath = ""
    @State private var agentEmoji = "🦞"
    @State private var agentDisplayName = ""
    @State private var isCreating = false
    @State private var resultMessage = ""
    @State private var resultIsError = false
    var onCreated: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Agent")
                    .font(.title.bold())
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Agent Identity") {
                    TextField("Agent name (e.g. my-agent)", text: $agentName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Display name (optional)", text: $agentDisplayName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Emoji", text: $agentEmoji)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                Section("Workspace") {
                    HStack {
                        TextField("Workspace path", text: $workspacePath)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                workspacePath = url.path
                            }
                        }
                    }

                    Text("The workspace folder should contain a SOUL.md file that defines the agent's personality and instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await createAgent() }
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.accentColor)
                            }
                            Text(isCreating ? "Creating..." : "Create Agent")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(agentName.isEmpty || workspacePath.isEmpty || isCreating)

                    if !resultMessage.isEmpty {
                        Text(resultMessage)
                            .font(.callout)
                            .foregroundStyle(resultIsError ? Color.red : Color.green)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func createAgent() async {
        isCreating = true
        resultMessage = ""

        // Create workspace directory if needed
        do {
            try FileManager.default.createDirectory(atPath: workspacePath, withIntermediateDirectories: true)
        } catch {
            resultMessage = "Failed to create workspace directory: \(error.localizedDescription)"
            resultIsError = true
            isCreating = false
            return
        }

        // Check if SOUL.md exists, create a default one if not
        let soulPath = "\(workspacePath)/SOUL.md"
        if !FileManager.default.fileExists(atPath: soulPath) {
            let displayNameForSoul = agentDisplayName.isEmpty ? agentName : agentDisplayName
            let defaultSoul = """
            # \(displayNameForSoul)

            You are a helpful AI assistant.

            ## Personality
            - Friendly and professional
            - Clear and concise in responses
            - Proactive in offering help
            """
            try? defaultSoul.write(toFile: soulPath, atomically: true, encoding: .utf8)
        }

        // Register the agent
        let addResult = await shell.run(
            "openclaw agents add \(agentName) --workspace \"\(workspacePath)\" --non-interactive"
        )

        if addResult.exitCode == 0 {
            // Set identity if display name or emoji provided
            if !agentDisplayName.isEmpty || agentEmoji != "🦞" {
                var identityCmd = "openclaw agents set-identity --agent \(agentName)"
                if !agentDisplayName.isEmpty {
                    identityCmd += " --name \"\(agentDisplayName)\""
                }
                identityCmd += " --emoji \"\(agentEmoji)\""
                await shell.run(identityCmd)
            }

            resultMessage = "Agent '\(agentName)' created successfully!"
            resultIsError = false
            onCreated?()
        } else {
            resultMessage = addResult.output.isEmpty ? "Failed to create agent" : addResult.output
            resultIsError = true
        }

        isCreating = false
    }
}

#Preview {
    AddAgentView()
}
