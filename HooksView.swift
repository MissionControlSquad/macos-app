import SwiftUI

struct HooksView: View {
    @Bindable var service: OpenClawService
    @State private var hooksOutput = ""
    @State private var isLoading = false
    @State private var actionResult = ""
    @State private var actionIsError = false
    @State private var selectedHookInfo = ""
    @State private var showHookDetail = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hooks")
                    .font(.title.bold())
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Explanation
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lifecycle Hooks")
                                    .font(.headline)
                                Text("Hooks let agents react to events like incoming messages, session start/end, and errors. Enable or disable hooks to customize agent behavior.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Hooks list
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Hooks")
                            .font(.headline)

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if hooksOutput.isEmpty {
                            Text("No hooks found. Hooks may not be configured yet.")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        } else {
                            Text(hooksOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Quick actions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hook Actions")
                            .font(.headline)

                        HStack(spacing: 12) {
                            hookActionField
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if !actionResult.isEmpty {
                        Text(actionResult)
                            .font(.callout)
                            .foregroundStyle(actionIsError ? .red : .green)
                            .padding(.horizontal)
                    }

                    // Hook detail info
                    if showHookDetail && !selectedHookInfo.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Hook Details")
                                    .font(.headline)
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

                            Text(selectedHookInfo)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
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
                        actionResult = result.exitCode == 0
                            ? "Hook '\(hookNameInput)' enabled"
                            : result.output
                        actionIsError = result.exitCode != 0
                        await refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(hookNameInput.isEmpty)

                Button("Disable") {
                    Task {
                        let result = await service.disableHook(name: hookNameInput)
                        actionResult = result.exitCode == 0
                            ? "Hook '\(hookNameInput)' disabled"
                            : result.output
                        actionIsError = result.exitCode != 0
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
