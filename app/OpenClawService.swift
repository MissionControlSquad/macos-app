import Foundation

/// Central service for all OpenClaw interactions.
/// Prefers gateway WebSocket RPCs when connected, falls back to CLI.
@MainActor
@Observable
class OpenClawService {
    // MARK: - State

    var agents: [Agent] = []
    var gatewayStatus: GatewayStatus?
    var modelsStatus: ModelsStatus?
    var isLoading = false
    var lastRefresh: Date?

    private let shell = ShellService()

    /// Optional gateway reference for WebSocket-first operations
    var gateway: GatewayWebSocket?

    /// Open a command in Terminal.app for interactive flows
    nonisolated func openInTerminal(_ command: String) {
        shell.openInTerminal(command)
    }

    // MARK: - Agents

    /// Fetch all agents — tries gateway RPC first, falls back to CLI
    func fetchAgents() async {
        // CLI returns full agent info (workspace, model, bindings, etc.)
        // Gateway only returns minimal info (id, name) — use as fallback
        let result = await shell.run("openclaw agents list --json", recordHistory: false)
        if result.exitCode == 0, let data = result.output.data(using: .utf8) {
            do {
                agents = try JSONDecoder().decode([Agent].self, from: data)
                return
            } catch {
                if let wrapper = try? JSONDecoder().decode(AgentsWrapper.self, from: data) {
                    agents = wrapper.agents
                    return
                }
            }
        }

        // Fallback: gateway (minimal agent info)
        if let gw = gateway, gw.isConnected {
            do {
                let payload = try await gw.agentsList()
                if let agentsList = payload["agents"] as? [[String: Any]] {
                    let data = try JSONSerialization.data(withJSONObject: agentsList)
                    agents = try JSONDecoder().decode([Agent].self, from: data)
                    return
                }
            } catch {
                print("[Service] Gateway agents.list also failed: \(error)")
            }
        }

        // Last resort: parse plain text
        agents = parseAgentsPlainText(result.output)
    }

    /// Get bindings for a specific agent
    func fetchBindings(for agentName: String) async -> [String] {
        let result = await shell.run("openclaw agents bindings --agent \(agentName) --json", recordHistory: false)
        if result.exitCode == 0, let data = result.output.data(using: .utf8) {
            if let bindings = try? JSONDecoder().decode([String].self, from: data) {
                return bindings
            }
        }
        return []
    }

    /// Add a channel binding to an agent
    func bindAgent(name: String, channel: String) async -> CommandResult {
        let result = await shell.run("openclaw agents bind --agent \(name) --bind \(channel)")
        if result.exitCode == 0 { await fetchAgents() }
        return result
    }

    /// Remove a channel binding from an agent
    func unbindAgent(name: String, channel: String) async -> CommandResult {
        let result = await shell.run("openclaw agents unbind --agent \(name) --bind \(channel)")
        if result.exitCode == 0 { await fetchAgents() }
        return result
    }

    /// Fetch usage stats for a specific agent via status --usage
    func fetchAgentUsage(agent: String) async -> CommandResult {
        return await shell.run("openclaw status --usage --json", recordHistory: false)
    }

    /// Add a new agent
    func addAgent(name: String, workspace: String) async -> CommandResult {
        // Create workspace and SOUL.md if needed
        await shell.run("mkdir -p \"\(workspace)\"")
        let soulCheck = await shell.run("test -f \"\(workspace)/SOUL.md\" && echo exists")
        if !soulCheck.output.contains("exists") {
            await shell.run("printf '# \(name)\\nYou are a helpful AI assistant.\\n' > \"\(workspace)/SOUL.md\"")
        }
        let result = await shell.run("openclaw agents add \(name) --workspace \"\(workspace)\" --non-interactive")
        if result.exitCode == 0 {
            await fetchAgents()
        }
        return result
    }

    /// Delete an agent — unbinds channel routes first, then deletes agent and refreshes list.
    func deleteAgent(name: String) async -> CommandResult {
        // 1. Unbind all channel routes for the agent
        let bindings = await fetchBindings(for: name)
        for binding in bindings {
            _ = await shell.run("openclaw agents unbind --agent \(name) --bind \(binding)")
        }

        // 2. Delete the agent (removes from registry, trashes workspace + state)
        let result = await shell.run("openclaw agents delete \(name)")

        // 3. Always refresh the agents list
        await fetchAgents()

        return result
    }

    /// Set agent identity
    func setAgentIdentity(name: String, displayName: String?, emoji: String?) async -> CommandResult {
        var cmd = "openclaw agents set-identity --agent \(name)"
        if let displayName, !displayName.isEmpty {
            cmd += " --name \"\(displayName)\""
        }
        if let emoji, !emoji.isEmpty {
            cmd += " --emoji \"\(emoji)\""
        }
        return await shell.run(cmd)
    }

    // MARK: - Gateway

    /// Step-by-step log for gateway operations
    var gatewayLog: String = ""

    private func logGateway(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        gatewayLog += "[\(time)] \(message)\n"
    }

    /// Check gateway status — tries gateway health RPC first, falls back to CLI
    func fetchGatewayStatus() async {
        // If gateway WebSocket is connected, we know it's running
        if let gw = gateway, gw.isConnected {
            do {
                let payload = try await gw.health()
                // Build a minimal GatewayStatus from health response
                let port = payload["port"] as? Int
                let status = payload["status"] as? String
                if status == "ok" || !payload.raw.isEmpty {
                    gatewayStatus = GatewayStatus(
                        service: GatewayService(label: "com.openclaw.gateway", loaded: true, runtime: GatewayRuntime(status: "running", state: nil, pid: nil), configAudit: nil),
                        gateway: GatewayConfig(bindMode: nil, bindHost: nil, port: port ?? 18789, probeUrl: nil, probeNote: nil),
                        port: GatewayPort(port: port ?? 18789, status: "open"),
                        rpc: GatewayRPC(ok: true, error: nil, url: "ws://127.0.0.1:\(port ?? 18789)")
                    )
                    return
                }
            } catch {
                print("[Service] Gateway health RPC failed: \(error), falling back to CLI")
            }
        }

        // Fallback: CLI
        let result = await shell.run("openclaw gateway status --json", recordHistory: false)
        if let data = result.output.data(using: .utf8) {
            gatewayStatus = try? JSONDecoder().decode(GatewayStatus.self, from: data)
        } else {
            gatewayStatus = nil
        }
    }

