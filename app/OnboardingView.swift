import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    @State private var shell = ShellService()
    @State private var isWorking = false
    @State private var log = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, 40)
                .padding(.top, 32)
                .padding(.bottom, 16)

            Spacer()

            stepContent
                .frame(maxWidth: 480)

            Spacer()

            if !log.isEmpty {
                logView
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<OnboardingStep.totalSteps, id: \.self) { index in
                    let step = OnboardingStep(rawValue: index)!
                    let isCurrent = step == appState.currentStep
                    let isComplete = step.rawValue < appState.currentStep.rawValue

                    RoundedRectangle(cornerRadius: 2)
                        .fill(isComplete ? Color.green : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.2)))
                        .frame(height: 4)
                        .animation(.easeInOut, value: appState.currentStep)
                }
            }

            HStack {
                Text("Step \(appState.currentStep.stepNumber) of \(OnboardingStep.totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Step Content

    private var stepContent: some View {
        VStack(spacing: 24) {
            Image(systemName: appState.currentStep.icon)
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text(appState.currentStep.title)
                    .font(.largeTitle.bold())

                Text(appState.currentStep.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Group {
                switch appState.currentStep {
                case .installNode:
                    installNodeStep
                case .installOpenClaw:
                    installOpenClawStep
                case .onboard:
                    onboardStep
                }
            }

            if showError {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(32)
    }

    // MARK: - Step 1: Node.js

    private var installNodeStep: some View {
        VStack(spacing: 16) {
            actionButton("Install with Homebrew", icon: "cup.and.saucer.fill") {
                await runStep {
                    appendLog("$ brew install node")
                    let result = await shell.run("brew install node 2>&1")
                    appendLog(result.output)
                    guard result.exitCode == 0 else {
                        throw StepError.failed("Homebrew install failed. Make sure Homebrew is installed, or install Node.js manually from nodejs.org")
                    }
                    await appState.checkNode()
                    guard appState.nodeInstalled else {
                        throw StepError.failed("Node.js installation could not be verified.")
                    }
                }
            }

            manualCommandView(
                "Or install manually from nodejs.org",
                command: "brew install node"
            )

            recheckButton {
                await appState.checkNode()
            }
        }
    }

    // MARK: - Step 2: OpenClaw

    private var installOpenClawStep: some View {
        VStack(spacing: 16) {
            completedBadge("Node.js \(appState.nodeVersion)")

            actionButton("Install OpenClaw", icon: "arrow.down.circle.fill") {
                await runStep {
                    appendLog("$ curl -fsSL https://openclaw.ai/install.sh | bash")
                    appendLog("Downloading and installing...")
                    let result = await shell.run("curl -fsSL https://openclaw.ai/install.sh | bash 2>&1")
                    appendLog(result.output)

                    if result.exitCode != 0 {
                        // Fallback to npm
                        appendLog("\nCurl install failed, trying npm...")
                        appendLog("$ npm install -g openclaw@latest")
                        let npmResult = await shell.run("npm install -g openclaw@latest 2>&1")
                        appendLog(npmResult.output)
                        guard npmResult.exitCode == 0 else {
                            throw StepError.failed(
                                "Installation failed. Open Terminal and run:\ncurl -fsSL https://openclaw.ai/install.sh | bash"
                            )
                        }
                    }

                    await appState.checkOpenClaw()
                    guard appState.openclawInstalled else {
                        throw StepError.failed("OpenClaw could not be found after installation.")
                    }
                }
            }

            manualCommandView(
                "Or install from Terminal",
                command: "curl -fsSL https://openclaw.ai/install.sh | bash"
            )

            recheckButton {
                await appState.checkOpenClaw()
            }
        }
    }

    // MARK: - Step 3: Onboard

    private var onboardStep: some View {
        VStack(spacing: 16) {
            completedBadge("OpenClaw \(appState.openclawVersion)")

            Text("The onboarding wizard will walk you through setting up your AI provider, gateway, and messaging channels.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            actionButton("Launch Setup Wizard", icon: "wand.and.stars") {
                await runStep {
                    appendLog("$ openclaw onboard --install-daemon")
                    appendLog("Starting onboarding wizard...")
                    let result = await shell.run("openclaw onboard --install-daemon 2>&1")
                    appendLog(result.output)
                    guard result.exitCode == 0 else {
                        throw StepError.failed("Onboarding failed. You can run 'openclaw onboard' in Terminal instead.")
                    }
                    await appState.checkAll()
                }
            }

            manualCommandView(
                "Or run in Terminal for interactive setup",
                command: "openclaw onboard --install-daemon"
            )

            // Skip to dashboard
            Button("Skip — go to Dashboard") {
                // Mark as set up so ContentView shows dashboard
                appState.openclawInstalled = true
                appState.isChecking = false
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared Components

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
            .frame(minWidth: 220)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isWorking)
    }

    private func completedBadge(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
    }

    private func manualCommandView(_ label: String, command: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func recheckButton(check: @escaping () async -> Void) -> some View {
        Button("I already have this — recheck") {
            Task {
                isWorking = true
                showError = false
                await check()
                isWorking = false
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Output")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { log = "" }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .onChange(of: log) {
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

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
