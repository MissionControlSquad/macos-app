import SwiftUI

struct SetupView: View {
    @State private var shell = ShellService()
    @State private var installStatus: InstallStatus = .checking
    @State private var installLog = ""
    @State private var nodeInstalled = false
    @State private var openclawInstalled = false

    enum InstallStatus {
        case checking, notInstalled, installing, installed, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                prerequisitesSection
                Divider()
                installSection
                Divider()
                initSection
                if !installLog.isEmpty {
                    Divider()
                    logSection
                }
            }
            .padding()
        }
        .navigationTitle("Setup")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if installStatus == .checking || installStatus == .installing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task {
            await checkPrerequisites()
        }
    }

    // MARK: - Prerequisites

    private var prerequisitesSection: some View {
        GroupBox("Prerequisites") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: nodeInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(nodeInstalled ? Color.green : Color.red)
                    Text("Node.js 22+")
                    Spacer()
                    if !nodeInstalled {
                        Button("Install with Homebrew") {
                            Task {
                                appendLog("Installing Node.js via Homebrew...")
                                let result = await shell.run("brew install node")
                                appendLog(result.output)
                                await checkPrerequisites()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: openclawInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(openclawInstalled ? Color.green : Color.red)
                    Text("OpenClaw CLI")
                    Spacer()
                    if openclawInstalled {
                        Text("Installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Install

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install OpenClaw")
                .font(.headline)

            Text("This will install the latest version of OpenClaw using npx.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text("npx openclaw@latest")
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(.quinary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Button {
                    Task { await installOpenClaw() }
                } label: {
                    Label(
                        openclawInstalled ? "Reinstall" : "Install",
                        systemImage: "arrow.down.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(installStatus == .installing || !nodeInstalled)
            }

            if installStatus == .failed {
                Text("Installation failed. Check the log below for details.")
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
    }

    // MARK: - Init Project

    private var initSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Initialize Project")
                .font(.headline)

            Text("Create a new OpenClaw project with default agent configuration.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                Task { await initProject() }
            } label: {
                Label("Run Onboarding Wizard", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!openclawInstalled || installStatus == .installing)

            Button {
                Task {
                    appendLog("Running: npx openclaw init")
                    let result = await shell.run("npx openclaw init")
                    appendLog(result.output)
                }
            } label: {
                Label("Quick Init (npx openclaw init)", systemImage: "bolt.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!openclawInstalled || installStatus == .installing)
        }
    }

    // MARK: - Log

    private var logSection: some View {
        GroupBox {
            ScrollView {
                Text(installLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
        } label: {
            HStack {
                Text("Log")
                Spacer()
                Button("Clear") { installLog = "" }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func checkPrerequisites() async {
        installStatus = .checking

        let nodeResult = await shell.run("node --version")
        nodeInstalled = nodeResult.exitCode == 0

        let clawResult = await shell.run("which openclaw")
        openclawInstalled = clawResult.exitCode == 0

        installStatus = openclawInstalled ? .installed : .notInstalled
    }

    private func installOpenClaw() async {
        installStatus = .installing
        appendLog("Installing OpenClaw...")
        let result = await shell.run("npm install -g openclaw@latest")
        appendLog(result.output)

        if result.exitCode == 0 {
            installStatus = .installed
            openclawInstalled = true
            appendLog("OpenClaw installed successfully!")
        } else {
            installStatus = .failed
            appendLog("Installation failed with exit code \(result.exitCode)")
        }
    }

    private func initProject() async {
        appendLog("Running onboarding wizard...")
        let result = await shell.run("npx openclaw onboard --non-interactive")
        appendLog(result.output)
    }

    private func appendLog(_ text: String) {
        if !installLog.isEmpty { installLog += "\n" }
        installLog += text
    }
}

#Preview {
    SetupView()
}
