import Foundation

/// Low-level shell command executor.
/// Use OpenClawService for all OpenClaw-specific operations.
@MainActor
@Observable
class ShellService {
    var isRunning = false
    var commandHistory: [CommandResult] = []

    /// Run any shell command and return the result
    @discardableResult
    func run(_ command: String) async -> CommandResult {
        isRunning = true

        let result = await runShellCommand(command)

        commandHistory.insert(result, at: 0)
        isRunning = false
        return result
    }

    /// Execute the shell command off the main thread
    private nonisolated func runShellCommand(_ command: String) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                process.standardOutput = pipe
                process.standardError = pipe

                var env = ProcessInfo.processInfo.environment
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                let extraPaths = [
                    "\(homeDir)/.local/bin",
                    "\(homeDir)/.cargo/bin",
                    "/usr/local/bin",
                    "/opt/homebrew/bin"
                ]
                if let existingPath = env["PATH"] {
                    env["PATH"] = extraPaths.joined(separator: ":") + ":" + existingPath
                }
                process.environment = env

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
    }
}
