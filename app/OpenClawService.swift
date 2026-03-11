import Foundation

/// Central service for all OpenClaw CLI interactions.
/// Every data fetch goes through this service using `--json` output.
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

    // MARK: - Agents

    /// Fetch all agents with full details via `openclaw agents list --json`
    func fetchAgents() async {
        let result = await shell.run("openclaw agents list --json", recordHistory: false)
        if result.exitCode == 0, let data = result.output.data(using: .utf8) {
            do {
                agents = try JSONDecoder().decode([Agent].self, from: data)
            } catch {
                // Might be wrapped in an object
                if let wrapper = try? JSONDecoder().decode(AgentsWrapper.self, from: data) {
                    agents = wrapper.agents
                } else {
                    agents = parseAgentsPlainText(result.output)
                }
            }
        } else {
            agents = parseAgentsPlainText(result.output)
        }
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

    /// Delete an agent
    func deleteAgent(name: String) async -> CommandResult {
        let result = await shell.run("openclaw agents delete \(name)")
        if result.exitCode == 0 {
            await fetchAgents()
        }
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

    /// Check gateway status via `openclaw gateway status --json`
    func fetchGatewayStatus() async {
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

    /// Run gateway health check
    func gatewayHealth() async -> CommandResult {
        gatewayLog = ""
        logGateway("Running health check...")
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

    /// Configure a provider API key via `openclaw onboard` (non-interactive)
    func configureProvider(provider: String, apiKey: String) async -> CommandResult {
        let escaped = apiKey.replacingOccurrences(of: "\"", with: "\\\"")
        // Provider-specific flags documented at docs.openclaw.ai/providers/*
        let cmd = "openclaw onboard --non-interactive --auth-choice \(provider)-api-key --\(provider)-api-key \"\(escaped)\""
        let result = await shell.run(cmd)
        await fetchModelsStatus()
        return result
    }

    // MARK: - Sessions

    /// Fetch sessions for an agent (or all agents)
    func fetchSessions(agent: String? = nil) async -> [AgentSession] {
        var cmd = "openclaw sessions --json"
        if let agent {
            cmd += " --agent \(agent)"
        } else {
            cmd += " --all-agents"
        }
        let result = await shell.run(cmd, recordHistory: false)
        if result.exitCode == 0, let data = result.output.data(using: .utf8) {
            if let response = try? JSONDecoder().decode(SessionsResponse.self, from: data) {
                return response.sessions ?? []
            }
        }
        return []
    }

    // MARK: - Chat / Messaging

    /// Send a message to an agent and get the response
    func sendMessage(to agent: String, message: String, sessionId: String? = nil) async -> CommandResult {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        var cmd = "openclaw agent --to \(agent) --message \"\(escaped)\""
        if let sessionId, !sessionId.isEmpty {
            cmd += " --session-id \(sessionId)"
        }
        return await shell.run(cmd)
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

    /// Login to a channel
    func channelLogin(channel: String) async -> CommandResult {
        return await shell.run("openclaw channels login --channel \(channel)")
    }

    /// Logout from a channel
    func channelLogout(channel: String) async -> CommandResult {
        return await shell.run("openclaw channels logout --channel \(channel)")
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

    /// Get a config value
    func configGet(_ key: String) async -> CommandResult {
        return await shell.run("openclaw config get \(key)")
    }

    /// Set a config value
    func configSet(_ key: String, value: String) async -> CommandResult {
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
        shell.commandHistory
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

                parsed.append(Agent(
                    agentId: name,
                    workspace: workspace,
                    agentDir: nil,
                    model: nil,
                    bindingsCount: nil,
                    isDefault: nil,
                    routes: nil
                ))
            }
        }

        return parsed
    }
}

/// Wrapper in case JSON output wraps agents in an object
private struct AgentsWrapper: Codable {
    let agents: [Agent]
}
