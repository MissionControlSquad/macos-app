import Foundation
import CryptoKit

// MARK: - Gateway WebSocket Connection

/// Manages a WebSocket connection to the OpenClaw Gateway (ws://127.0.0.1:18789).
/// Implements the exact protocol used by OpenClaw's WebChat:
///
/// 1. Gateway sends `connect.challenge` event with nonce
/// 2. Client sends `connect` request with protocol version + client info
/// 3. Gateway responds with `hello-ok` payload
/// 4. After handshake: `req(method, params)` -> `res(ok/payload|error)`
/// 5. Gateway pushes `event` frames for agent streaming, presence, ticks, etc.
@MainActor
@Observable
class GatewayWebSocket {

    // MARK: - Public State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    var state: ConnectionState = .disconnected
    var isConnected: Bool { state == .connected }

    /// Accumulated text from the current agent run (streamed deltas)
    var streamingText = ""
    var isAgentRunning = false
    /// The runId of the current agent execution
    var currentRunId: String?

    /// Pending approval requests pushed by the gateway
    var pendingApprovals: [[String: Any]] = []
    /// Connected devices/nodes from presence events
    var presenceEntries: [[String: Any]] = []

    // MARK: - Private

    private var wsTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveLoop: Task<Void, Never>?
    private var pingLoop: Task<Void, Never>?

    /// Pending RPC requests waiting for a response
    private var pending: [String: CheckedContinuation<GatewayPayload, Error>] = [:]

    /// Nonce from the connect.challenge event
    private var challengeNonce: String?

    private let port: Int

    /// Loaded device identity for Ed25519 signing
    private var deviceIdentity: DeviceIdentity?
    /// Loaded device auth token
    private var deviceAuth: DeviceAuth?

    init(port: Int = 18789) {
        self.port = port
        loadDeviceCredentials()
    }

    // MARK: - Connect / Disconnect

    func connect() {
        guard state == .disconnected || state == .error("") || {
            if case .error = state { return true }
            return false
        }() else { return }

        state = .connecting
        let url = URL(string: "ws://127.0.0.1:\(port)")!
        let session = URLSession(configuration: .default)
        self.urlSession = session

        let task = session.webSocketTask(with: url)
        self.wsTask = task
        task.resume()

        print("[GW] Connecting to \(url)...")
        startReceiveLoop()
        startPingLoop()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        receiveLoop?.cancel()
        pingLoop?.cancel()
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        urlSession = nil
        state = .disconnected
        // Fail any pending requests
        for (_, cont) in pending {
            cont.resume(throwing: GatewayError.disconnected)
        }
        pending.removeAll()
        challengeNonce = nil
        print("[GW] Disconnected")
    }

    // MARK: - RPC Methods

    /// List all sessions from the gateway
    func sessionsList() async throws -> GatewaySessionsListResponse {
        let payload = try await rpc("sessions.list", params: [:])
        let data = try JSONSerialization.data(withJSONObject: payload.raw)
        return try JSONDecoder().decode(GatewaySessionsListResponse.self, from: data)
    }

    /// Load chat history for a session key
    func chatHistory(sessionKey: String) async throws -> GatewayChatHistoryResponse {
        let payload = try await rpc("chat.history", params: ["sessionKey": sessionKey])
        let data = try JSONSerialization.data(withJSONObject: payload.raw)
        return try JSONDecoder().decode(GatewayChatHistoryResponse.self, from: data)
    }

    /// Send a chat message (triggers agent run, returns with status: "started" + runId)
    func chatSend(sessionKey: String, message: String) async throws -> GatewayPayload {
        streamingText = ""
        currentRunId = nil
        let result = try await rpc("chat.send", params: [
            "sessionKey": sessionKey,
            "message": message,
            "idempotencyKey": UUID().uuidString
        ])
        // The response includes status: "started" and runId
        if let runId = result["runId"] as? String {
            currentRunId = runId
        }
        if result["status"] as? String == "started" {
            isAgentRunning = true
        }
        return result
    }

    /// Inject a note into the transcript without triggering an agent run
    func chatInject(sessionKey: String, content: String) async throws -> GatewayPayload {
        return try await rpc("chat.inject", params: [
            "sessionKey": sessionKey,
            "content": content
        ])
    }

