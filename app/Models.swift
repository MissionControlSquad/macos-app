import Foundation

// MARK: - Agent

struct Agent: Identifiable, Codable, Hashable {
    var id: String { agentId }
    let agentId: String
    /// Workspace path — present in CLI response, absent in gateway response
    var workspace: String { _workspace ?? "" }
    private let _workspace: String?
    let agentDir: String?
    let model: String?
    let bindingsCount: Int?
    let isDefault: Bool?
    let routes: [String]?
    /// Agent display name from gateway
    private let _name: String?

    // Fields not from JSON, populated separately
    var status: String?
    var emoji: String?
    var displayName: String?

    var agentStatus: AgentStatus {
        guard let status else { return .unknown }
        return AgentStatus(rawValue: status.lowercased()) ?? .unknown
    }

    var name: String { _name ?? agentId }

    enum CodingKeys: String, CodingKey {
        case agentId = "id"
        case _workspace = "workspace"
        case agentDir
        case model
        case bindingsCount = "bindings"
        case isDefault
        case routes
        case _name = "name"
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
    let service: GatewayService?
    let gateway: GatewayConfig?
    let port: GatewayPort?
    let rpc: GatewayRPC?

    /// True when the service process is running AND rpc is responding
    var running: Bool {
        rpc?.ok == true
    }

    /// True when the process is running but rpc may not be ready yet
    var processRunning: Bool {
        service?.runtime?.status == "running"
    }

    var gatewayPort: Int? {
        gateway?.port
    }

    var pid: Int? {
        service?.runtime?.pid
    }

    var lastError: String? {
        service?.configAudit?.issues?.first
    }
}

struct GatewayService: Codable {
    let label: String?
    let loaded: Bool?
    let runtime: GatewayRuntime?
    let configAudit: GatewayConfigAudit?
}

struct GatewayConfigAudit: Codable {
    let ok: Bool?
    let issues: [String]?
}

struct GatewayRuntime: Codable {
    let status: String?
    let state: String?
    let pid: Int?
}

struct GatewayConfig: Codable {
    let bindMode: String?
    let bindHost: String?
    let port: Int?
    let probeUrl: String?
    let probeNote: String?
}

struct GatewayPort: Codable {
    let port: Int?
    let status: String?
}

struct GatewayRPC: Codable {
    let ok: Bool?
    let error: String?
    let url: String?
}

// MARK: - Models

struct ModelsStatus: Codable {
    let defaultModel: String?
    let resolvedDefault: String?
    let fallbacks: [String]?
    let imageModel: String?
    let imageFallbacks: [String]?
    let allowed: [String]?
    let auth: ModelsAuth?

    /// Convenience: list of provider statuses from auth.oauth.providers
    var providers: [ProviderStatus] {
        auth?.oauth?.providers ?? []
    }
}

struct ModelsAuth: Codable {
    let storePath: String?
    let missingProvidersInUse: [String]?
    let oauth: ModelsOAuth?
}

struct ModelsOAuth: Codable {
    let providers: [ProviderStatus]?
}

struct ProviderStatus: Identifiable, Codable {
    var id: String { provider }
    let provider: String
    let status: String?
    let profiles: [AuthProfile]?

    /// Whether this provider has valid auth configured
    var authenticated: Bool {
        status == "ok" || status == "valid"
    }

    var name: String { provider }
}

struct AuthProfile: Identifiable, Codable {
    var id: String { profileId ?? type ?? UUID().uuidString }
    let profileId: String?
    let type: String?
    let status: String?
}

// MARK: - Model Catalog (from openclaw models list --all --json)

struct ModelCatalogResponse: Codable {
    let count: Int?
    let models: [CatalogModel]?
}

struct CatalogModel: Identifiable, Codable {
    var id: String { modelKey }
    /// CLI uses "key", gateway uses "id" — we normalize into modelKey
    let key: String?
    let name: String?
    /// Gateway returns "id", CLI returns "key"
    private let _gatewayId: String?
    /// Gateway returns provider as a top-level field
    private let _provider: String?

    /// Stable key: prefers CLI `key`, then gateway `id`
    var modelKey: String {
        key ?? _gatewayId ?? ""
    }

    /// Provider prefix extracted from the key, or from gateway's provider field
    var provider: String {
        if let p = _provider, !p.isEmpty { return p }
        return modelKey.components(separatedBy: "/").first ?? modelKey
    }

    /// Display label: name if present, otherwise the part after the provider prefix
    var displayLabel: String {
        if let name, !name.isEmpty { return name }
        let parts = modelKey.components(separatedBy: "/")
        return parts.dropFirst().joined(separator: "/")
    }

