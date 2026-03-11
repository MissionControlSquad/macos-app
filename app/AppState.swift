import Foundation

@MainActor
@Observable
class AppState {
    var isChecking = true
    var nodeInstalled = false
    var nodeVersion = ""
    var openclawInstalled = false
    var openclawVersion = ""
    var gatewayRunning = false

    var needsSetup: Bool {
        !openclawInstalled
    }

    /// Current onboarding step the user needs to complete
    var currentStep: OnboardingStep {
        if !nodeInstalled { return .installNode }
        if !openclawInstalled { return .installOpenClaw }
        return .onboard
    }

    private let shell = ShellService()

    func checkAll() async {
        isChecking = true
        await checkNode()
        await checkOpenClaw()
        if openclawInstalled {
            await checkGateway()
        }
        isChecking = false
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

    func checkGateway() async {
        let result = await shell.run("openclaw gateway status")
        gatewayRunning = result.exitCode == 0
            && !result.output.lowercased().contains("not running")
            && !result.output.lowercased().contains("error")
    }
}

enum OnboardingStep: Int, CaseIterable {
    case installNode = 0
    case installOpenClaw = 1
    case onboard = 2

    var title: String {
        switch self {
        case .installNode: return "Install Node.js"
        case .installOpenClaw: return "Install OpenClaw"
        case .onboard: return "Run Setup Wizard"
        }
    }

    var subtitle: String {
        switch self {
        case .installNode: return "OpenClaw requires Node.js 22 or newer."
        case .installOpenClaw: return "Install the OpenClaw CLI on your system."
        case .onboard: return "The wizard will configure your AI provider, gateway, and channels."
        }
    }

    var icon: String {
        switch self {
        case .installNode: return "shippingbox.fill"
        case .installOpenClaw: return "arrow.down.app.fill"
        case .onboard: return "wand.and.stars"
        }
    }

    var stepNumber: Int { rawValue + 1 }
    static var totalSteps: Int { allCases.count }
}

extension AppState {
    static func preview(step: OnboardingStep = .installNode) -> AppState {
        let state = AppState()
        state.isChecking = false
        switch step {
        case .installNode:
            break
        case .installOpenClaw:
            state.nodeInstalled = true
            state.nodeVersion = "v22.5.0"
        case .onboard:
            state.nodeInstalled = true
            state.openclawInstalled = true
            state.openclawVersion = "2026.3.2"
        }
        return state
    }
}