    /// Patch session settings (model, thinking level, etc.)
    func sessionsPatch(sessionKey: String, patch: [String: Any]) async throws -> GatewayPayload {
        return try await rpc("sessions.patch", params: [
            "sessionKey": sessionKey,
            "patch": patch
        ])
    }

    /// Reset a session (archives old transcript, creates new sessionId under the same key)
    func sessionsReset(sessionKey: String) async throws -> GatewayPayload {
        return try await rpc("sessions.reset", params: [
            "sessionKey": sessionKey
        ])
    }

    /// Delete a session
    func sessionsDelete(sessionKey: String) async throws -> GatewayPayload {
        return try await rpc("sessions.delete", params: [
            "sessionKey": sessionKey
        ])
    }

    /// Get gateway health
    func health() async throws -> GatewayPayload {
        return try await rpc("health", params: [:])
    }

    /// Get system presence (connected devices)
    func systemPresence() async throws -> GatewayPayload {
        return try await rpc("system-presence", params: [:])
    }

    /// Abort a running chat
    func chatAbort(sessionKey: String) async throws -> GatewayPayload {
        isAgentRunning = false
        return try await rpc("chat.abort", params: ["sessionKey": sessionKey])
    }

    // MARK: - Approvals

    /// Get current approval settings
    func approvalsGet() async throws -> GatewayPayload {
        return try await rpc("exec.approvals.get", params: [:])
    }

    /// Resolve (approve/reject) a pending approval
    func approvalResolve(requestId: String, decision: String) async throws -> GatewayPayload {
        return try await rpc("exec.approval.resolve", params: [
            "requestId": requestId,
            "decision": decision
        ])
    }

    // MARK: - Usage & Cost

    /// Get usage statistics
    func usageStatus() async throws -> GatewayPayload {
        return try await rpc("usage.status", params: [:])
    }

    /// Get cost breakdown
    func usageCost() async throws -> GatewayPayload {
        return try await rpc("usage.cost", params: [:])
    }

    // MARK: - Cron

    /// List cron jobs
    func cronList() async throws -> GatewayPayload {
        return try await rpc("cron.list", params: [:])
    }

    /// Get cron status
    func cronStatus() async throws -> GatewayPayload {
        return try await rpc("cron.status", params: [:])
    }

    /// Add a cron job
    func cronAdd(name: String, schedule: String, message: String) async throws -> GatewayPayload {
        return try await rpc("cron.add", params: [
            "name": name,
            "schedule": schedule,
            "message": message
        ])
    }

    /// Remove a cron job
    func cronRemove(name: String) async throws -> GatewayPayload {
        return try await rpc("cron.remove", params: ["name": name])
    }

    /// Run a cron job now
    func cronRun(name: String) async throws -> GatewayPayload {
        return try await rpc("cron.run", params: ["name": name])
    }

    /// Get cron run history
    func cronRuns(name: String? = nil) async throws -> GatewayPayload {
        var params: [String: Any] = [:]
        if let name { params["name"] = name }
        return try await rpc("cron.runs", params: params)
    }

    // MARK: - Device & Node Management

    /// List paired and pending devices
    func devicePairList() async throws -> GatewayPayload {
        return try await rpc("device.pair.list", params: [:])
    }

    /// Approve a device pairing request
    func devicePairApprove(requestId: String) async throws -> GatewayPayload {
        return try await rpc("device.pair.approve", params: ["requestId": requestId])
    }

    /// Reject a device pairing request
    func devicePairReject(requestId: String) async throws -> GatewayPayload {
        return try await rpc("device.pair.reject", params: ["requestId": requestId])
    }

    /// Remove a paired device
    func devicePairRemove(deviceId: String) async throws -> GatewayPayload {
        return try await rpc("device.pair.remove", params: ["deviceId": deviceId])
    }

    /// Rotate device token
    func deviceTokenRotate() async throws -> GatewayPayload {
        return try await rpc("device.token.rotate", params: [:])
    }

    // MARK: - Tools Catalog