    enum CodingKeys: String, CodingKey {
        case key, name
        case _gatewayId = "id"
        case _provider = "provider"
    }
}

// MARK: - Static Model Catalog

/// Hardcoded provider → model catalog so the pickers always have data,
/// even when the CLI / gateway / cache are all unavailable.
enum StaticModelCatalog {

    /// (provider, modelKey, displayName)
    private static let entries: [(String, String, String)] = [
        // Anthropic
        ("anthropic", "anthropic/claude-opus-4-0-20250514", "Claude Opus 4"),
        ("anthropic", "anthropic/claude-sonnet-4-6-20250514", "Claude Sonnet 4.6"),
        ("anthropic", "anthropic/claude-sonnet-4-20250514", "Claude Sonnet 4"),
        ("anthropic", "anthropic/claude-haiku-4-20250514", "Claude Haiku 4"),
        ("anthropic", "anthropic/claude-3.5-sonnet-20241022", "Claude 3.5 Sonnet"),
        ("anthropic", "anthropic/claude-3.5-haiku-20241022", "Claude 3.5 Haiku"),
        ("anthropic", "anthropic/claude-3-opus-20240229", "Claude 3 Opus"),
        // OpenAI
        ("openai", "openai/gpt-4.1", "GPT-4.1"),
        ("openai", "openai/gpt-4.1-mini", "GPT-4.1 Mini"),
        ("openai", "openai/gpt-4.1-nano", "GPT-4.1 Nano"),
        ("openai", "openai/gpt-4o", "GPT-4o"),
        ("openai", "openai/gpt-4o-mini", "GPT-4o Mini"),
        ("openai", "openai/o3", "o3"),
        ("openai", "openai/o3-mini", "o3 Mini"),
        ("openai", "openai/o4-mini", "o4 Mini"),
        ("openai", "openai/gpt-4-turbo", "GPT-4 Turbo"),
        // Google
        ("google", "google/gemini-2.5-pro", "Gemini 2.5 Pro"),
        ("google", "google/gemini-2.5-flash", "Gemini 2.5 Flash"),
        ("google", "google/gemini-2.0-flash", "Gemini 2.0 Flash"),
        ("google", "google/gemini-1.5-pro", "Gemini 1.5 Pro"),
        ("google", "google/gemini-1.5-flash", "Gemini 1.5 Flash"),
        // Mistral
        ("mistral", "mistral/mistral-large-latest", "Mistral Large"),
        ("mistral", "mistral/mistral-medium-latest", "Mistral Medium"),
        ("mistral", "mistral/mistral-small-latest", "Mistral Small"),
        ("mistral", "mistral/codestral-latest", "Codestral"),
        ("mistral", "mistral/pixtral-large-latest", "Pixtral Large"),
        // Groq
        ("groq", "groq/llama-3.3-70b-versatile", "Llama 3.3 70B"),
        ("groq", "groq/llama-3.1-8b-instant", "Llama 3.1 8B"),
        ("groq", "groq/mixtral-8x7b-32768", "Mixtral 8x7B"),
        ("groq", "groq/gemma2-9b-it", "Gemma 2 9B"),
        // Cohere
        ("cohere", "cohere/command-r-plus", "Command R+"),
        ("cohere", "cohere/command-r", "Command R"),
        ("cohere", "cohere/command-a", "Command A"),
        // DeepSeek
        ("deepseek", "deepseek/deepseek-chat", "DeepSeek Chat (V3)"),
        ("deepseek", "deepseek/deepseek-reasoner", "DeepSeek Reasoner (R1)"),
        ("deepseek", "deepseek/deepseek-coder", "DeepSeek Coder"),
        // xAI
        ("xai", "xai/grok-3", "Grok 3"),
        ("xai", "xai/grok-3-mini", "Grok 3 Mini"),
        ("xai", "xai/grok-2", "Grok 2"),
        // Meta (via together / fireworks)
        ("together", "together/meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo", "Llama 3.1 405B"),
        ("together", "together/meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo", "Llama 3.1 70B"),
        ("together", "together/meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo", "Llama 3.1 8B"),
        // Fireworks
        ("fireworks", "fireworks/accounts/fireworks/models/llama-v3p1-405b-instruct", "Llama 3.1 405B"),
        ("fireworks", "fireworks/accounts/fireworks/models/llama-v3p1-70b-instruct", "Llama 3.1 70B"),
        // Perplexity
        ("perplexity", "perplexity/sonar-pro", "Sonar Pro"),
        ("perplexity", "perplexity/sonar", "Sonar"),
        // Ollama (local)
        ("ollama", "ollama/llama3.2", "Llama 3.2"),
        ("ollama", "ollama/llama3.1", "Llama 3.1"),
        ("ollama", "ollama/mistral", "Mistral"),
        ("ollama", "ollama/codellama", "Code Llama"),
        ("ollama", "ollama/phi3", "Phi-3"),
        ("ollama", "ollama/gemma2", "Gemma 2"),
        // Amazon Bedrock
        ("bedrock", "bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0", "Claude 3.5 Sonnet (Bedrock)"),
        ("bedrock", "bedrock/anthropic.claude-3-opus-20240229-v1:0", "Claude 3 Opus (Bedrock)"),
        ("bedrock", "bedrock/amazon.nova-pro-v1:0", "Amazon Nova Pro"),
        ("bedrock", "bedrock/amazon.nova-lite-v1:0", "Amazon Nova Lite"),
        // Azure OpenAI
        ("azure", "azure/gpt-4o", "GPT-4o (Azure)"),
        ("azure", "azure/gpt-4o-mini", "GPT-4o Mini (Azure)"),
        ("azure", "azure/gpt-4-turbo", "GPT-4 Turbo (Azure)"),
        // OpenRouter
        ("openrouter", "openrouter/anthropic/claude-3.5-sonnet", "Claude 3.5 Sonnet"),
        ("openrouter", "openrouter/openai/gpt-4o", "GPT-4o"),
        ("openrouter", "openrouter/google/gemini-2.0-flash-001", "Gemini 2.0 Flash"),
        ("openrouter", "openrouter/meta-llama/llama-3.1-405b-instruct", "Llama 3.1 405B"),
    ]

