import SwiftUI

struct HooksView: View {
    @Bindable var service: OpenClawService
    @State private var hooksOutput = ""
    @State private var isLoading = false
    @State private var toast = ToastState()
    @State private var selectedHookInfo = ""
    @State private var showHookDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Explanation
                GroupBox {
                    HStack(spacing: 8) {
                        Image(systemName: "link.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("Hooks let agents react to events like incoming messages, session start/end, and errors. Enable or disable hooks to customize agent behavior.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Hooks list
                GroupBox("Available Hooks") {
                    if isLoading {
                        LoadingStateView(message: "Loading hooks...", compact: true)
                    } else if hooksOutput.isEmpty {
                        Text("No hooks found. Hooks may not be configured yet.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(hooksOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Quick actions
                GroupBox("Hook Actions") {
                    hookActionField
                }

                ToastBanner(toast: toast)

                // Hook detail info
                if showHookDetail && !selectedHookInfo.isEmpty {
                    GroupBox {
                        Text(selectedHookInfo)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        HStack {
                            Text("Hook Details")
                            Spacer()
                            Button {
                                showHookDetail = false
                                selectedHookInfo = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Hooks")
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
                    .help("Refresh hooks")
                }
            }
        }
        .task {
            await refresh()
        }
    }

    // MARK: - Hook Action Field

    @State private var hookNameInput = ""

    private var hookActionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Hook name", text: $hookNameInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack(spacing: 8) {
                Button("Enable") {
                    Task {
                        let result = await service.enableHook(name: hookNameInput)
                        toast.show(
                            result.exitCode == 0 ? "Hook '\(hookNameInput)' enabled" : result.output,
                            isError: result.exitCode != 0
                        )
                        await refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(hookNameInput.isEmpty)

                Button("Disable") {
                    Task {
                        let result = await service.disableHook(name: hookNameInput)
                        toast.show(
                            result.exitCode == 0 ? "Hook '\(hookNameInput)' disabled" : result.output,
                            isError: result.exitCode != 0
                        )
                        await refresh()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(hookNameInput.isEmpty)

                Button("Info") {
                    Task {
                        let result = await service.hookInfo(name: hookNameInput)
                        selectedHookInfo = result.output
                        showHookDetail = true
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(hookNameInput.isEmpty)
            }
        }
    }

    // MARK: - Helpers

    private func refresh() async {
        isLoading = true
        let result = await service.fetchHooks()
        hooksOutput = result.output
        isLoading = false
    }
}