    /// Get available tools catalog
    func toolsCatalog() async throws -> GatewayPayload {
        return try await rpc("tools.catalog", params: [:])
    }

    // MARK: - Config

    /// Get config schema
    func configSchema() async throws -> GatewayPayload {
        return try await rpc("config.schema", params: [:])
    }

    /// Get a config value
    func configGet(key: String) async throws -> GatewayPayload {
        return try await rpc("config.get", params: ["key": key])
    }

    /// Set a config value
    func configSet(key: String, value: Any) async throws -> GatewayPayload {
        return try await rpc("config.set", params: ["key": key, "value": value])
    }

    // MARK: - Agents (via gateway)

    /// List agents via gateway
    func agentsList() async throws -> GatewayPayload {
        return try await rpc("agents.list", params: [:])
    }

    // MARK: - Models

    /// List available models
    func modelsList() async throws -> GatewayPayload {
        return try await rpc("models.list", params: [:])
    }

    // MARK: - Low-Level RPC

    private func rpc(_ method: String, params: [String: Any]) async throws -> GatewayPayload {
        guard let ws = wsTask, state == .connected else {
            throw GatewayError.notConnected
        }

        let id = UUID().uuidString
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: frame)
        let text = String(data: data, encoding: .utf8)!

        print("[GW] -> \(method) (\(id.prefix(8)))")

        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont

            Task {
                do {
                    try await ws.send(.string(text))
                } catch {
                    if let c = pending.removeValue(forKey: id) {
                        c.resume(throwing: error)
                    }
                }
            }