    /// Install the gateway as a system service (launchd)
    func installGateway() async -> CommandResult {
        gatewayLog = ""
        logGateway("Running: openclaw gateway install")
        let result = await shell.run("openclaw gateway install")
        logGateway("Exit code: \(result.exitCode)")
        logGateway("Output: \(result.output)")
        try? await Task.sleep(for: .seconds(2))
        await fetchGatewayStatus()
        return result
    }

    /// Start the gateway — configures mode, installs service, starts, and verifies
    func startGateway() async -> CommandResult {
        gatewayLog = ""

        // Step 1: Set gateway.mode=local (required by OpenClaw)
        logGateway("Step 1: Setting gateway.mode=local...")
        let modeResult = await shell.run("openclaw config set gateway.mode local")
        logGateway("Exit code: \(modeResult.exitCode)")
        logGateway("Output: \(modeResult.output)")

        // Step 2: Install service if needed
        logGateway("\nStep 2: Ensuring gateway service is installed...")
        let installResult = await shell.run("openclaw gateway install")
        logGateway("Exit code: \(installResult.exitCode)")
        logGateway("Output: \(installResult.output)")

        if installResult.exitCode != 0 && !installResult.output.contains("already loaded") {
            logGateway("ERROR: Install failed. Aborting.")
            return installResult
        }

        // Step 3: Start the gateway
        logGateway("\nStep 3: Starting gateway...")
        let startResult = await shell.run("openclaw gateway start")
        logGateway("Exit code: \(startResult.exitCode)")
        logGateway("Output: \(startResult.output)")

        // Step 4: Wait for boot
        logGateway("\nStep 4: Waiting 5 seconds for gateway to boot...")
        try? await Task.sleep(for: .seconds(5))

        // Step 5: Check if it's running
        logGateway("Step 5: Checking gateway status...")
        await fetchGatewayStatus()

        if let status = gatewayStatus {
            logGateway("Process running: \(status.processRunning)")
            logGateway("RPC responding: \(status.running)")
            if let pid = status.pid {
                logGateway("PID: \(pid)")
            }
            if let port = status.gatewayPort {
                logGateway("Port: \(port)")
            }
            if let lastError = status.lastError {
                logGateway("Last error: \(lastError)")
            }
            if let rpcError = status.rpc?.error {
                logGateway("RPC error: \(rpcError)")
            }
        } else {
            logGateway("Could not parse gateway status.")
        }

        // Step 6: If RPC not ready but process is running, wait a bit more
        if gatewayStatus?.processRunning == true && gatewayStatus?.running != true {
            logGateway("\nStep 6: Process running but RPC not ready. Waiting 5 more seconds...")
            try? await Task.sleep(for: .seconds(5))
            await fetchGatewayStatus()
            logGateway("RPC responding: \(gatewayStatus?.running ?? false)")

            if gatewayStatus?.running != true {
                logGateway("\nGateway process is running but not accepting connections.")
                logGateway("Check error logs: ~/.openclaw/logs/gateway.err.log")
                let errLog = await shell.run("tail -20 ~/.openclaw/logs/gateway.err.log 2>&1")
                logGateway("Recent error log:\n\(errLog.output)")
            }
        } else if gatewayStatus?.running == true {
            logGateway("\nGateway started successfully!")
        } else {
            logGateway("\nGateway failed to start.")
            let errLog = await shell.run("tail -20 ~/.openclaw/logs/gateway.err.log 2>&1")
            logGateway("Recent error log:\n\(errLog.output)")
        }

        return startResult
    }

    /// Stop the gateway
    func stopGateway() async -> CommandResult {
        gatewayLog = ""
        logGateway("Stopping gateway...")
        let result = await shell.run("openclaw gateway stop")
        logGateway("Exit code: \(result.exitCode)")
        logGateway("Output: \(result.output)")
        try? await Task.sleep(for: .seconds(1))
        await fetchGatewayStatus()
        return result
    }

    /// Restart the gateway
    func restartGateway() async -> CommandResult {
        gatewayLog = ""
        logGateway("Restarting gateway...")
        let result = await shell.run("openclaw gateway restart")
        logGateway("Exit code: \(result.exitCode)")
        logGateway("Output: \(result.output)")
        logGateway("Waiting 3 seconds for gateway to boot...")
        try? await Task.sleep(for: .seconds(3))
        await fetchGatewayStatus()
        logGateway("Gateway running: \(gatewayStatus?.running ?? false)")
        return result
    }

    /// Run gateway health check — tries gateway RPC first, falls back to CLI
    func gatewayHealth() async -> CommandResult {
        gatewayLog = ""
        
        if let gw = gateway, gw.isConnected {
            logGateway("Running health check via gateway WebSocket...")
            do {
                let payload = try await gw.health()
                if let jsonData = try? JSONSerialization.data(withJSONObject: payload.raw, options: .prettyPrinted),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    logGateway("Health: OK")
                    logGateway(jsonStr)
                    return CommandResult(command: "gateway.health()", output: jsonStr, timestamp: Date(), exitCode: 0)
                }
            } catch {
                logGateway("Gateway RPC failed: \(error), falling back to CLI")
            }
        }

