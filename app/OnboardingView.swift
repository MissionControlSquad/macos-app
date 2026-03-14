import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @Bindable var appState: AppState
    @State private var shell = ShellService()
    @State private var isWorking = false
    @State private var log = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var copied = false
    @State private var waitingForTerminal = false

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
                .navigationTitle("Setup")
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Step icon and title
                        VStack(spacing: 8) {
                            Image(systemName: appState.currentStep.icon)
                                .font(.largeTitle)
                                .foregroundStyle(.accent)

                            Text(appState.currentStep.title)
                                .font(.title.bold())

                            Text(appState.currentStep.subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Step content
                        stepContent

                        // Error display
                        if showError {
                            GroupBox {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(24)
                }

                if !log.isEmpty {
                    logPanel
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.currentStep)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List {
            ForEach(0..<OnboardingStep.totalSteps, id: \.self) { index in
                let step = OnboardingStep(rawValue: index)!
                let isCurrent = step == appState.currentStep
                let isComplete = step.rawValue < appState.currentStep.rawValue

                HStack(spacing: 10) {
                    ZStack {
                        if isComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if isCurrent {
                            Image(systemName: "\(index + 1).circle.fill")
                                .foregroundStyle(.accent)
                        } else {
                            Image(systemName: "\(index + 1).circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(isCurrent ? .callout.bold() : .callout)
                            .foregroundStyle(isComplete ? .green : isCurrent ? .primary : .secondary)
                        Text(step.sidebarDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Label("Private & Local", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("All data stays on your machine.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch appState.currentStep {
        case .xcodeTools: xcodeToolsContent
        case .homebrew: homebrewContent
        case .installOpenClaw: installOpenClawContent
        case .onboard: onboardContent
        case .startGateway: startGatewayContent
        }
    }

    // MARK: - Step 1: Xcode Command Line Tools

    private var xcodeToolsContent: some View {
        VStack(spacing: 14) {
            infoRow(icon: "wrench.and.screwdriver", text: "Includes Git, compilers, and macOS build utilities")

            actionButton("Install Xcode Tools", icon: "hammer.fill") {
                await runStep {
                    appendLog("$ xcode-select --install")
                    appendLog("Opening macOS installer dialog...")
                    let result = await shell.run("xcode-select --install 2>&1")
                    appendLog(result.output)
                    appendLog("Waiting for installation to complete (this may take several minutes)...")
                    for _ in 0..<120 {
                        try await Task.sleep(for: .seconds(5))
                        await appState.checkXcodeTools()
                        if appState.xcodeToolsInstalled {
                            appendLog("Xcode Command Line Tools installed successfully.")
                            return
                        }
                    }
                    throw StepError.failed("Timed out. Complete the system dialog and click Recheck below.")
                }
            }

            terminalBlock("xcode-select --install")

            recheckButton("I already have Xcode Tools") {
                await appState.checkXcodeTools()
            }
        }
    }

    // MARK: - Step 2: Homebrew

    private var homebrewContent: some View {
        VStack(spacing: 14) {
            doneBadge("Xcode Tools")

            infoRow(icon: "shippingbox", text: "Homebrew is used to install Node.js and other dependencies")

            if waitingForTerminal {
                waitingForTerminalView(
                    message: "Complete the Homebrew installation in Terminal, then come back here.",
                    recheckAction: {
                        await appState.checkBrew()
                        if appState.brewInstalled {
                            waitingForTerminal = false
                        }
                    }
                )
            } else {
                actionButton("Install Homebrew", icon: "mug.fill") {
                    shell.openInTerminal("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                    waitingForTerminal = true
                    await pollUntil {
                        await appState.checkBrew()
                        return appState.brewInstalled
                    }
                    waitingForTerminal = false
                }

                terminalBlock("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")

                recheckButton("I already have Homebrew") {
                    await appState.checkBrew()
                }
            }
        }
    }

    // MARK: - Step 3: Install OpenClaw

    private var installOpenClawContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                doneBadge("Xcode Tools")
                doneBadge(appState.brewVersion.isEmpty ? "Homebrew" : appState.brewVersion)
            }

            infoRow(icon: "cube.box", text: "Installs OpenClaw CLI, Node.js 22+, and all dependencies")

            if waitingForTerminal {
                waitingForTerminalView(
                    message: "Complete the OpenClaw installation in Terminal, then come back here.",
                    recheckAction: {
                        await appState.checkNode()
                        await appState.checkOpenClaw()
                        if appState.openclawInstalled {
                            waitingForTerminal = false
                        }
                    }
                )
            } else {
                actionButton("Install OpenClaw", icon: "arrow.down.circle.fill") {
                    shell.openInTerminal("curl -fsSL https://openclaw.ai/install.sh | bash")
                    waitingForTerminal = true
                    await pollUntil {
                        await appState.checkNode()
                        await appState.checkOpenClaw()
                        return appState.openclawInstalled
                    }
                    waitingForTerminal = false
                }

                terminalBlock("curl -fsSL https://openclaw.ai/install.sh | bash")

                recheckButton("I already have OpenClaw") {
                    await appState.checkNode()
                    await appState.checkOpenClaw()
                }
            }
        }
    }

    // MARK: - Step 4: Onboard

    private var onboardContent: some View {
        VStack(spacing: 14) {
            doneBadge("OpenClaw \(appState.openclawVersion)")

            Text("The wizard will walk you through connecting your AI provider keys, configuring the gateway, and setting up channels.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if waitingForTerminal {
                waitingForTerminalView(
                    message: "Complete the setup wizard in Terminal, then come back here.",
                    recheckAction: {
                        await appState.checkOnboarded()
                        await appState.checkGateway()
                        if appState.onboarded {
                            waitingForTerminal = false
                        }
                    }
                )
            } else {
                actionButton("Launch Setup Wizard", icon: "wand.and.stars") {
                    shell.openInTerminal("openclaw onboard --install-daemon")
                    waitingForTerminal = true
                    await pollUntil {
                        await appState.checkOnboarded()
                        return appState.onboarded
                    }
                    waitingForTerminal = false
                }

                terminalBlock("openclaw onboard --install-daemon")

                recheckButton("I've already run onboard") {
                    await appState.checkOnboarded()
                    await appState.checkGateway()
                }
            }
        }
    }

    // MARK: - Step 5: Start Gateway

    private var startGatewayContent: some View {
        VStack(spacing: 14) {
            doneBadge("OpenClaw \(appState.openclawVersion)")

            Text("The gateway connects your agents to AI providers and channels. It runs as a background service.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            actionButton("Start Gateway", icon: "bolt.fill") {
                await runStep {
                    appendLog("$ openclaw gateway start")
                    let result = await shell.run("openclaw gateway start 2>&1")
                    appendLog(result.output)
                    try await Task.sleep(for: .seconds(2))
                    await appState.checkGateway()
                    guard appState.gatewayRunning else {
                        throw StepError.failed("Gateway didn't start. Check the output or run 'openclaw gateway start' in Terminal.")
                    }
                }
            }

            terminalBlock("openclaw gateway start")

            Button("Skip to Dashboard") {
                appState.gatewayRunning = true
                appState.onboarded = true
                appState.isChecking = false
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Components

    private func actionButton(
        _ title: String,
        icon: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                }
                Text(isWorking ? "Working..." : title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isWorking)
    }

    private func doneBadge(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.green.opacity(0.1))
            .clipShape(Capsule())
    }

    private func terminalBlock(_ command: String) -> some View {
        GroupBox {
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.secondary)
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func recheckButton(_ label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                isWorking = true
                showError = false
                await action()
                isWorking = false
            }
        } label: {
            Label(label, systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
    }

    private func waitingForTerminalView(
        message: String,
        recheckAction: @escaping () async -> Void
    ) -> some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill")
                        .font(.title3)
                        .foregroundStyle(.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for Terminal")
                            .font(.headline)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ProgressView()
                        .controlSize(.small)
                }

                HStack(spacing: 12) {
                    recheckButton("Recheck now") {
                        await recheckAction()
                    }

                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    } label: {
                        Label("Open Terminal", systemImage: "macwindow")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Log Panel

    private var logPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Terminal Output", systemImage: "terminal")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { log = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("logEnd")
                    }
                    .onChange(of: log) {
                        proxy.scrollTo("logEnd", anchor: .bottom)
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    // MARK: - Helpers

    private func pollUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<120 {
            try? await Task.sleep(for: .seconds(5))
            if await condition() { return }
        }
    }

    private func runStep(_ work: () async throws -> Void) async {
        isWorking = true
        showError = false
        errorMessage = ""
        do {
            try await work()
        } catch let error as StepError {
            showError = true
            errorMessage = error.message
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func appendLog(_ text: String) {
        if !log.isEmpty { log += "\n" }
        log += text
    }
}

private enum StepError: Error {
    case failed(String)
    var message: String {
        switch self {
        case .failed(let msg): return msg
        }
    }
}

// MARK: - Previews

#Preview("Step 1 - Xcode Tools") {
    OnboardingView(appState: .preview(step: .xcodeTools))
        .frame(width: 840, height: 600)
}

#Preview("Step 2 - Homebrew") {
    OnboardingView(appState: .preview(step: .homebrew))
        .frame(width: 840, height: 600)
}

#Preview("Step 3 - OpenClaw") {
    OnboardingView(appState: .preview(step: .installOpenClaw))
        .frame(width: 840, height: 600)
}

#Preview("Step 4 - Onboard") {
    OnboardingView(appState: .preview(step: .onboard))
        .frame(width: 840, height: 600)
}

#Preview("Step 5 - Gateway") {
    OnboardingView(appState: .preview(step: .startGateway))
        .frame(width: 840, height: 600)
}
