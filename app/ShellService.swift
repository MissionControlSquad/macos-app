import Foundation

/// Low-level shell command executor.
/// Use OpenClawService for all OpenClaw-specific operations.
@MainActor
@Observable
class ShellService {
    var isRunning = false
    var commandHistory: [CommandResult] = []

    /// Run any shell command and return the result
    /// Set `recordHistory` to false for internal/bulk commands to avoid bloating command history.
    @discardableResult
    func run(_ command: String, recordHistory: Bool = true) async -> CommandResult {
        isRunning = true

        let result = await runShellCommand(command)

        if recordHistory {
            commandHistory.insert(result, at: 0)
        }
        isRunning = false
        return result
    }

    /// Start a long-running/streaming command. Returns a handle to read output and stop it.
    func startStreaming(_ command: String) -> StreamingProcess {
        return StreamingProcess(command: command, env: Self.buildEnv())
    }

    /// Build the environment dict with extra PATH entries
    nonisolated private static func buildEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var extraPaths = [
            "\(homeDir)/.local/bin",
            "\(homeDir)/.cargo/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin"
        ]
        // Add NVM node paths (find the latest installed version)
        let nvmDir = "\(homeDir)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = versions.sorted { a, b in
                // Sort by version descending so latest is first
                a.compare(b, options: .numeric) == .orderedDescending
            }
            for version in sorted {
                let binPath = "\(nvmDir)/\(version)/bin"
                if FileManager.default.fileExists(atPath: "\(binPath)/node") {
                    extraPaths.insert(binPath, at: 0)
                    break  // Use the latest version only
                }
            }
        }
        if let existingPath = env["PATH"] {
            env["PATH"] = extraPaths.joined(separator: ":") + ":" + existingPath
        }
        return env
    }

    /// Execute the shell command off the main thread
    private nonisolated func runShellCommand(_ command: String) async -> CommandResult {
        let startTime = Date()
        print("[Shell] ▶ Running: \(command)")

        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = ShellService.buildEnv()

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    let result = CommandResult(
                        command: command,
                        output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                        timestamp: Date(),
                        exitCode: process.terminationStatus
                    )
                    continuation.resume(returning: result)
                } catch {
                    let result = CommandResult(
                        command: command,
                        output: "Error: \(error.localizedDescription)",
                        timestamp: Date(),
                        exitCode: -1
                    )
                    continuation.resume(returning: result)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let outputPreview = result.output.prefix(200)
        let truncated = result.output.count > 200 ? "... (\(result.output.count) chars total)" : ""
        print("[Shell] ✅ Done: \(command)")
        print("[Shell]    Exit code: \(result.exitCode) | Duration: \(String(format: "%.2f", elapsed))s | Output: \(outputPreview)\(truncated)")

        return result
    }

    /// Open Terminal.app and run a command interactively.
    /// Use this for commands that need user input (passwords, wizards, etc.)
    nonisolated func openInTerminal(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                print("[Shell] AppleScript error: \(error)")
            }
        }
    }
}

// MARK: - Streaming Process

/// A handle for a long-running shell process that streams output line by line.
@MainActor
@Observable
class StreamingProcess {
    var output: String = ""
    var isRunning = false
    var exitCode: Int32 = 0

    private var process: Process?
    private let command: String
    private let env: [String: String]

    nonisolated init(command: String, env: [String: String]) {
        self.command = command
        self.env = env
    }

    /// Start the streaming process and append output as it arrives
    func start() {
        guard !isRunning else { return }
        isRunning = true
        output = ""
        exitCode = 0

        print("[Shell:Stream] ▶ Starting: \(command)")

        let proc = Process()
        let pipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", command]
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.environment = env
        self.process = proc

        // Read data as it arrives on a background queue
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.output += text
                }
            }
        }

        proc.terminationHandler = { [weak self] proc in
            print("[Shell:Stream] ⏹ Ended: exit code \(proc.terminationStatus)")
            Task { @MainActor [weak self] in
                self?.exitCode = proc.terminationStatus
                self?.isRunning = false
            }
        }

        do {
            try proc.run()
            print("[Shell:Stream] ✅ Process launched (PID: \(proc.processIdentifier))")
        } catch {
            print("[Shell:Stream] ❌ Failed to start: \(error.localizedDescription)")
            output = "Error: \(error.localizedDescription)"
            isRunning = false
        }
    }

    /// Stop the streaming process
    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }
}

