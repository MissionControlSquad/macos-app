import Foundation

// MARK: - Agent

struct Agent: Identifiable, Codable {
    var id: String { agentId }
    let agentId: String
    let workspace: String
    let agentDir: String?
    let bindingsCount: Int?
    let isDefault: Bool?
    let routes: [String]?

    // Fields not from JSON, populated separately
    var status: String?
    var emoji: String?
    var displayName: String?

    var agentStatus: AgentStatus {
        guard let status else { return .unknown }
        return AgentStatus(rawValue: status.lowercased()) ?? .unknown
    }

    var name: String { agentId }

    enum CodingKeys: String, CodingKey {
        case agentId = "id"
        case workspace
        case agentDir
        case bindingsCount = "bindings"
        case isDefault
        case routes
    }
}

enum AgentStatus: String {
    case online = "online"
    case offline = "offline"
    case working = "working"
    case idle = "idle"
    case unknown = "unknown"

    var icon: String {
        switch self {
        case .online: return "circle.fill"
        case .working: return "bolt.circle.fill"
        case .idle: return "moon.circle.fill"
        case .offline: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

// MARK: - Gateway

struct GatewayStatus: Codable {
    let running: Bool?
    let port: Int?
    let pid: Int?
    let uptime: String?
    let version: String?
}

// MARK: - Models

struct ModelsStatus: Codable {
    let defaultModel: String?
    let fallbackModel: String?
    let providers: [ProviderStatus]?

    enum CodingKeys: String, CodingKey {
        case defaultModel = "default_model"
        case fallbackModel = "fallback_model"
        case providers
    }
}

struct ProviderStatus: Identifiable, Codable {
    var id: String { name }
    let name: String
    let authenticated: Bool?
    let models: [String]?
}

// MARK: - Command Result

struct CommandResult: Identifiable {
    let id = UUID()
    let command: String
    let output: String
    let timestamp: Date
    let exitCode: Int32
}