            // 60s timeout
            Task {
                try? await Task.sleep(for: .seconds(60))
                if let c = pending.removeValue(forKey: id) {
                    c.resume(throwing: GatewayError.timeout)
                }
            }
        }
    }

    // MARK: - Receive Loop

    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = true

    private func startReceiveLoop() {
        receiveLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let ws = self.wsTask else { break }
                do {
                    let msg = try await ws.receive()
                    self.handleFrame(msg)
                } catch {
                    if !Task.isCancelled {
                        print("[GW] Receive error: \(error)")
                        self.state = .error("Connection lost")
                        self.scheduleReconnect()
                    }
                    break
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            // Exponential backoff: 2s, 4s, 8s, max 30s
            var delay: UInt64 = 2
            for attempt in 1...10 {
                guard !Task.isCancelled else { return }
                print("[GW] Reconnecting in \(delay)s (attempt \(attempt))...")
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }

                // Clean up old connection
                self.wsTask?.cancel(with: .goingAway, reason: nil)
                self.wsTask = nil
                self.challengeNonce = nil
                for (_, cont) in self.pending {
                    cont.resume(throwing: GatewayError.disconnected)
                }
                self.pending.removeAll()

                // Try reconnecting
                self.state = .connecting
                let url = URL(string: "ws://127.0.0.1:\(self.port)")!
                let session = URLSession(configuration: .default)
                self.urlSession = session
                let task = session.webSocketTask(with: url)
                self.wsTask = task
                task.resume()
                self.startReceiveLoop()
                self.startPingLoop()

                // Wait to see if connection succeeds
                try? await Task.sleep(for: .seconds(3))
                if self.isConnected {
                    print("[GW] Reconnected successfully")
                    return
                }
                delay = min(delay * 2, 30)
            }
            print("[GW] Gave up reconnecting after 10 attempts")
        }
    }

    private func startPingLoop() {
        pingLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.wsTask?.sendPing { _ in }
            }
        }
    }

    // MARK: - Frame Handling

    private func handleFrame(_ msg: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = msg,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "event":
            handleEvent(json)
        case "res":
            handleResponse(json)
        default:
            print("[GW] Unknown frame type: \(type)")
        }
    }

    private func handleEvent(_ json: [String: Any]) {
        guard let event = json["event"] as? String else { return }
        let payload = json["payload"] as? [String: Any] ?? [:]

        switch event {
        case "connect.challenge":
            // Step 1: Save nonce, send connect request
            challengeNonce = payload["nonce"] as? String
            print("[GW] Got challenge, nonce=\(challengeNonce?.prefix(8) ?? "nil")")
            sendConnectRequest()

        case "agent":
            handleAgentEvent(payload)

        case "chat":
            handleChatEvent(payload)

        case "tick", "heartbeat", "health":
            break // Silent

        case "presence":
            if let entries = payload["entries"] as? [[String: Any]] {
                presenceEntries = entries
            }

        case "exec.approval.requested":
            pendingApprovals.append(payload)
            print("[GW] Approval requested: \(payload["requestId"] ?? "?")")

        case "exec.approval.resolved":
            let resolvedId = payload["requestId"] as? String
            pendingApprovals.removeAll { $0["requestId"] as? String == resolvedId }

        case "shutdown":
            print("[GW] Gateway shutting down")
            state = .error("Gateway shutting down")

        default:
            print("[GW] Event: \(event)")
        }
    }

    private func handleResponse(_ json: [String: Any]) {
        guard let id = json["id"] as? String else { return }
        let ok = json["ok"] as? Bool ?? false
        let payload = json["payload"] as? [String: Any] ?? [:]

        // Check if this is the hello-ok from connect
        if payload["type"] as? String == "hello-ok" {
            print("[GW] Connected (hello-ok), protocol=\(payload["protocol"] ?? "?")")
            state = .connected
            // Extract initial presence from snapshot
            if let snapshot = payload["snapshot"] as? [String: Any],
               let presence = snapshot["presence"] as? [[String: Any]] {
                presenceEntries = presence
            }
        }

        print("[GW] <- res \(id.prefix(8)) ok=\(ok)")

        if let cont = pending.removeValue(forKey: id) {
            if ok {
                cont.resume(returning: GatewayPayload(raw: payload))
            } else {
                let errMsg = (json["error"] as? [String: Any])?["message"] as? String
                    ?? json["error"] as? String
                    ?? "Unknown error"
                cont.resume(throwing: GatewayError.serverError(errMsg))
            }
        }
    }

    // MARK: - Device Identity

    /// Load device credentials from ~/.openclaw/identity/
    private func loadDeviceCredentials() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let identityDir = "\(home)/.openclaw/identity"

        // Load device.json (keypair + deviceId)
        if let data = FileManager.default.contents(atPath: "\(identityDir)/device.json"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            deviceIdentity = DeviceIdentity(
                deviceId: json["deviceId"] as? String ?? "",
                publicKeyPem: json["publicKeyPem"] as? String ?? "",
                privateKeyPem: json["privateKeyPem"] as? String ?? ""
            )
            print("[GW] Loaded device identity: \(deviceIdentity!.deviceId.prefix(16))...")
        } else {
            print("[GW] Warning: Could not load device identity")
        }

        // Load device-auth.json (operator token)
        if let data = FileManager.default.contents(atPath: "\(identityDir)/device-auth.json"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokens = json["tokens"] as? [String: Any],
           let operator_ = tokens["operator"] as? [String: Any] {
            deviceAuth = DeviceAuth(
                token: operator_["token"] as? String ?? "",
                role: operator_["role"] as? String ?? "operator",
                scopes: operator_["scopes"] as? [String] ?? []
            )
            print("[GW] Loaded device auth token")
        } else {
            print("[GW] Warning: Could not load device auth token")
        }
    }

    // MARK: - Connect Handshake

    private func sendConnectRequest() {
        guard let identity = deviceIdentity, let auth = deviceAuth else {
            print("[GW] Cannot connect: missing device credentials")
            state = .error("Missing device credentials")
            return
        }

        guard let nonce = challengeNonce else {
            print("[GW] Cannot connect: no challenge nonce")
            state = .error("No challenge nonce received")
            return
        }

        // Build Ed25519 signature
        let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        let clientId = "openclaw-macos"
        let clientMode = "ui"
        let platform = "darwin"

        // v3 payload: v3|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce|platform|deviceFamily
        let payloadStr = [
            "v3",
            identity.deviceId,
            clientId,
            clientMode,
            auth.role,
            auth.scopes.joined(separator: ","),
            String(signedAtMs),
            auth.token,
            nonce,
            platform,
            "" // deviceFamily (empty)
        ].joined(separator: "|")

        guard let signature = signWithEd25519(payload: payloadStr, privateKeyPem: identity.privateKeyPem) else {
            print("[GW] Failed to sign connect payload")
            state = .error("Ed25519 signing failed")
            return
        }

        // Get raw public key bytes as base64url
        let publicKeyB64url = extractRawPublicKeyBase64url(from: identity.publicKeyPem) ?? ""

        let id = UUID().uuidString
        let params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": clientId,
                "version": "1.0.0",
                "platform": platform,
                "mode": clientMode
            ] as [String: Any],
            "role": auth.role,
            "scopes": auth.scopes,
            "caps": [] as [String],
            "locale": "en-US",
            "userAgent": "openclaw-macos/1.0",
            "device": [
                "id": identity.deviceId,
                "publicKey": publicKeyB64url,
                "signature": signature,
                "signedAt": signedAtMs,
                "nonce": nonce
            ] as [String: Any],
            "auth": [
                "deviceToken": auth.token
            ] as [String: Any]
        ]

        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": "connect",
            "params": params
        ]

        Task {
            guard let data = try? JSONSerialization.data(withJSONObject: frame),
                  let text = String(data: data, encoding: .utf8) else { return }
            do {
                try await wsTask?.send(.string(text))
                print("[GW] -> connect (\(id.prefix(8))) with device auth")
            } catch {
                print("[GW] Failed to send connect: \(error)")
                state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Ed25519 Signing

    /// Sign a payload string with Ed25519 private key, return base64url signature
    private func signWithEd25519(payload: String, privateKeyPem: String) -> String? {
        guard let keyData = pemToRawPrivateKey(privateKeyPem) else {
            print("[GW] Failed to parse private key PEM")
            return nil
        }

        do {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
            let payloadData = Data(payload.utf8)
            let signature = try privateKey.signature(for: payloadData)
            return base64urlEncode(signature)
        } catch {
            print("[GW] Ed25519 signing error: \(error)")
            return nil
        }
    }

    /// Extract raw 32-byte private key from PEM (PKCS8 DER wrapper for Ed25519)
    private func pemToRawPrivateKey(_ pem: String) -> Data? {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let derData = Data(base64Encoded: stripped) else { return nil }

        // PKCS8 DER for Ed25519: 48 bytes total, last 32 bytes are the raw key
        // Format: 30 2e 02 01 00 30 05 06 03 2b 65 70 04 22 04 20 <32 bytes>
        // The raw key starts at offset 16
        guard derData.count >= 48 else { return nil }
        return derData.suffix(32)
    }

    /// Extract raw 32-byte public key from PEM and encode as base64url
    private func extractRawPublicKeyBase64url(from pem: String) -> String? {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let derData = Data(base64Encoded: stripped) else { return nil }

        // SPKI DER for Ed25519: 44 bytes total, last 32 bytes are the raw key
        // Format: 30 2a 30 05 06 03 2b 65 70 03 21 00 <32 bytes>
        guard derData.count >= 44 else { return nil }
        let rawKey = derData.suffix(32)
        return base64urlEncode(rawKey)
    }

    /// Base64url encode data (no padding)
    private func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Agent Event Handling

    /// Handle "agent" events: stream=lifecycle (start/end), stream=assistant (text deltas)
    private func handleAgentEvent(_ payload: [String: Any]) {
        let runId = payload["runId"] as? String
        let stream = payload["stream"] as? String
        let data = payload["data"] as? [String: Any] ?? [:]

        if let runId { currentRunId = runId }

        switch stream {
        case "lifecycle":
            let phase = data["phase"] as? String
            if phase == "start" {
                isAgentRunning = true
                print("[GW] Agent run started: \(runId ?? "?")")
            } else if phase == "end" {
                isAgentRunning = false
                print("[GW] Agent run ended: \(runId ?? "?")")
            }

        case "assistant":
            // Streaming text delta from the agent
            if let delta = data["delta"] as? String {
                streamingText += delta
            }

        case "error":
            isAgentRunning = false
            let error = data["message"] as? String ?? payload["error"] as? String ?? "Unknown error"
            print("[GW] Agent run error: \(error)")

        default:
            break
        }
    }

    /// Handle "chat" events: state=delta (partial), state=final (complete message)
    private func handleChatEvent(_ payload: [String: Any]) {
        // Chat events carry the full message; we use agent stream for real-time deltas
        // The "final" state confirms the run is done
        let state = payload["state"] as? String
        if state == "final" {
            isAgentRunning = false
        }
    }

    /// Wait until the current agent run finishes
    func waitForAgentCompletion() async {
        while isAgentRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

// MARK: - Types

struct GatewayPayload {
    let raw: [String: Any]

    subscript(key: String) -> Any? { raw[key] }
}

/// Device identity loaded from ~/.openclaw/identity/device.json
struct DeviceIdentity {
    let deviceId: String
    let publicKeyPem: String
    let privateKeyPem: String
}

/// Device auth token loaded from ~/.openclaw/identity/device-auth.json
struct DeviceAuth {
    let token: String
    let role: String
    let scopes: [String]
}

enum GatewayError: LocalizedError {
    case notConnected
    case disconnected
    case timeout
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to gateway"
        case .disconnected: return "Disconnected from gateway"
        case .timeout: return "Request timed out"
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - Sessions List Response (matches actual gateway output)

struct GatewaySessionsListResponse: Codable {
    let ts: Double?
    let path: String?
    let count: Int?
    let defaults: GatewaySessionDefaults?
    let sessions: [GatewaySession]?
}

struct GatewaySessionDefaults: Codable {
    let modelProvider: String?
    let model: String?
    let contextTokens: Int?
}

struct GatewaySession: Identifiable, Codable {
    var id: String { sessionId ?? key }
    let key: String
    let kind: String?
    let displayName: String?
    let chatType: String?
    let origin: GatewaySessionOrigin?
    let updatedAt: Double?
    let sessionId: String?
    let systemSent: Bool?
    let abortedLastRun: Bool?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let totalTokensFresh: Bool?
    let modelProvider: String?
    let model: String?
    let contextTokens: Int?
    let lastChannel: String?

    /// Extract agent ID from the session key (agent:<agentId>:...)
    var agentId: String? {
        let parts = key.components(separatedBy: ":")
        guard parts.count >= 2, parts[0] == "agent" else { return nil }
        return parts[1]
    }
}

struct GatewaySessionOrigin: Codable {
    let label: String?
    let provider: String?
    let surface: String?
    let chatType: String?
}

// MARK: - Chat History Response (matches actual gateway output)

struct GatewayChatHistoryResponse: Codable {
    let sessionKey: String?
    let sessionId: String?
    let messages: [GatewayChatMsg]?

    /// Convert to display-friendly ChatMessages, filtering to user + assistant text only
    func toChatMessages() -> [ChatMessage] {
        guard let messages else { return [] }
        var result: [ChatMessage] = []

        for msg in messages {
            guard let role = msg.role else { continue }

            // Only show user and assistant messages
            guard role == "user" || role == "assistant" else { continue }

            let chatRole: ChatRole = role == "user" ? .user : .agent

            // Extract text content from content blocks
            let textParts = (msg.content ?? []).compactMap { block -> String? in
                if block.type == "text" { return block.text }
                return nil
            }
            let text = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            // Timestamp is epoch ms
            let date: Date
            if let ts = msg.timestamp {
                date = Date(timeIntervalSince1970: ts / 1000.0)
            } else {
                date = Date()
            }

            result.append(ChatMessage(role: chatRole, content: text, timestamp: date))
        }

        return result
    }
}

struct GatewayChatMsg: Codable {
    let role: String?
    let content: [GatewayChatBlock]?
    let timestamp: Double?
    let senderLabel: String?
    let api: String?
    let provider: String?
    let model: String?
    let stopReason: String?
}

struct GatewayChatBlock: Codable {
    let type: String?
    let text: String?
    let thinking: String?
    let name: String?
    let id: String?
    // toolCall fields
    let arguments: [String: AnyCodable]?
}

/// Wrapper for heterogeneous JSON values in Codable contexts
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let int = value as? Int { try container.encode(int) }
        else if let double = value as? Double { try container.encode(double) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else { try container.encode("") }
    }
}