    static let allModels: [CatalogModel] = {
        let json = entries.map { (provider, key, name) -> [String: String] in
            ["key": key, "name": name, "provider": provider]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let models = try? JSONDecoder().decode([CatalogModel].self, from: data) else {
            return []
        }
        return models
    }()

    static var providers: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for m in allModels {
            if seen.insert(m.provider).inserted {
                result.append(m.provider)
            }
        }
        return result.sorted()
    }
}

// MARK: - Global Model Catalog Store

/// App-wide singleton that merges a built-in static catalog with dynamic
/// data from the CLI / gateway / disk cache.
@MainActor
@Observable
class ModelCatalogStore {
    static let shared = ModelCatalogStore()

    /// Dynamic models fetched from CLI/gateway (may be empty).
    var dynamicModels: [CatalogModel] = []
    var isLoading = false
    /// Debug log visible in the Models view to diagnose loading issues
    var debugLog: String = ""

    /// Optional gateway reference for WebSocket-first fetching
    var gateway: GatewayWebSocket?

    /// Merged models: dynamic first (if any), then bundled catalog as fallback.
    var models: [CatalogModel] {
        if dynamicModels.isEmpty {
            return StaticModelCatalog.allModels
        }
        return dynamicModels
    }

    /// Sorted list of unique provider names
    var providers: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for m in models {
            if seen.insert(m.provider).inserted {
                result.append(m.provider)
            }
        }
        return result.sorted()
    }

    /// Models for a specific provider
    func models(for provider: String) -> [CatalogModel] {
        models.filter { $0.provider == provider }
    }

    private let shell = ShellService()
    private var fetchTask: Task<Void, Never>?

    private init() {}

    private func log(_ msg: String) {
        let ts = Date().formatted(date: .omitted, time: .standard)
        debugLog += "[\(ts)] \(msg)\n"
        print("[ModelCatalog] \(msg)")
    }

    // MARK: - Cache

    private static var cacheURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw")
            .appendingPathComponent("cache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("model-catalog.json")
    }

    /// Load from disk cache synchronously (instant on subsequent launches).
    func loadFromCache() {
        let url = Self.cacheURL
        log("Loading cache from: \(url.path)")
        guard let data = try? Data(contentsOf: url) else {
            log("No cache file found — using built-in static catalog (\(StaticModelCatalog.allModels.count) models)")
            return
        }
        log("Cache file size: \(data.count) bytes")
        guard let response = try? JSONDecoder().decode(ModelCatalogResponse.self, from: data) else {
            log("Failed to decode cache JSON — using built-in static catalog")
            return
        }
        let loaded = response.models ?? []
        dynamicModels = loaded
        log("Loaded \(loaded.count) models from cache, \(providers.count) providers")
    }

