import Foundation

enum CheckItem: String, CaseIterable {
    case xcodeTools = "Xcode Command Line Tools"
    case homebrew = "Homebrew"
    case node = "Node.js"
    case openclaw = "OpenClaw CLI"
    case onboarded = "Setup Configuration"
    case gateway = "Gateway Service"

    var icon: String {
        switch self {
        case .xcodeTools: return "hammer.fill"
        case .homebrew: return "mug.fill"
        case .node: return "circle.grid.3x3.fill"
        case .openclaw: return "cube.box.fill"
        case .onboarded: return "checkmark.seal.fill"
        case .gateway: return "bolt.fill"
        }
    }
}

enum CheckStatus {
    case pending
    case checking
    case passed
    case failed
}

@MainActor
@Observable
class AppState {
    var isChecking = true

    // Dependency checks
    var xcodeToolsInstalled = false
    var brewInstalled = false
    var brewVersion = ""
    var nodeInstalled = false
    var nodeVersion = ""
    var openclawInstalled = false
    var openclawVersion = ""
    var gatewayRunning = false
    var onboarded = false

    // Check progress tracking
    var checkStatuses: [CheckItem: CheckStatus] = [:]
    var currentCheck: CheckItem?

    var needsSetup: Bool {
        !openclawInstalled || !onboarded || !gatewayRunning
    }

    /// Current onboarding step the user needs to complete
    var currentStep: OnboardingStep {
        if !xcodeToolsInstalled { return .xcodeTools }
        if !brewInstalled { return .homebrew }
        if !openclawInstalled { return .installOpenClaw }
        if !onboarded { return .onboard }
        if !gatewayRunning { return .startGateway }
        return .startGateway
    }

    private let shell = ShellService()

    func checkAll() async {
        isChecking = true
        // Initialize all as pending
        for item in CheckItem.allCases {
            checkStatuses[item] = .pending
        }

        await runCheck(.xcodeTools) { await self.checkXcodeTools(); return self.xcodeToolsInstalled }
        await runCheck(.homebrew) { await self.checkBrew(); return self.brewInstalled }
        await runCheck(.node) { await self.checkNode(); return self.nodeInstalled }
        await runCheck(.openclaw) { await self.checkOpenClaw(); return self.openclawInstalled }

        if openclawInstalled {
            await runCheck(.onboarded) { await self.checkOnboarded(); return self.onboarded }
            await runCheck(.gateway) { await self.checkGateway(); return self.gatewayRunning }
        } else {
            // Mark remaining as failed since openclaw is required
            checkStatuses[.onboarded] = .failed
            checkStatuses[.gateway] = .failed
        }

        currentCheck = nil
        isChecking = false
    }

    private func runCheck(_ item: CheckItem, _ check: () async -> Bool) async {
        currentCheck = item
        checkStatuses[item] = .checking
        let passed = await check()
        checkStatuses[item] = passed ? .passed : .failed
    }

    func checkXcodeTools() async {
        let result = await shell.run("xcode-select -p")
        xcodeToolsInstalled = result.exitCode == 0
    }

    func checkBrew() async {
        let result = await shell.run("brew --version")
        if result.exitCode == 0 {
            brewInstalled = true
            // Extract first line, e.g. "Homebrew 4.3.5"
            brewVersion = result.output
                .components(separatedBy: "\n").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            brewInstalled = false
            brewVersion = ""
        }
    }

    func checkNode() async {
        let result = await shell.run("node --version")
        nodeInstalled = result.exitCode == 0
        if nodeInstalled {
            nodeVersion = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func checkOpenClaw() async {
        let result = await shell.run("openclaw --version")
        if result.exitCode == 0 {
            openclawInstalled = true
            openclawVersion = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            openclawInstalled = false
            openclawVersion = ""
        }
    }

    /// Check if onboarding has been completed (gateway config exists)
    func checkOnboarded() async {
        let result = await shell.run("openclaw gateway status")
        // If gateway status returns something meaningful, onboard was run
        let output = result.output.lowercased()
        onboarded = result.exitCode == 0 || output.contains("port") || output.contains("running") || output.contains("stopped")
    }

    func checkGateway() async {
        let result = await shell.run("openclaw gateway status")
        gatewayRunning = result.exitCode == 0
            && !result.output.lowercased().contains("not running")
            && !result.output.lowercased().contains("error")
    }
}

enum OnboardingStep: Int, CaseIterable {
    case xcodeTools = 0
    case homebrew = 1
    case installOpenClaw = 2
    case onboard = 3
    case startGateway = 4

    var title: String {
        switch self {
        case .xcodeTools: return "Xcode Command Line Tools"
        case .homebrew: return "Install Homebrew"
        case .installOpenClaw: return "Install OpenClaw"
        case .onboard: return "Run Setup Wizard"
        case .startGateway: return "Start Gateway"
        }
    }

    var subtitle: String {
        switch self {
        case .xcodeTools: return "Required build tools for macOS. Includes Git, compilers, and developer utilities."
        case .homebrew: return "The missing package manager for macOS. Needed to install Node.js and other dependencies."
        case .installOpenClaw: return "Installs the OpenClaw CLI, Node.js 22+, and all required dependencies."
        case .onboard: return "Configure your AI provider, gateway, and messaging channels."
        case .startGateway: return "Start the gateway service so your agents can communicate."
        }
    }

    var icon: String {
        switch self {
        case .xcodeTools: return "hammer.fill"
        case .homebrew: return "mug.fill"
        case .installOpenClaw: return "arrow.down.circle.fill"
        case .onboard: return "wand.and.stars"
        case .startGateway: return "bolt.fill"
        }
    }

    /// Short description shown in the sidebar step list
    var sidebarDescription: String {
        switch self {
        case .xcodeTools: return "Git, compilers & build tools"
        case .homebrew: return "macOS package manager"
        case .installOpenClaw: return "CLI, Node.js & runtime"
        case .onboard: return "Provider, gateway & channels"
        case .startGateway: return "Launch the agent gateway"
        }
    }

    var stepNumber: Int { rawValue + 1 }
    static var totalSteps: Int { allCases.count }
}

extension AppState {
    static func preview(step: OnboardingStep = .xcodeTools) -> AppState {
        let state = AppState()
        state.isChecking = false
        switch step {
        case .xcodeTools:
            break
        case .homebrew:
            state.xcodeToolsInstalled = true
        case .installOpenClaw:
            state.xcodeToolsInstalled = true
            state.brewInstalled = true
            state.brewVersion = "Homebrew 4.3.5"
        case .onboard:
            state.xcodeToolsInstalled = true
            state.brewInstalled = true
            state.brewVersion = "Homebrew 4.3.5"
            state.nodeInstalled = true
            state.nodeVersion = "v22.5.0"
            state.openclawInstalled = true
            state.openclawVersion = "OpenClaw 2026.3.8"
        case .startGateway:
            state.xcodeToolsInstalled = true
            state.brewInstalled = true
            state.brewVersion = "Homebrew 4.3.5"
            state.nodeInstalled = true
            state.nodeVersion = "v22.5.0"
            state.openclawInstalled = true
            state.openclawVersion = "OpenClaw 2026.3.8"
            state.onboarded = true
        }
        return state
    }
}