        logGateway("Running health check via CLI...")
        let result = await shell.run("openclaw gateway health --json")
        logGateway("Exit code: \(result.exitCode)")
        logGateway("Output: \(result.output)")
        return result
    }

    // MARK: - Models

    /// Fetch model provider status via `openclaw models status --check --json`
    func fetchModelsStatus() async {
        let result = await shell.run("openclaw models status --check --json", recordHistory: false)
        if let data = result.output.data(using: .utf8) {
            modelsStatus = try? JSONDecoder().decode(ModelsStatus.self, from: data)
        } else {
            modelsStatus = nil
        }
    }

    /// Set the default model
    func setDefaultModel(_ model: String) async -> CommandResult {
        let result = await shell.run("openclaw models set \"\(model)\"")
        await fetchModelsStatus()
        return result
    }

    /// Configure a provider API key.
    ///
    /// Writes directly to both storage locations:
    /// 1. `auth-profiles.json` — the actual secret key
    /// 2. `openclaw.json` — the profile reference (via `openclaw config set`)
    ///
    /// The CLI's `openclaw onboard --auth-choice <provider>-api-key` has a bug where it
    /// doesn't write to `auth-profiles.json` in non-interactive mode, so we bypass it
    /// and write the files directly for API key providers.
    func configureProvider(provider: String, apiKey: String) async -> CommandResult {
        let providerKey = provider.lowercased()

        // Special cases: local runners (no key) and OAuth providers
        switch providerKey {
        case "ollama":
            let cmd = "openclaw onboard --non-interactive --accept-risk --auth-choice ollama --skip-health"
            return await runOnboardAndRestart(cmd)
        case "vllm":
            let cmd = "openclaw onboard --non-interactive --accept-risk --auth-choice vllm --skip-health"
            return await runOnboardAndRestart(cmd)
        case "sglang":
            let cmd = "openclaw onboard --non-interactive --accept-risk --auth-choice sglang --skip-health"
            return await runOnboardAndRestart(cmd)
        case "openai-codex":
            shell.openInTerminal("openclaw onboard --auth-choice openai-codex")
            return CommandResult(command: "openai-codex OAuth", output: "Opened Terminal for OAuth login", timestamp: Date(), exitCode: 0)
        default:
            break
        }

        // Resolve the provider name used in auth-profiles.json.
        // Most providers use their name directly, but some map differently.
        let profileProvider: String
        switch providerKey {
        case "google": profileProvider = "google"
        case "kimi-coding": profileProvider = "kimi-coding"
        case "vercel-ai-gateway": profileProvider = "vercel-ai-gateway"
        case "cloudflare-ai-gateway": profileProvider = "cloudflare-ai-gateway"
        case "minimax-cn": profileProvider = "minimax-cn"
        case "opencode-go": profileProvider = "opencode-go"
        case "modelstudio-cn": profileProvider = "modelstudio-cn"
        case "zai-coding-global": profileProvider = "zai-coding-global"
        case "zai-coding-cn": profileProvider = "zai-coding-cn"
        case "zai-global": profileProvider = "zai-global"
        case "zai-cn": profileProvider = "zai-cn"
        default: profileProvider = providerKey
        }

        let profileId = "\(profileProvider):default"

        // 1. Write the actual key to auth-profiles.json
        let writeSuccess = writeToAuthProfilesJSON(profileId: profileId, provider: profileProvider, key: apiKey)
        guard writeSuccess else {
            return CommandResult(command: "configureProvider", output: "Failed to write to auth-profiles.json", timestamp: Date(), exitCode: 1)
        }

        // 2. Write the profile reference to openclaw.json via CLI
        _ = await shell.run("openclaw config set 'auth.profiles.\(profileId)' '{\"provider\":\"\(profileProvider)\",\"mode\":\"api_key\"}'")


        // 3. Restart gateway and refresh
        _ = await shell.run("openclaw gateway restart", recordHistory: false)
        try? await Task.sleep(for: .seconds(2))
        await fetchModelsStatus()

        return CommandResult(command: "configureProvider", output: "\(provider) configured", timestamp: Date(), exitCode: 0)
    }

    /// Write an API key entry to auth-profiles.json.
    /// Returns true on success.
    private func writeToAuthProfilesJSON(profileId: String, provider: String, key: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profilesPath = "\(home)/.openclaw/agents/main/agent/auth-profiles.json"

        // Read existing file or create default structure
        var json: [String: Any]
        if let data = FileManager.default.contents(atPath: profilesPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        } else {
            json = ["version": 1, "profiles": [String: Any](), "usageStats": [String: Any]()]
        }

        // Get or create the profiles dict
        var profiles = json["profiles"] as? [String: Any] ?? [:]

        // Add the new profile entry
        profiles[profileId] = [
            "type": "api_key",
            "provider": provider,
            "key": key
        ]
        json["profiles"] = profiles

        // Write back
        guard let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }

        do {
            try updatedData.write(to: URL(fileURLWithPath: profilesPath))
            return true
        } catch {
            print("[Service] Failed to write auth-profiles.json: \(error)")
            return false
        }
    }

    /// Run an onboard command, restart the gateway, and refresh models status.
    private func runOnboardAndRestart(_ cmd: String) async -> CommandResult {
        let result = await shell.run(cmd)
        _ = await shell.run("openclaw gateway restart", recordHistory: false)
        try? await Task.sleep(for: .seconds(2))
        await fetchModelsStatus()
        return result
    }

    /// Remove a provider entirely: config references, stored keys, and allowed models.
    ///
    /// OpenClaw stores provider auth in two places:
    /// 1. `~/.openclaw/openclaw.json` → `auth.profiles.<provider>:default` (reference: provider + mode)
    /// 2. `~/.openclaw/agents/main/agent/auth-profiles.json` → `profiles.<provider>:default` (actual secret key)
    ///
    /// There is no CLI command to remove from auth-profiles.json, so we edit it directly.
    func removeProviderAuth(provider: String) async -> CommandResult {
        // 1. Remove auth profile references from openclaw.json (try common ID patterns)
        _ = await shell.run("openclaw config unset 'auth.profiles.\(provider):default'")
        _ = await shell.run("openclaw config unset 'auth.profiles.\(provider):manual'")

        // 2. Remove actual stored keys from auth-profiles.json
        removeFromAuthProfilesJSON(provider: provider)

        // 3. Remove this provider's models from the allowed list (agents.defaults.models)
        let modelsResult = await shell.run("openclaw config get agents.defaults.models", recordHistory: false)
        if modelsResult.exitCode == 0,
           let data = modelsResult.output.data(using: .utf8),
           let models = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let prefix = provider + "/"
            let toRemove = models.keys.filter { $0.hasPrefix(prefix) }
            for modelKey in toRemove {
                _ = await shell.run("openclaw config unset 'agents.defaults.models.\(modelKey)'")
            }
        }

        // 4. If this provider was the default model, clear it
        if let currentDefault = modelsStatus?.defaultModel, currentDefault.hasPrefix(provider + "/") {
            _ = await shell.run("openclaw config unset 'agents.defaults.model.primary'")
        }

        // 5. Locally remove the provider from cached modelsStatus for immediate UI update
        if let current = modelsStatus {
            let filteredProviders = current.providers.filter { $0.provider != provider }
            let filteredAllowed = current.allowed?.filter { !$0.hasPrefix(provider + "/") }
            if let authData = try? JSONEncoder().encode(current),
               var json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] {
                if var auth = json["auth"] as? [String: Any],
                   var oauth = auth["oauth"] as? [String: Any] {
                    if let providersData = try? JSONEncoder().encode(filteredProviders),
                       let providersArray = try? JSONSerialization.jsonObject(with: providersData) {
                        oauth["providers"] = providersArray
                        auth["oauth"] = oauth
                        json["auth"] = auth
                    }
                }
                json["allowed"] = filteredAllowed
                if let rebuiltData = try? JSONSerialization.data(withJSONObject: json),
                   let rebuilt = try? JSONDecoder().decode(ModelsStatus.self, from: rebuiltData) {
                    modelsStatus = rebuilt
                }
            }
        }

        // 6. Restart gateway so it picks up the config changes
        _ = await shell.run("openclaw gateway restart", recordHistory: false)
        try? await Task.sleep(for: .seconds(2))

        // 7. Re-fetch from gateway (should now reflect the removal)
        await fetchModelsStatus()

        return CommandResult(command: "removeProviderAuth", output: "Removed \(provider)", timestamp: Date(), exitCode: 0)
    }

    /// Remove a provider's entries from auth-profiles.json directly.
    /// This file stores actual secret keys — there is no CLI command to remove entries.
    private func removeFromAuthProfilesJSON(provider: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profilesPath = "\(home)/.openclaw/agents/main/agent/auth-profiles.json"
        guard let data = FileManager.default.contents(atPath: profilesPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var profiles = json["profiles"] as? [String: Any] else {
            return
        }

        // Remove all profile IDs matching this provider (e.g. "anthropic:default", "anthropic:manual")
        let keysToRemove = profiles.keys.filter { $0.hasPrefix(provider + ":") || $0 == provider }
        guard !keysToRemove.isEmpty else { return }

        for key in keysToRemove {
            profiles.removeValue(forKey: key)
        }
        json["profiles"] = profiles

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: URL(fileURLWithPath: profilesPath))
        }
    }

    /// Remove an agent-specific provider auth override
    func removeAgentProviderAuth(agent: String, provider: String) async -> CommandResult {
        var result = await shell.run("openclaw config unset 'agents.\(agent).auth.profiles.\(provider):default'")
        if result.exitCode != 0 {
            result = await shell.run("openclaw config unset 'agents.\(agent).auth.profiles.\(provider):manual'")
        }
        return result
    }

    /// Validate a specific provider's API key by checking its auth status.
    /// Returns the ProviderStatus for the given provider, or nil if not found.
    func validateProviderAuth(provider: String) async -> ProviderStatus? {
        let result = await shell.run("openclaw models status --check --json", recordHistory: false)
        guard let data = result.output.data(using: .utf8),
              let status = try? JSONDecoder().decode(ModelsStatus.self, from: data) else {
            return nil
        }
        // Update cached status
        modelsStatus = status
        return status.providers.first { $0.provider == provider }
    }

    /// Validate a provider by making a live API call using the stored key/token.
    /// Reads the API key or OAuth token from auth-profiles.json and calls the provider's endpoint.
    func validateProviderLive(provider: String) async -> APIKeyValidation {
        // Read the auth-profiles.json to find the stored key
        let result = await shell.run("openclaw config get auth", recordHistory: false)
        guard result.exitCode == 0 else {
            return APIKeyValidation(isValid: false, error: "Could not read auth config")
        }

        // Try to find the stored key from auth-profiles.json directly
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profilesPath = "\(home)/.openclaw/agents/main/agent/auth-profiles.json"
        guard let profilesData = FileManager.default.contents(atPath: profilesPath),
              let profilesJson = try? JSONSerialization.jsonObject(with: profilesData) as? [String: Any],
              let profiles = profilesJson["profiles"] as? [String: Any] else {
            return APIKeyValidation(isValid: false, error: "Could not read auth profiles")
        }

        // Look for a profile matching this provider (try common ID patterns)
        let candidateIds = ["\(provider):default", "\(provider):manual", provider]
        var storedKey: String?
        var profileType: String?

        for candidateId in candidateIds {
            if let profile = profiles[candidateId] as? [String: Any] {
                profileType = profile["type"] as? String
                if profileType == "api_key" {
                    storedKey = profile["key"] as? String
                } else if profileType == "oauth" {
                    storedKey = profile["access"] as? String
                } else if profileType == "token" {
                    storedKey = profile["token"] as? String ?? profile["key"] as? String
                }
                if storedKey != nil { break }
            }
        }

        guard let apiKey = storedKey, !apiKey.isEmpty else {
            return APIKeyValidation(isValid: false, error: "No stored key found for \(provider)")
        }

        // validateAPIKey handles provider name routing (including openai-codex → openai)
        return await Self.validateAPIKey(provider: provider, apiKey: apiKey)
    }

    /// Validate a provider's key for a specific agent.
    func validateAgentProviderAuth(agent: String, provider: String) async -> ProviderStatus? {
        let result = await shell.run("openclaw models --agent \(agent) status --check --json", recordHistory: false)
        guard let data = result.output.data(using: .utf8),
              let status = try? JSONDecoder().decode(ModelsStatus.self, from: data) else {
            return nil
        }
        return status.providers.first { $0.provider == provider }
    }

    // MARK: - Real API Key Validation

    /// Result of a real API key validation call
    struct APIKeyValidation {
        let isValid: Bool
        let error: String?
    }

    /// Validate an API key by making a real HTTP request to the provider.
    /// Routes to the appropriate provider-specific validation function.
    static func validateAPIKey(provider: String, apiKey: String) async -> APIKeyValidation {
        switch provider.lowercased() {
        case "google":
            return await validateGoogleKey(apiKey)
        case "openai", "openai-codex":
            return await validateOpenAIKey(apiKey)
        case "anthropic":
            return await validateAnthropicKey(apiKey)
        case "mistral":
            return await validateMistralKey(apiKey)
        case "openrouter":
            return await validateOpenRouterKey(apiKey)
        case "xai":
            return await validateBearerKey(apiKey, url: "https://api.x.ai/v1/models", name: "xAI")
        case "groq":
            return await validateBearerKey(apiKey, url: "https://api.groq.com/openai/v1/models", name: "Groq")
        case "together":
            return await validateBearerKey(apiKey, url: "https://api.together.xyz/v1/models", name: "Together")
        case "cerebras":
            return await validateBearerKey(apiKey, url: "https://api.cerebras.ai/v1/models", name: "Cerebras")
        case "huggingface":
            return await validateBearerKey(apiKey, url: "https://huggingface.co/api/whoami-v2", name: "HuggingFace")
        case "ollama":
            return await validateOllamaKey(apiKey)
        default:
            // For providers without a known validation endpoint, accept the key
            return APIKeyValidation(isValid: true, error: nil)
        }
    }

    /// Google Gemini: GET /v1beta/models?key=<key>
    private static func validateGoogleKey(_ apiKey: String) async -> APIKeyValidation {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            return APIKeyValidation(isValid: false, error: "Invalid API key format")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidation(isValid: false, error: "Invalid response")
            }
            if http.statusCode == 200 {
                return APIKeyValidation(isValid: true, error: nil)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 400 || http.statusCode == 403 {
                return APIKeyValidation(isValid: false, error: "Invalid API key")
            }
            return APIKeyValidation(isValid: false, error: "HTTP \(http.statusCode): \(body.prefix(200))")
        } catch {
            return APIKeyValidation(isValid: false, error: error.localizedDescription)
        }
    }

    /// OpenAI: GET /v1/models with Bearer token
    private static func validateOpenAIKey(_ apiKey: String) async -> APIKeyValidation {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return APIKeyValidation(isValid: false, error: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidation(isValid: false, error: "Invalid response")
            }
            if http.statusCode == 200 {
                return APIKeyValidation(isValid: true, error: nil)
            }
            if http.statusCode == 401 {
                return APIKeyValidation(isValid: false, error: "Invalid API key")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            return APIKeyValidation(isValid: false, error: "HTTP \(http.statusCode): \(body.prefix(200))")
        } catch {
            return APIKeyValidation(isValid: false, error: error.localizedDescription)
        }
    }

    /// Anthropic: GET /v1/models with x-api-key header
    private static func validateAnthropicKey(_ apiKey: String) async -> APIKeyValidation {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            return APIKeyValidation(isValid: false, error: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidation(isValid: false, error: "Invalid response")
            }
            if http.statusCode == 200 {
                return APIKeyValidation(isValid: true, error: nil)
            }
            if http.statusCode == 401 {
                return APIKeyValidation(isValid: false, error: "Invalid API key")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            return APIKeyValidation(isValid: false, error: "HTTP \(http.statusCode): \(body.prefix(200))")
        } catch {
            return APIKeyValidation(isValid: false, error: error.localizedDescription)
        }
    }

    /// Mistral: GET /v1/models with Bearer token
    private static func validateMistralKey(_ apiKey: String) async -> APIKeyValidation {
        guard let url = URL(string: "https://api.mistral.ai/v1/models") else {
            return APIKeyValidation(isValid: false, error: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidation(isValid: false, error: "Invalid response")
            }
            if http.statusCode == 200 {
                return APIKeyValidation(isValid: true, error: nil)
            }
            if http.statusCode == 401 {
                return APIKeyValidation(isValid: false, error: "Invalid API key")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            return APIKeyValidation(isValid: false, error: "HTTP \(http.statusCode): \(body.prefix(200))")
        } catch {
            return APIKeyValidation(isValid: false, error: error.localizedDescription)
        }
    }

    /// OpenRouter: GET /api/v1/models with Bearer token
    private static func validateOpenRouterKey(_ apiKey: String) async -> APIKeyValidation {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            return APIKeyValidation(isValid: false, error: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidation(isValid: false, error: "Invalid response")
            }
            if http.statusCode == 200 {
                return APIKeyValidation(isValid: true, error: nil)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return APIKeyValidation(isValid: false, error: "Invalid API key")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            return APIKeyValidation(isValid: false, error: "HTTP \(http.statusCode): \(body.prefix(200))")
        } catch {
            return APIKeyValidation(isValid: false, error: error.localizedDescription)
        }
    }

    /// Ollama: GET /api/tags on localhost — no key needed, just check reachability
    private static func validateOllamaKey(_ apiKey: String) async -> APIKeyValidation {
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            return APIKeyValidation(isValid: false, error: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidation(isValid: false, error: "Invalid response")
            }
            if http.statusCode == 200 {
                return APIKeyValidation(isValid: true, error: nil)
            }
            return APIKeyValidation(isValid: false, error: "Ollama returned HTTP \(http.statusCode)")
        } catch {
            return APIKeyValidation(isValid: false, error: "Ollama not reachable at localhost:11434. Is it running?")
        }
    }

    /// Generic Bearer token validation: GET a URL with Authorization: Bearer header.
    /// Works for any OpenAI-compatible provider (xAI, Groq, Together, Cerebras, HuggingFace, etc.)
    private static func validateBearerKey(_ apiKey: String, url urlString: String, name: String) async -> APIKeyValidation {
        guard let url = URL(string: urlString) else {
            return APIKeyValidation(isValid: false, error: "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return APIKeyValidation(isValid: false, error: "Invalid response")
            }
            if http.statusCode == 200 {
                return APIKeyValidation(isValid: true, error: nil)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return APIKeyValidation(isValid: false, error: "Invalid API key")
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            return APIKeyValidation(isValid: false, error: "HTTP \(http.statusCode): \(body.prefix(200))")
        } catch {
            return APIKeyValidation(isValid: false, error: "\(name) not reachable: \(error.localizedDescription)")
        }
    }

    // MARK: - Sessions

    /// Fetch sessions — tries gateway RPC first, falls back to CLI
    func fetchSessions(agent: String? = nil) async -> [AgentSession] {
        // Try gateway first
        if let gw = gateway, gw.isConnected {
            do {
                let response = try await gw.sessionsList()
                let allSessions = response.sessions ?? []
                let filtered: [GatewaySession]
                if let agent {
                    filtered = allSessions.filter { $0.agentId == agent }
                } else {
                    filtered = allSessions
                }
                return filtered.map { gs in
                    var session = AgentSession(
                        agentId: gs.agentId,
                        key: gs.key,
                        model: gs.model,
                        sessionId: gs.sessionId,
                        updatedAt: gs.updatedAt,
                        kind: gs.kind
                    )
                    session.inputTokens = gs.inputTokens
                    session.outputTokens = gs.outputTokens
                    session.totalTokens = gs.totalTokens
                    return session
                }
                .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            } catch {
                print("[Service] Gateway sessions.list failed: \(error), falling back to CLI")
            }
        }

        // Fallback: CLI
        var cmd = "openclaw sessions --json"
        if let agent {
            cmd += " --agent \(agent)"
        } else {
            cmd += " --all-agents"
        }
        let result = await shell.run(cmd, recordHistory: false)
        if result.exitCode == 0, let data = result.output.data(using: .utf8) {
            if let response = try? JSONDecoder().decode(SessionsResponse.self, from: data) {
                return (response.sessions ?? []).sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            }
        }
        return []
    }

    /// Resolve transcript path for a given session using the session store index.
    private func transcriptPath(for agent: String, sessionId: String) async -> String? {
        let indexResult = await shell.run("cat ~/.openclaw/agents/\(agent)/sessions/sessions.json", recordHistory: false)
        guard indexResult.exitCode == 0, let data = indexResult.output.data(using: .utf8) else { return nil }

        if let entries = try? JSONDecoder().decode([String: SessionStoreEntry].self, from: data) {
            if let match = entries.values.first(where: { $0.sessionId == sessionId }) {
                return match.sessionFile ?? "~/.openclaw/agents/\(agent)/sessions/\(sessionId).jsonl"
            }
        }

        return "~/.openclaw/agents/\(agent)/sessions/\(sessionId).jsonl"
    }

    /// Load transcript history for a stored session.
    func loadSessionHistory(agent: String, sessionId: String) async -> [ChatMessage] {
        guard let rawPath = await transcriptPath(for: agent, sessionId: sessionId) else { return [] }
        let escapedPath = rawPath.replacingOccurrences(of: "\"", with: "\\\"")
        let result = await shell.run("cat \"\(escapedPath)\"", recordHistory: false)
        guard result.exitCode == 0 else { return [] }

        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        var messages: [ChatMessage] = []

        for line in result.output.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(SessionTranscriptLine.self, from: data),
                  entry.type == "message",
                  let msg = entry.message,
                  let role = msg.role,
                  let content = msg.content else { continue }

            let textParts = content.compactMap { part -> String? in
                guard let type = part.type else { return nil }
                switch type {
                case "text":
                    return part.text
                default:
                    return nil
                }
            }

            let text = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let timestamp = entry.timestamp.flatMap { iso.date(from: $0) } ?? Date()
            let chatRole: ChatRole
            switch role {
            case "user": chatRole = .user
            case "assistant": chatRole = .agent
            default: continue
            }

            messages.append(ChatMessage(role: chatRole, content: text, timestamp: timestamp))
        }

        return messages
    }

    // MARK: - Chat / Messaging

    /// Send a message to an agent and get the response (blocking)
    func sendMessage(to agent: String, message: String, sessionId: String? = nil) async -> CommandResult {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        var cmd = "openclaw agent --to \(agent) --message \"\(escaped)\""
        if let sessionId, !sessionId.isEmpty {
            cmd += " --session-id \(sessionId)"
        }
        return await shell.run(cmd)
    }

    /// Start a streaming message to an agent. Returns a StreamingProcess whose
    /// `output` property updates in real-time as the agent responds.
    func sendMessageStreaming(to agent: String, message: String, sessionId: String? = nil) -> StreamingProcess {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        var cmd = "openclaw agent --to \(agent) --message \"\(escaped)\""
        if let sessionId, !sessionId.isEmpty {
            cmd += " --session-id \(sessionId)"
        }
        return shell.startStreaming(cmd)
    }

    // MARK: - Workspace Files

    /// List files in an agent's workspace directory
    func listWorkspaceFiles(workspace: String) async -> [WorkspaceFile] {
        let result = await shell.run("ls -lAp \"\(workspace)\"")
        guard result.exitCode == 0 else { return [] }

        var files: [WorkspaceFile] = []
        let lines = result.output.components(separatedBy: "\n")

        for line in lines {
            // Skip the total line and empty lines
            if line.hasPrefix("total") || line.isEmpty { continue }

            let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }

            let sizeStr = parts[4]
            let name = String(parts[8])
            let isDir = name.hasSuffix("/")
            let cleanName = isDir ? String(name.dropLast()) : name

            // Skip hidden files except .openclaw
            if cleanName.hasPrefix(".") && cleanName != ".openclaw" { continue }

            files.append(WorkspaceFile(
                name: cleanName,
                path: "\(workspace)/\(cleanName)",
                isDirectory: isDir,
                size: Int64(sizeStr) ?? 0
            ))
        }

        return files
    }

    /// Read the content of a workspace file
    func readWorkspaceFile(path: String) async -> String {
        let result = await shell.run("cat \"\(path)\"")
        return result.exitCode == 0 ? result.output : "Error reading file: \(result.output)"
    }

    // MARK: - Channels

    /// List configured channels
    func fetchChannels() async -> CommandResult {
        return await shell.run("openclaw channels list --json")
    }

    /// Get channel runtime status
    func fetchChannelStatus() async -> CommandResult {
        return await shell.run("openclaw channels status --json")
    }

    /// Start a streaming channel login process (e.g. WhatsApp QR flow)
    func channelLoginStreaming(channel: String, account: String? = nil) -> StreamingProcess {
        var cmd = "openclaw channels login --channel \(channel)"
        if let account { cmd += " --account \(account)" }
        return shell.startStreaming(cmd)
    }

    /// List pairing requests for a channel
    func pairingList(channel: String) async -> CommandResult {
        return await shell.run("openclaw pairing list \(channel) --json", recordHistory: false)
    }

    /// Approve a pairing request
    func pairingApprove(channel: String, code: String) async -> CommandResult {
        return await shell.run("openclaw pairing approve \(channel) \(code)")
    }

    /// Enable a config-based channel
    func enableChannel(channel: String) async -> CommandResult {
        return await shell.run("openclaw config set channels.\(channel).enabled true --json")
    }

    /// Disable a config-based channel
    func disableChannel(channel: String) async -> CommandResult {
        return await shell.run("openclaw config set channels.\(channel).enabled false --json")
    }

    /// Set a config value as a JSON-typed value (for booleans, numbers, objects)
    func configSetJSON(_ key: String, value: String) async -> CommandResult {
        return await shell.run("openclaw config set \(key) '\(value)' --json")
    }

    /// Set a config value as a quoted string
    func configSetString(_ key: String, value: String) async -> CommandResult {
        // --json with quoted string ensures it's stored as a string
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return await shell.run("openclaw config set \(key) '\"\(escaped)\"' --json")
    }

    // MARK: - Logs

    /// Fetch recent logs with local timestamps
    func fetchLogs(limit: Int = 100) async -> CommandResult {
        return await shell.run("openclaw logs --limit \(limit) --local-time", recordHistory: false)
    }

    /// Start streaming live logs via --follow
    func startLogStream() -> StreamingProcess {
        return shell.startStreaming("openclaw logs --follow --local-time")
    }

    // MARK: - Memory

    /// Check memory status with deep vector/embedding probe
    func memoryStatus(agent: String? = nil) async -> CommandResult {
        var cmd = "openclaw memory status --deep --json"
        if let agent { cmd += " --agent \(agent)" }
        return await shell.run(cmd)
    }

    /// Search agent memory
    func memorySearch(query: String, agent: String? = nil) async -> CommandResult {
        var cmd = "openclaw memory search --query \"\(query)\" --json"
        if let agent { cmd += " --agent \(agent)" }
        return await shell.run(cmd)
    }

    /// Rebuild memory index (full reindex)
    func memoryIndex(agent: String? = nil, force: Bool = true) async -> CommandResult {
        var cmd = "openclaw memory index"
        if force { cmd += " --force" }
        if let agent { cmd += " --agent \(agent)" }
        cmd += " --verbose"
        return await shell.run(cmd)
    }

    // MARK: - Skills

    /// List all skills with eligibility info
    func fetchSkills() async -> CommandResult {
        return await shell.run("openclaw skills list --eligible --json")
    }

    /// Get skill info
    func skillInfo(name: String) async -> CommandResult {
        return await shell.run("openclaw skills info \(name) --json")
    }

    // MARK: - Plugins

    /// List all plugins
    func fetchPlugins() async -> CommandResult {
        return await shell.run("openclaw plugins list --json")
    }

    /// Enable a plugin
    func enablePlugin(id: String) async -> CommandResult {
        let result = await shell.run("openclaw plugins enable \(id)")
        return result
    }

    /// Disable a plugin
    func disablePlugin(id: String) async -> CommandResult {
        let result = await shell.run("openclaw plugins disable \(id)")
        return result
    }

    /// Install a plugin
    func installPlugin(spec: String) async -> CommandResult {
        return await shell.run("openclaw plugins install \(spec)")
    }

    // MARK: - Cron

    /// List cron jobs
    func fetchCronJobs() async -> CommandResult {
        return await shell.run("openclaw cron list --json")
    }

    /// Add a cron job
    func addCronJob(name: String, schedule: String, message: String) async -> CommandResult {
        return await shell.run(
            "openclaw cron add --name \"\(name)\" --cron \"\(schedule)\" --message \"\(message)\""
        )
    }

    /// Remove a cron job
    func removeCronJob(id: String) async -> CommandResult {
        return await shell.run("openclaw cron rm \(id)")
    }

    /// Run a cron job now
    func runCronJob(id: String) async -> CommandResult {
        return await shell.run("openclaw cron run \(id)")
    }

    /// View cron job runs
    func cronJobRuns(id: String) async -> CommandResult {
        return await shell.run("openclaw cron runs --id \(id) --json")
    }

    // MARK: - Hooks

    /// List all hooks with verbose requirement details
    func fetchHooks() async -> CommandResult {
        return await shell.run("openclaw hooks list --verbose --json")
    }

    /// Enable a hook
    func enableHook(name: String) async -> CommandResult {
        return await shell.run("openclaw hooks enable \(name)")
    }

    /// Disable a hook
    func disableHook(name: String) async -> CommandResult {
        return await shell.run("openclaw hooks disable \(name)")
    }

    /// Hook info
    func hookInfo(name: String) async -> CommandResult {
        return await shell.run("openclaw hooks info \(name) --json")
    }

    // MARK: - Config / Settings

    /// Get a config value — tries gateway RPC first, falls back to CLI
    func configGet(_ key: String) async -> CommandResult {
        if let gw = gateway, gw.isConnected {
            do {
                let payload = try await gw.configGet(key: key)
                let value = payload["value"]
                let output = "\(value ?? "null")"
                return CommandResult(command: "config.get(\(key))", output: output, timestamp: Date(), exitCode: 0)
            } catch {
                print("[Service] Gateway config.get failed: \(error), falling back to CLI")
            }
        }
        return await shell.run("openclaw config get \(key)")
    }

    /// Set a config value — tries gateway RPC first, falls back to CLI
    func configSet(_ key: String, value: String) async -> CommandResult {
        if let gw = gateway, gw.isConnected {
            do {
                _ = try await gw.configSet(key: key, value: value)
                return CommandResult(command: "config.set(\(key))", output: "\(key) updated", timestamp: Date(), exitCode: 0)
            } catch {
                print("[Service] Gateway config.set failed: \(error), falling back to CLI")
            }
        }
        return await shell.run("openclaw config set \(key) \"\(value)\"")
    }

    /// Unset a config value
    func configUnset(_ key: String) async -> CommandResult {
        return await shell.run("openclaw config unset \(key)")
    }

    /// Validate config
    func configValidate() async -> CommandResult {
        return await shell.run("openclaw config validate --json")
    }

    /// Get the full config file path
    func configFile() async -> CommandResult {
        return await shell.run("openclaw config file")
    }

    // MARK: - Per-Agent Auth

    /// Configure auth for a specific agent via env config
    func configureAgentAuth(agent: String, provider: String, apiKey: String) async -> CommandResult {
        let escaped = apiKey.replacingOccurrences(of: "\"", with: "\\\"")
        return await shell.run(
            "echo \"\(escaped)\" | openclaw models --agent \(agent) auth paste-token --provider \(provider)"
        )
    }

    /// Set model for a specific agent
    func setAgentModel(agent: String, model: String) async -> CommandResult {
        return await shell.run("openclaw models --agent \(agent) set \"\(model)\"")
    }

    /// Get model auth status with live probe (consumes tokens)
    func fetchModelsStatusDetailed() async -> CommandResult {
        return await shell.run("openclaw models status --check --probe --json")
    }

    /// Manage fallback models
    func listFallbacks() async -> CommandResult {
        return await shell.run("openclaw models fallbacks list")
    }

    func addFallback(model: String) async -> CommandResult {
        return await shell.run("openclaw models fallbacks add \"\(model)\"")
    }

    func removeFallback(model: String) async -> CommandResult {
        return await shell.run("openclaw models fallbacks remove \"\(model)\"")
    }

    /// Reorder fallback models via a single config set (much faster than clear + N adds)
    func reorderFallbacks(models: [String]) async -> CommandResult {
        let json = "[" + models.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return await shell.run("openclaw config set agents.defaults.model.fallbacks '\(json)'")
    }

    // MARK: - Diagnostics

    /// Run full diagnostics with deep checks
    func runDoctor() async -> CommandResult {
        return await shell.run("openclaw doctor --deep")
    }

    /// Get full system status with usage info
    func fetchSystemStatus() async -> CommandResult {
        return await shell.run("openclaw status --all --json")
    }

    // MARK: - Shell Passthrough

    /// Run an arbitrary command (for the terminal view)
    @discardableResult
    func runCommand(_ command: String) async -> CommandResult {
        return await shell.run(command)
    }

    /// Access to command history from ShellService
    var commandHistory: [CommandResult] {
        get { shell.commandHistory }
        set { shell.commandHistory = newValue }
    }

    var isRunningCommand: Bool {
        shell.isRunning
    }

    // MARK: - Refresh All

    /// Refresh all data from OpenClaw (runs fetches concurrently)
    func refreshAll() async {
        isLoading = true
        async let agentsTask: () = fetchAgents()
        async let gatewayTask: () = fetchGatewayStatus()
        async let modelsTask: () = fetchModelsStatus()
        _ = await (agentsTask, gatewayTask, modelsTask)
        lastRefresh = Date()
        isLoading = false
    }

    // MARK: - Parsing Fallback

    /// Fallback parser for plain text output when --json is not available
    private func parseAgentsPlainText(_ output: String) -> [Agent] {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        var parsed: [Agent] = []

        for line in lines {
            // Skip headers, separators, and JSON-looking lines
            if line.contains("───")
                || line.contains("{") || line.contains("}")
                || line.contains("[") || line.contains("]")
                || line.contains("\":")
                || (line.lowercased().contains("name") && line.lowercased().contains("status")) {
                continue
            }

            let components = line.components(separatedBy: CharacterSet.whitespaces)
                .filter { !$0.isEmpty && $0 != "│" && $0 != "|" }

            if components.count >= 1 {
                let name = components[0]
                let workspace = components.count >= 2 ? components[1] : "~"
                // Build Agent via JSON decoding to use CodingKeys
                let json: [String: Any] = ["id": name, "workspace": workspace]
                if let data = try? JSONSerialization.data(withJSONObject: json),
                   let agent = try? JSONDecoder().decode(Agent.self, from: data) {
                    parsed.append(agent)
                }
            }
        }

        return parsed
    }
}

/// Wrapper in case JSON output wraps agents in an object
private struct AgentsWrapper: Codable {
    let agents: [Agent]
}
