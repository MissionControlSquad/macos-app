import SwiftUI

struct SkillsPluginsView: View {
    @Bindable var service: OpenClawService
    @State private var selectedTab = 0
    @State private var skillsOutput = ""
    @State private var pluginsOutput = ""
    @State private var isLoading = false
    @State private var actionResult = ""
    @State private var actionIsError = false
    @State private var installSpec = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Skills & Plugins")
                    .font(.title.bold())
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            Divider()

            // Tab toggle
            Picker("", selection: $selectedTab) {
                Text("Skills").tag(0)
                Text("Plugins").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if selectedTab == 0 {
                skillsTab
            } else {
                pluginsTab
            }
        }
        .task {
            await refresh()
        }
    }

    // MARK: - Skills Tab

    private var skillsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if skillsOutput.isEmpty {
                    ContentUnavailableView {
                        Label("No Skills Data", systemImage: "star")
                    } description: {
                        Text("Could not load skills. Make sure OpenClaw is running.")
                    }
                } else {
                    Text(skillsOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            let result = await service.runCommand("openclaw skills check")
                            skillsOutput = result.output
                        }
                    } label: {
                        Label("Check Eligibility", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            let result = await service.fetchSkills()
                            skillsOutput = result.output
                        }
                    } label: {
                        Label("List Eligible", systemImage: "list.star")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }

    // MARK: - Plugins Tab

    private var pluginsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if pluginsOutput.isEmpty {
                    ContentUnavailableView {
                        Label("No Plugins Data", systemImage: "puzzlepiece")
                    } description: {
                        Text("Could not load plugins. Make sure OpenClaw is running.")
                    }
                } else {
                    Text(pluginsOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Install plugin
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install Plugin")
                        .font(.headline)

                    HStack {
                        TextField("npm package or path (e.g. @openclaw/plugin-voice)", text: $installSpec)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task {
                                isLoading = true
                                let result = await service.installPlugin(spec: installSpec)
                                actionResult = result.exitCode == 0
                                    ? "Plugin installed!"
                                    : result.output
                                actionIsError = result.exitCode != 0
                                installSpec = ""
                                await refresh()
                                isLoading = false
                            }
                        } label: {
                            Label("Install", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(installSpec.isEmpty)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Actions
                HStack(spacing: 12) {
                    Button {
                        Task {
                            let result = await service.runCommand("openclaw plugins doctor")
                            pluginsOutput = result.output
                        }
                    } label: {
                        Label("Diagnose", systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            isLoading = true
                            let result = await service.runCommand("openclaw plugins update --all")
                            actionResult = result.exitCode == 0
                                ? "All plugins updated!"
                                : result.output
                            actionIsError = result.exitCode != 0
                            await refresh()
                            isLoading = false
                        }
                    } label: {
                        Label("Update All", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                if !actionResult.isEmpty {
                    Text(actionResult)
                        .font(.callout)
                        .foregroundStyle(actionIsError ? .red : .green)
                }
            }
            .padding()
        }
    }

    private func refresh() async {
        isLoading = true
        let skills = await service.fetchSkills()
        skillsOutput = skills.output
        let plugins = await service.fetchPlugins()
        pluginsOutput = plugins.output
        isLoading = false
    }
}
