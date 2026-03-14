import SwiftUI

struct SkillsPluginsView: View {
    @Bindable var service: OpenClawService
    @State private var selectedTab = 0
    @State private var skillsOutput = ""
    @State private var pluginsOutput = ""
    @State private var isLoading = false
    @State private var toast = ToastState()
    @State private var installSpec = ""
    @State private var showUpdateAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("Skills & Plugins")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh skills and plugins")
                }
            }
        }
        .task {
            await refresh()
        }
        .confirmationDialog(
            "Update All Plugins",
            isPresented: $showUpdateAllConfirm
        ) {
            Button("Update All", role: .destructive) {
                Task {
                    isLoading = true
                    let result = await service.runCommand("openclaw plugins update --all")
                    toast.show(
                        result.exitCode == 0 ? "All plugins updated!" : result.output,
                        isError: result.exitCode != 0
                    )
                    await refresh()
                    isLoading = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will update all installed plugins to their latest versions. Continue?")
        }
    }

    // MARK: - Skills Tab

    private var skillsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if skillsOutput.isEmpty {
                    EmptyStateView(
                        icon: "star",
                        title: "No Skills Data",
                        message: "Could not load skills. Make sure OpenClaw is running."
                    )
                } else {
                    Text(skillsOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            let result = await service.runCommand("openclaw skills check --json")
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
                    EmptyStateView(
                        icon: "puzzlepiece",
                        title: "No Plugins Data",
                        message: "Could not load plugins. Make sure OpenClaw is running."
                    )
                } else {
                    Text(pluginsOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Install plugin
                GroupBox("Install Plugin") {
                    HStack {
                        TextField("npm package or path (e.g. @openclaw/plugin-voice)", text: $installSpec)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task {
                                isLoading = true
                                let result = await service.installPlugin(spec: installSpec)
                                toast.show(
                                    result.exitCode == 0 ? "Plugin installed!" : result.output,
                                    isError: result.exitCode != 0
                                )
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
                        showUpdateAllConfirm = true
                    } label: {
                        Label("Update All", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                ToastBanner(toast: toast)
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