    /// Load cache first, then refresh from gateway/CLI in background.
    /// Call this once at app startup.
    func loadAndRefresh() {
        log("loadAndRefresh() called, dynamicModels.count=\(dynamicModels.count)")
        if dynamicModels.isEmpty {
            loadFromCache()
        }
        guard fetchTask == nil else {
            log("Fetch already in progress, skipping")
            return
        }
        log("Starting background fetch...")
        fetchTask = Task {
            await refreshFromSource()
            fetchTask = nil
        }
    }

    /// Force refresh (for manual refresh buttons).
    func refresh() {
        log("Manual refresh triggered")
        fetchTask?.cancel()
        fetchTask = Task {
            await refreshFromSource()
            fetchTask = nil
        }
    }

    /// Try CLI for the full catalog, fall back to gateway (which only returns configured models)
    private func refreshFromSource() async {
        isLoading = true
        defer { isLoading = false }

        // CLI provides the full model catalog (781+ models)
        log("Running: openclaw models list --all --json")

        // Use a timeout so the spinner doesn't hang forever if the CLI is missing/stuck
        let result: CommandResult? = await withTaskGroup(of: CommandResult?.self) { group in
            group.addTask { @Sendable [shell] in
                await shell.run("openclaw models list --all --json", recordHistory: false)
            }
            group.addTask { @Sendable in
                try? await Task.sleep(for: .seconds(15))
                return nil // timeout sentinel
            }
            // Return whichever finishes first
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        if let result, result.exitCode == 0 {
            let outputLen = result.output.count
            log("CLI exit code: 0, output length: \(outputLen) chars")
            if let data = result.output.data(using: .utf8) {
                do {
                    let response = try JSONDecoder().decode(ModelCatalogResponse.self, from: data)
                    let fetched = response.models ?? []
                    if !fetched.isEmpty {
                        dynamicModels = fetched
                        try data.write(to: Self.cacheURL, options: .atomic)
                        log("Fetched \(fetched.count) models, \(providers.count) providers. Cache saved.")
                        return
                    }
                } catch {
                    log("JSON decode error: \(error)")
                }
            } else {
                log("Failed to convert output to UTF-8 data")
            }
        } else if let result {
            log("CLI failed (exit \(result.exitCode)): \(result.output.prefix(500))")
        } else {
            log("CLI timed out after 15s — skipping")
        }

        // Fallback: gateway (only returns configured/available models, not the full catalog)
        if let gw = gateway, gw.isConnected {
            log("Trying gateway models.list (configured models only)...")
            do {
                let payload = try await gw.modelsList()
                if let modelsArray = payload["models"] as? [[String: Any]] {
                    let data = try JSONSerialization.data(withJSONObject: modelsArray)
                    let catalogModels = (try? JSONDecoder().decode([CatalogModel].self, from: data)) ?? []
                    if !catalogModels.isEmpty {
                        dynamicModels = catalogModels
                        log("Fetched \(catalogModels.count) configured models via gateway, \(providers.count) providers.")
                        return
                    }
                }
            } catch {
                log("Gateway models.list failed: \(error)")
            }
        }

        log("Using built-in static catalog (\(StaticModelCatalog.allModels.count) models, \(StaticModelCatalog.providers.count) providers)")
    }
}

// MARK: - Sessions

struct SessionsResponse: Codable {
    let path: String?
    let count: Int?
    let sessions: [AgentSession]?
}

struct AgentSession: Identifiable, Codable, Hashable {
    var id: String { sessionId ?? key }
    let agentId: String?
    let key: String
    let model: String?
    let sessionId: String?
    let updatedAt: Double?
    let kind: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case agentId, key, model, sessionId, updatedAt, kind, inputTokens, outputTokens, totalTokens
    }
}

struct SessionStoreIndex: Codable {
    let sessions: [String: SessionStoreEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        sessions = try container.decode([String: SessionStoreEntry].self)
    }
}

struct SessionStoreEntry: Codable {
    let sessionId: String?
    let sessionFile: String?
}

struct SessionTranscriptLine: Codable {
    let type: String
    let timestamp: String?
    let message: TranscriptMessage?
}

struct TranscriptMessage: Codable {
    let role: String?
    let content: [TranscriptContent]?
}

struct TranscriptContent: Codable {
    let type: String?
    let text: String?
}

// MARK: - Workspace File

struct WorkspaceFile: Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let timestamp: Date
}

enum ChatRole {
    case user
    case agent
    case error
}

// MARK: - Command Result

struct CommandResult: Identifiable {
    let id = UUID()
    let command: String
    let output: String
    let timestamp: Date
    let exitCode: Int32
}
