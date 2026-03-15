import SwiftUI

enum AgentTab: String, CaseIterable {
    case chat = "Chat"
    case files = "Files"
    case sessions = "Sessions"
    case model = "Model"
    case info = "Info"

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .files: return "doc.text.fill"
        case .sessions: return "clock.fill"
        case .model: return "cpu"
        case .info: return "info.circle.fill"
        }
    }
}

struct AgentDetailView: View {
    let agent: Agent
    @Bindable var service: OpenClawService
    var initialSessionId: String? = nil
    var onDeleted: (() -> Void)? = nil
    @State private var selectedTab: AgentTab = .chat

    // Gateway WebSocket
    @State private var gateway = GatewayWebSocket()

    // Chat state
    @State private var messageText = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var isSending = false
    @State private var streamingProcess: StreamingProcess?
    @State private var activeSessionKey: String?
    @State private var slashCommandResult: String?

    // Files state
    @State private var workspaceFiles: [WorkspaceFile] = []
    @State private var selectedFileContent: String?
    @State private var selectedFileName: String?
    @State private var currentDirectory: String = "" // relative path within workspace
    @State private var isLoadingFiles = false

    // Sessions state
    @State private var sessions: [AgentSession] = []
    @State private var selectedSession: AgentSession?
    @State private var activeSessionId: String?
    @State private var isLoadingHistory = false
    @State private var isLoadingSessions = true

    // Confirmation dialogs
    @State private var showDeleteConfirm = false
    @State private var showRestartGatewayConfirm = false
    @State private var toast = ToastState()

    // Per-agent model & auth
    @State private var agentModel = ""
    @State private var showModelChooser = false
    @State private var showAPIKeySheet = false
    @State private var apiKeyOverrideProvider = ""
    @State private var agentAuthOverrides: Set<String> = []
    @State private var validatingProvider = ""
    @State private var providerValidationResults: [String: Bool] = [:]

    // Identity editing
    @State private var editDisplayName = ""
    @State private var editEmoji = ""

    // Channel bindings
    @State private var agentBindings: [String] = []
    @State private var isLoadingBindings = true
    @State private var showAddBindingPopover = false
    @State private var newBindingChannel = ""
    @State private var newBindingAccountId = ""
    @State private var isBindingBusy = false

    // Usage stats
    @State private var usageOutput = ""
    @State private var isLoadingUsage = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            switch selectedTab {
            case .chat:
                chatView
            case .files:
                filesView
            case .sessions:
                sessionsView
            case .model:
                modelView
            case .info:
                infoView
            }
        }
        .navigationTitle(agent.displayName ?? agent.name)
        .navigationSubtitle(agent.agentStatus.label)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                StatusBadge(label: agent.agentStatus.label, color: agentColor(agent.agentStatus))
            }
        }
        .toastOverlay(toast)
        .confirmationDialog(
            "Delete Agent",
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete \"\(agent.displayName ?? agent.name)\"", role: .destructive) {
                Task {
                    let agentName = agent.displayName ?? agent.name
                    let result = await service.deleteAgent(name: agent.name)
                    if result.exitCode == 0 {
                        toast.show("Agent \"\(agentName)\" deleted")
                        onDeleted?()
                    } else {
                        toast.show("Failed to delete agent: \(result.output)", isError: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will unbind all channel routes, remove the agent registry entry, and trash its workspace and session data. This cannot be undone.")
        }
        .confirmationDialog(
            "Restart Gateway",
            isPresented: $showRestartGatewayConfirm
        ) {
            Button("Restart Gateway", role: .destructive) {
                Task {
                    let result = await service.runCommand("openclaw gateway restart")
                    if result.exitCode == 0 {
                        toast.show("Gateway restarted successfully")
                    } else {
                        toast.show("Gateway restart failed: \(result.output)", isError: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restarting the gateway will briefly disconnect all active sessions. Continue?")
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(AgentTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chatMessages.isEmpty {
                            if isLoadingHistory {
                                LoadingStateView(message: "Loading chat history...")
                                    .padding(.top, 60)
                            } else {
                                EmptyStateView(
                                    icon: "bubble.left.and.bubble.right",
                                    title: "Start a Conversation",
                                    message: "Send a message to start chatting with \(agent.name)"
                                )
                                .padding(.top, 60)
                            }
                        }

                        ForEach(chatMessages) { message in
                            chatBubble(message)
                                .id(message.id)
                        }

                        if isSending {
                            let streamText = gateway.isConnected ? gateway.streamingText : streamingProcess?.output ?? ""
                            if !streamText.isEmpty {
                                // Show streaming response as it arrives
                                VStack(alignment: .leading, spacing: 4) {
                                    MarkdownTextView(content: streamText)

                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.mini)
                                            .tint(Color.accentColor)
                                        Text("Responding...")
                                            .font(.caption2)
                                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                        Spacer()
                                        Button {
                                            abortCurrentRun()
                                        } label: {
                                            Label("Stop", systemImage: "stop.fill")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                        .tint(Color.red)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .id("streaming")
                            } else {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.accentColor)
                                    Text("Thinking...")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        abortCurrentRun()
                                    } label: {
                                        Label("Stop", systemImage: "stop.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .tint(Color.red)
                                }
                                .padding(.horizontal)
                                .id("thinking")
                            }
                        }

                        // Slash command result
                        if let result = slashCommandResult {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .foregroundStyle(.secondary)
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                }
                .onChange(of: chatMessages.count) {
                    if let last = chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: isSending) {
                    if isSending {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
                .onChange(of: streamingProcess?.output) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onChange(of: gateway.streamingText) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Message input
            VStack(spacing: 6) {
                // Session & connection status bar
                HStack(spacing: 8) {
                    // Gateway connection indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(gateway.isConnected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(gateway.isConnected ? "Gateway" : "CLI")
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Connection: \(gateway.isConnected ? "Gateway" : "CLI")")

                    // Session switcher menu
                    Menu {
                        Button {
                            startNewSession()
                        } label: {
                            Label("New Session", systemImage: "plus.bubble")
                        }

                        if !sessions.isEmpty {
                            Divider()

                            ForEach(sessions) { session in
                                Button {
                                    Task { await openSession(session) }
                                } label: {
                                    HStack {
                                        if activeSessionKey == session.key {
                                            Image(systemName: "checkmark")
                                        }
                                        Text(sessionMenuLabel(session))
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.caption2)
                            if let key = activeSessionKey {
                                Text(sessionDisplayKey(key))
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                            } else {
                                Text("New Session")
                                    .font(.caption2)
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()

                    // Session metrics (from gateway sessions data)
                    if let session = sessions.first(where: { $0.key == activeSessionKey }) {
                        HStack(spacing: 8) {
                            if let input = session.inputTokens, input > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.doc")
                                        .font(.caption2)
                                    Text(formatTokenCount(input))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Input tokens")
                            }
                            if let output = session.outputTokens, output > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.down.doc")
                                        .font(.caption2)
                                    Text(formatTokenCount(output))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Output tokens")
                            }
                            if let total = session.totalTokens, total > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "sum")
                                        .font(.caption2)
                                    Text(formatTokenCount(total))
                                }
                                .font(.caption2)
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                .help("Total tokens")
                            }
                            if let model = session.model, !model.isEmpty {
                                Text(model.components(separatedBy: "/").last ?? model)
                                    .font(.caption2)
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                    .lineLimit(1)
                            }
                        }
                    }

                    Button {
                        startNewSession()
                    } label: {
                        Label("New Chat", systemImage: "plus.bubble")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                HStack(spacing: 8) {
                    TextField("Message \(agent.name)... (/ for commands)", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .onSubmit { sendMessage() }

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(messageText.isEmpty || isSending ? Color(nsColor: .tertiaryLabelColor) : Color.accentColor)
                    .disabled(messageText.isEmpty || isSending)
                }
            }
            .padding(12)
        }
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                MarkdownTextView(content: message.content)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubbleBackground(message.role))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private func bubbleBackground(_ role: ChatRole) -> Color {
        switch role {
        case .user: return Color.accentColor.opacity(0.15)
        case .agent: return Color(nsColor: .controlBackgroundColor)
        case .error: return Color.red.opacity(0.1)
        }
    }

    // MARK: - Files View

    private var filesView: some View {
        HSplitView {
            // File sidebar with navigation
            VStack(spacing: 0) {
                // Breadcrumb / path bar
                HStack(spacing: 4) {
                    // Home button (workspace root)
                    Button {
                        navigateToDirectory("")
                    } label: {
                        Image(systemName: "house.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(currentDirectory.isEmpty ? .primary : .secondary)

                    if !currentDirectory.isEmpty {
                        // Show breadcrumb path segments
                        let segments = currentDirectory.components(separatedBy: "/").filter { !$0.isEmpty }
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                            Button {
                                // Navigate to this level
                                let path = segments.prefix(index + 1).joined(separator: "/")
                                navigateToDirectory(path)
                            } label: {
                                Text(segment)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(index == segments.count - 1 ? .primary : .secondary)
                        }
                    }

                    Spacer()

                    if isLoadingFiles {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.accentColor)
                    }

                    Button {
                        navigateToDirectory(currentDirectory)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Back row when inside a subdirectory
                if !currentDirectory.isEmpty {
                    Button {
                        // Go up one level
                        let parts = currentDirectory.components(separatedBy: "/").filter { !$0.isEmpty }
                        let parent = parts.dropLast().joined(separator: "/")
                        navigateToDirectory(parent)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("..")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                }

                // File list
                List(workspaceFiles, selection: $selectedFileName) { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.isDirectory ? "folder.fill" : fileIcon(file.name))
                            .foregroundStyle(file.isDirectory ? Color.accentColor : .secondary)

                        VStack(alignment: .leading) {
                            Text(file.name)
                                .font(.callout)
                            if !file.isDirectory {
                                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                        }

                        Spacer()

                        if file.isDirectory {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                    .tag(file.name)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if file.isDirectory {
                            let subdir = currentDirectory.isEmpty ? file.name : "\(currentDirectory)/\(file.name)"
                            navigateToDirectory(subdir)
                        }
                    }
                    .onTapGesture(count: 1) {
                        if file.isDirectory {
                            let subdir = currentDirectory.isEmpty ? file.name : "\(currentDirectory)/\(file.name)"
                            navigateToDirectory(subdir)
                        } else {
                            selectedFileName = file.name
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 220)
            .onChange(of: selectedFileName) {
                guard let name = selectedFileName,
                      let file = workspaceFiles.first(where: { $0.name == name }),
                      !file.isDirectory else {
                    return
                }
                selectedFileContent = nil
                Task {
                    selectedFileContent = await service.readWorkspaceFile(path: file.path)
                }
            }

            // File content panel
            VStack(spacing: 0) {
                if let fileName = selectedFileName,
                   let file = workspaceFiles.first(where: { $0.name == fileName }), !file.isDirectory {
                    // File header with full path
                    HStack(spacing: 6) {
                        Image(systemName: fileIcon(fileName))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fileName)
                                .font(.headline)
                            // Show relative path
                            if !currentDirectory.isEmpty {
                                Text(currentDirectory)
                                    .font(.caption2)
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                    Divider()

                    if let content = selectedFileContent {
                        ScrollView {
                            Text(content)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding()
                        }
                    } else {
                        ProgressView()
                            .tint(Color.accentColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    EmptyStateView(
                        icon: "doc.text",
                        title: "Select a File",
                        message: "Choose a file from the sidebar to view its contents. Click folders to navigate inside."
                    )
                }
            }
        }
        .task {
            navigateToDirectory("")
        }
    }

    private func navigateToDirectory(_ relativePath: String) {
        currentDirectory = relativePath
        selectedFileName = nil
        selectedFileContent = nil
        isLoadingFiles = true
        Task {
            let fullPath = relativePath.isEmpty ? agent.workspace : "\(agent.workspace)/\(relativePath)"
            workspaceFiles = await service.listWorkspaceFiles(workspace: fullPath)
            isLoadingFiles = false
        }
    }

    // MARK: - Sessions View

    private var sessionsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions")
                    .font(.headline)
                Spacer()
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    startNewSession()
                    selectedTab = .chat
                } label: {
                    Label("New Session", systemImage: "plus.bubble")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await refreshSessions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            if isLoadingSessions {
                LoadingStateView(message: "Loading sessions...")
            } else if sessions.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "No Sessions",
                    message: "No conversation sessions found for this agent. Send a message to start one."
                )
            } else {
                List(sessions, selection: $selectedSession) { session in
                    HStack(spacing: 12) {
                        Image(systemName: activeSessionKey == session.key ? "bubble.left.and.bubble.right.fill" : "bubble.left.fill")
                            .font(.title3)
                            .foregroundStyle(activeSessionKey == session.key ? Color.accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(sessionDisplayKey(session.key))
                                    .font(.callout.bold())
                                    .lineLimit(1)

                                if activeSessionKey == session.key {
                                    StatusBadge(label: "Active", color: Color.green)
                                }
                            }

                            Text(session.key)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                if let model = session.model {
                                    Label(model, systemImage: "cpu")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if let updatedAt = session.updatedAt {
                                    Text(formatSessionDate(updatedAt))
                                        .font(.caption)
                                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                }
                            }
                        }

                        Spacer()

                        Button {
                            Task { await openSession(session) }
                        } label: {
                            Text(activeSessionKey == session.key ? "Continue" : "Resume")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        Task { await openSession(session) }
                    }
                }
            }
        }
        .task {
            await refreshSessions()
        }
    }

    private func refreshSessions() async {
        // Try gateway first for richer session data
        if gateway.isConnected {
            do {
                let response = try await gateway.sessionsList()
                let allSessions = response.sessions ?? []
                // Filter to this agent's sessions and convert to AgentSession
                let agentSessions = allSessions.filter { $0.agentId == agent.name }
                sessions = agentSessions.map { gs in
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
                isLoadingSessions = false
                return
            } catch {
                print("[Sessions] Gateway sessions.list failed: \(error), falling back to CLI")
            }
        }
        let fetched = await service.fetchSessions(agent: agent.name)
        sessions = fetched.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        isLoadingSessions = false
    }

    private func formatSessionDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Info View

    private var infoView: some View {
        Form {
            Section {
                LabeledContent("Display Name") {
                    TextField("Display Name", text: $editDisplayName)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Emoji") {
                    TextField("e.g. 🤖", text: $editEmoji)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                HStack {
                    Spacer()
                    Button("Save Identity") {
                        Task {
                            let r = await service.setAgentIdentity(
                                name: agent.name,
                                displayName: editDisplayName.isEmpty ? nil : editDisplayName,
                                emoji: editEmoji.isEmpty ? nil : editEmoji
                            )
                            toast.show(r.exitCode == 0 ? "Identity updated" : r.output, isError: r.exitCode != 0)
                            if r.exitCode == 0 { await service.fetchAgents() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } header: {
                Text("Identity")
            } footer: {
                Text("Set the display name and emoji shown in the sidebar and channels.")
            }

            Section("Agent Details") {
                LabeledContent("Agent ID", value: agent.name)
                LabeledContent("Workspace", value: agent.workspace)
                LabeledContent("Agent Dir", value: agent.agentDir ?? "—")
                LabeledContent("Default", value: agent.isDefault == true ? "Yes" : "No")
                LabeledContent("Bindings", value: "\(agent.bindingsCount ?? 0)")
            }

            Section {
                if isLoadingUsage {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading usage data…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if sessions.isEmpty && usageOutput.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar")
                            .foregroundStyle(.secondary)
                        Text("No usage data available. Start a session to begin tracking.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Aggregated session token stats
                    let totalInput = sessions.compactMap(\.inputTokens).reduce(0, +)
                    let totalOutput = sessions.compactMap(\.outputTokens).reduce(0, +)
                    let totalTokens = sessions.compactMap(\.totalTokens).reduce(0, +)
                    let sessionCount = sessions.count

                    HStack(spacing: 0) {
                        usageStatCard(
                            title: "Sessions",
                            value: "\(sessionCount)",
                            icon: "bubble.left.and.bubble.right",
                            color: .blue
                        )
                        Divider().frame(height: 40)
                        usageStatCard(
                            title: "Input Tokens",
                            value: formatTokenCount(totalInput),
                            icon: "arrow.up.circle",
                            color: .green
                        )
                        Divider().frame(height: 40)
                        usageStatCard(
                            title: "Output Tokens",
                            value: formatTokenCount(totalOutput),
                            icon: "arrow.down.circle",
                            color: .orange
                        )
                        Divider().frame(height: 40)
                        usageStatCard(
                            title: "Total Tokens",
                            value: formatTokenCount(totalTokens),
                            icon: "number.circle",
                            color: .purple
                        )
                    }

                    // Model breakdown
                    let modelGroups = Dictionary(grouping: sessions.filter { $0.model != nil }, by: { $0.model! })
                    if !modelGroups.isEmpty {
                        ForEach(modelGroups.keys.sorted(), id: \.self) { model in
                            let modelSessions = modelGroups[model]!
                            let modelTokens = modelSessions.compactMap(\.totalTokens).reduce(0, +)
                            HStack(spacing: 10) {
                                Image(systemName: "cpu")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model)
                                        .font(.system(.callout, design: .monospaced))
                                    Text("\(modelSessions.count) session\(modelSessions.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(formatTokenCount(modelTokens) + " tokens")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Provider usage (from CLI)
                    if !usageOutput.isEmpty {
                        DisclosureGroup("Provider Usage Details") {
                            Text(usageOutput)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await refreshUsage() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoadingUsage)
                }
            } header: {
                Text("Usage & Tokens")
            } footer: {
                Text("Token usage aggregated across all sessions for this agent. Provider usage requires valid API credentials.")
            }

            Section {
                if isLoadingBindings {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading bindings…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if agentBindings.isEmpty {
                    VStack(spacing: 8) {
                        Text("No channel bindings")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Bind this agent to a channel so it can receive and respond to messages.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                } else {
                    ForEach(agentBindings, id: \.self) { binding in
                        HStack(spacing: 10) {
                            Image(systemName: channelIcon(for: binding))
                                .foregroundStyle(.accent)
                                .frame(width: 20)
                            Text(binding)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                Task {
                                    isBindingBusy = true
                                    let r = await service.unbindAgent(name: agent.name, channel: binding)
                                    isBindingBusy = false
                                    if r.exitCode == 0 {
                                        agentBindings.removeAll { $0 == binding }
                                        toast.show("Removed \(binding) binding")
                                    } else {
                                        toast.show(r.output, isError: true)
                                    }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .disabled(isBindingBusy)
                            .help("Remove binding")
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        showAddBindingPopover = true
                    } label: {
                        Label("Add Binding", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBindingBusy)
                    .popover(isPresented: $showAddBindingPopover, arrowEdge: .bottom) {
                        addBindingPopover
                    }
                }
            } header: {
                HStack {
                    Text("Channel Bindings")
                    if !agentBindings.isEmpty {
                        Text("· \(agentBindings.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Channel bindings route messages from a channel (e.g. whatsapp, telegram, discord) to this agent.")
            }

            Section {
                let files: [(name: String, desc: String)] = [
                    ("AGENTS.md", "Operating instructions and memory rules"),
                    ("SOUL.md", "Persona, tone, and behavioral boundaries"),
                    ("USER.md", "Information about the user"),
                    ("IDENTITY.md", "Agent name and vibe"),
                    ("TOOLS.md", "Guidance on local tools"),
                ]
                ForEach(files, id: \.name) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(.body, design: .monospaced))
                            Text(file.desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") {
                            let path = agent.workspace.isEmpty
                                ? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.openclaw/workspace/\(file.name)"
                                : "\(agent.workspace)/\(file.name)"
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Workspace Instruction Files")
            } footer: {
                Text("These files control agent behavior. They are injected into the agent's context at the start of each session.")
            }

            Section("Actions") {
                HStack(spacing: 12) {
                    Button {
                        showRestartGatewayConfirm = true
                    } label: {
                        Label("Restart Gateway", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Agent", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            editDisplayName = agent.displayName ?? ""
            editEmoji = agent.emoji ?? ""
        }
        .task {
            agentBindings = await service.fetchBindings(for: agent.name)
            isLoadingBindings = false
            await refreshUsage()
        }
    }

    private static let supportedChannels = [
        "whatsapp", "telegram", "discord", "slack",
        "signal", "imessage", "msteams", "mattermost", "google-chat"
    ]

    private var addBindingPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Channel Binding")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Picker("Channel", selection: $newBindingChannel) {
                    Text("Select channel…").tag("")
                    ForEach(Self.supportedChannels, id: \.self) { channel in
                        Label(channel.capitalized, systemImage: channelIcon(for: channel))
                            .tag(channel)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Account ID") {
                    TextField("Optional", text: $newBindingAccountId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                Text("Leave empty for the default account. Use an account ID when you have multiple accounts on the same channel (e.g. telegram:alerts-bot).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Preview
            if !newBindingChannel.isEmpty {
                let bindingSpec = newBindingAccountId.isEmpty ? newBindingChannel : "\(newBindingChannel):\(newBindingAccountId)"
                HStack(spacing: 6) {
                    Image(systemName: channelIcon(for: newBindingChannel))
                        .foregroundStyle(.accent)
                    Text(bindingSpec)
                        .font(.system(.callout, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("The channel must be configured (token/credentials set) before binding. Set up channels in the Channels page or via config file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") {
                    showAddBindingPopover = false
                    newBindingChannel = ""
                    newBindingAccountId = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Add Binding") {
                    guard !newBindingChannel.isEmpty else { return }
                    let bindingSpec = newBindingAccountId.isEmpty ? newBindingChannel : "\(newBindingChannel):\(newBindingAccountId)"
                    Task {
                        isBindingBusy = true
                        showAddBindingPopover = false
                        let r = await service.bindAgent(name: agent.name, channel: bindingSpec)
                        isBindingBusy = false
                        if r.exitCode == 0 {
                            agentBindings.append(bindingSpec)
                            toast.show("Bound \(bindingSpec) to \(agent.displayName ?? agent.name)")
                        } else {
                            toast.show(r.output, isError: true)
                        }
                        newBindingChannel = ""
                        newBindingAccountId = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newBindingChannel.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func channelIcon(for channel: String) -> String {
        let name = channel.lowercased().components(separatedBy: ":").first ?? channel
        switch name {
        case "whatsapp": return "message.fill"
        case "telegram": return "paperplane.fill"
        case "discord": return "gamecontroller.fill"
        case "slack": return "number"
        case "signal": return "lock.shield.fill"
        case "imessage": return "bubble.fill"
        case "msteams": return "person.3.fill"
        case "mattermost": return "bubble.left.and.bubble.right.fill"
        case "google-chat": return "ellipsis.bubble.fill"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    private func usageStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.monospacedDigit().bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func refreshUsage() async {
        isLoadingUsage = true
        // Refresh sessions to get latest token data
        await refreshSessions()
        // Fetch provider usage via CLI
        let r = await service.fetchAgentUsage(agent: agent.name)
        if r.exitCode == 0, !r.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Try to extract human-readable usage info
            // If JSON, show raw; if text, show as-is
            let output = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.hasPrefix("{") || output.hasPrefix("[") {
                // Parse JSON for a cleaner display — show raw for now
                usageOutput = output
            } else {
                usageOutput = output
            }
        }
        isLoadingUsage = false
    }

    // MARK: - Model View

    private var modelView: some View {
        Form {
            Section {
                HStack {
                    Text(agentModel.isEmpty ? "Using global default" : agentModel)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(agentModel.isEmpty ? .secondary : .primary)
                    Spacer()
                    Button(agentModel.isEmpty ? "Set Model" : "Change") {
                        showModelChooser = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } header: {
                Text("Primary Model")
            } footer: {
                Text("Set a specific model for this agent. Leave empty to use the global default.")
            }

            Section {
                if let fallbacks = service.modelsStatus?.fallbacks, !fallbacks.isEmpty {
                    ForEach(fallbacks, id: \.self) { fallback in
                        Text(fallback)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No global fallbacks configured.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Fallback Models")
            } footer: {
                Text("Fallback models are configured globally on the Models page. All agents share the same fallback chain.")
            }

            Section {
                if let providers = service.modelsStatus?.providers, !providers.isEmpty {
                    ForEach(providers) { provider in
                        HStack(spacing: 10) {
                            // Status icon — validation result, validating spinner, or auth status
                            if validatingProvider == provider.name {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 20, height: 20)
                            } else if let isValid = providerValidationResults[provider.name] {
                                Image(systemName: isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(isValid ? Color.green : Color.orange)
                                    .font(.title3)
                            } else {
                                Image(systemName: provider.authenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(provider.authenticated ? Color.green : Color.red)
                                    .font(.title3)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name.capitalized)
                                    .font(.body.weight(.medium))

                                if validatingProvider == provider.name {
                                    Text("Validating…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let isValid = providerValidationResults[provider.name] {
                                    if agentAuthOverrides.contains(provider.name) {
                                        Text(isValid ? "Agent key validated" : "Agent key validation failed")
                                            .font(.caption)
                                            .foregroundStyle(isValid ? .green : .orange)
                                    } else {
                                        Text(isValid ? "Global key validated" : "Global key validation failed")
                                            .font(.caption)
                                            .foregroundStyle(isValid ? .green : .orange)
                                    }
                                } else if agentAuthOverrides.contains(provider.name) {
                                    Text("Using agent-specific key")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else if provider.authenticated {
                                    Text("Using global key")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No API key configured")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            Spacer()

                            if provider.authenticated || agentAuthOverrides.contains(provider.name) {
                                Button("Validate") {
                                    Task {
                                        validatingProvider = provider.name
                                        providerValidationResults.removeValue(forKey: provider.name)
                                        if agentAuthOverrides.contains(provider.name) {
                                            let status = await service.validateAgentProviderAuth(agent: agent.name, provider: provider.name)
                                            providerValidationResults[provider.name] = status?.authenticated == true
                                        } else {
                                            let status = await service.validateProviderAuth(provider: provider.name)
                                            providerValidationResults[provider.name] = status?.authenticated == true
                                        }
                                        validatingProvider = ""
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!validatingProvider.isEmpty)
                            }

                            if agentAuthOverrides.contains(provider.name) {
                                Button("Remove Override") {
                                    agentAuthOverrides.remove(provider.name)
                                    providerValidationResults.removeValue(forKey: provider.name)
                                    toast.show("Reverted \(provider.name.capitalized) to global key")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Button(agentAuthOverrides.contains(provider.name) ? "Change" : "Override") {
                                apiKeyOverrideProvider = provider.name
                                showAPIKeySheet = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("No providers configured. Add API keys on the Models page first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Provider API Keys")
            } footer: {
                Text("This agent inherits API keys from global settings. You can override a specific provider's key for this agent only.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showModelChooser) {
            ModelChooserSheet(
                title: "Model for \(agent.displayName ?? agent.name)",
                description: "Choose a model specifically for this agent, overriding the global default.",
                actionLabel: "Apply",
                initialSelection: agentModel,
                onApply: { model in
                    let r = await service.setAgentModel(agent: agent.name, model: model)
                    toast.show(r.exitCode == 0 ? "Model set for \(agent.name)" : r.output, isError: r.exitCode != 0)
                    if r.exitCode == 0 { agentModel = model }
                    return r.exitCode == 0
                },
                onDismiss: { showModelChooser = false }
            )
        }

        .sheet(isPresented: $showAPIKeySheet) {
            APIKeySheet(
                title: "API Key for \(agent.displayName ?? agent.name)",
                description: "This key will override the global \(apiKeyOverrideProvider.isEmpty ? "provider" : apiKeyOverrideProvider.capitalized) key for this agent only.",
                initialProvider: apiKeyOverrideProvider,
                onSave: { provider, apiKey in
                    let r = await service.configureAgentAuth(
                        agent: agent.name,
                        provider: provider,
                        apiKey: apiKey
                    )
                    if r.exitCode == 0 {
                        agentAuthOverrides.insert(provider)
                        toast.show("\(provider.capitalized) key set for \(agent.displayName ?? agent.name)")
                    } else {
                        toast.show(r.output, isError: true)
                    }
                    return r.exitCode == 0
                },
                onValidate: { provider in
                    await service.validateAgentProviderAuth(agent: agent.name, provider: provider)
                },
                onDismiss: {
                    showAPIKeySheet = false
                    apiKeyOverrideProvider = ""
                }
            )
        }
    }

    // MARK: - Helpers

    @MainActor
    private func loadData() async {
        // Try connecting to gateway WebSocket
        gateway.connect()
        // Give gateway a moment to complete handshake
        try? await Task.sleep(for: .milliseconds(500))

        workspaceFiles = await service.listWorkspaceFiles(workspace: agent.workspace)
        await refreshSessions()

        // If a specific session was requested (e.g. from the Sessions list), open it
        if let targetId = initialSessionId,
           let target = sessions.first(where: { $0.sessionId == targetId || $0.key == targetId }) {
            await openSession(target)
        } else if let latest = sessions.first {
            await openSession(latest)
        }
    }

    @MainActor
    private func openSession(_ session: AgentSession) async {
        selectedSession = session
        activeSessionId = session.sessionId
        activeSessionKey = session.key
        isLoadingHistory = true
        slashCommandResult = nil
        chatMessages = []

        // Try loading history via gateway WebSocket first, fall back to JSONL files
        var loaded = false

        if gateway.isConnected, !session.key.isEmpty {
            do {
                let historyResponse = try await gateway.chatHistory(sessionKey: session.key)
                let msgs = historyResponse.toChatMessages()
                chatMessages = msgs
                loaded = true
                print("[Chat] Loaded \(msgs.count) messages via gateway for key: \(session.key)")

                // Also update the sessionId from the response if we don't have one
                if activeSessionId == nil, let sid = historyResponse.sessionId {
                    activeSessionId = sid
                }
            } catch {
                print("[Chat] Gateway history failed: \(error)")
            }
        }

        // Fallback: read JSONL transcript from disk
        if !loaded, let sessionId = session.sessionId ?? activeSessionId {
            let msgs = await service.loadSessionHistory(agent: agent.name, sessionId: sessionId)
            chatMessages = msgs
            print("[Chat] Loaded \(msgs.count) messages from JSONL for sessionId: \(sessionId)")
        }

        isLoadingHistory = false
        selectedTab = .chat
    }

    private func sendMessage() {
        guard !messageText.isEmpty, !isSending else { return }
        let text = messageText
        messageText = ""

        // Handle slash commands
        if text.hasPrefix("/") {
            handleSlashCommand(text)
            return
        }

        chatMessages.append(ChatMessage(role: .user, content: text, timestamp: Date()))
        isSending = true

        if gateway.isConnected {
            // If no active session key, generate a new unique one for a fresh session
            let sessionKey = activeSessionKey ?? "agent:\(agent.name):\(UUID().uuidString.prefix(8).lowercased())"
            if activeSessionKey == nil {
                activeSessionKey = sessionKey
            }
            sendViaGateway(text: text, sessionKey: sessionKey)
        } else {
            // CLI mode: omitting session-id creates a new session automatically
            sendViaCLI(text: text)
        }
    }

    private func sendViaGateway(text: String, sessionKey: String) {
        Task {
            do {
                // chatSend returns immediately with acceptance; streaming happens via agent events
                _ = try await gateway.chatSend(sessionKey: sessionKey, message: text)

                // Wait for the agent to finish streaming
                await gateway.waitForAgentCompletion()

                isSending = false

                // Use the accumulated streaming text
                let responseText = gateway.streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !responseText.isEmpty {
                    chatMessages.append(ChatMessage(role: .agent, content: responseText, timestamp: Date()))
                }

                gateway.streamingText = ""

                // Refresh sessions to pick up newly created session
                await refreshSessions()

                // If we didn't have a sessionId before, find it from the refreshed sessions
                if activeSessionId == nil,
                   let match = sessions.first(where: { $0.key == sessionKey }) {
                    activeSessionId = match.sessionId
                }
            } catch {
                isSending = false
                gateway.streamingText = ""
                chatMessages.append(ChatMessage(role: .error, content: error.localizedDescription, timestamp: Date()))
            }
        }
    }

    private func sendViaCLI(text: String) {
        // Start a streaming process so output appears in real-time
        let proc = service.sendMessageStreaming(to: agent.name, message: text, sessionId: activeSessionId)
        streamingProcess = proc
        proc.start()

        Task {
            while proc.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }

            let output = proc.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let exitCode = proc.exitCode

            streamingProcess = nil
            isSending = false

            if exitCode == 0 && !output.isEmpty {
                chatMessages.append(ChatMessage(role: .agent, content: output, timestamp: Date()))
            } else if !output.isEmpty {
                chatMessages.append(ChatMessage(role: .error, content: output, timestamp: Date()))
            }

            // Refresh sessions to capture any new session
            await refreshSessions()

            // If this was a new session, pick up the newly created session info
            if activeSessionId == nil || activeSessionKey == nil {
                // Sort by updatedAt descending to find the most recently active session
                let sorted = sessions.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
                if let newest = sorted.first {
                    if activeSessionId == nil {
                        activeSessionId = newest.sessionId
                    }
                    if activeSessionKey == nil {
                        activeSessionKey = newest.key
                    }
                }
            }
        }
    }

    // MARK: - Slash Commands

    private func handleSlashCommand(_ input: String) {
        let parts = input.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        let command = parts[0].lowercased()
        let args = parts.dropFirst().joined(separator: " ")

        switch command {
        case "/new", "/reset":
            if let key = activeSessionKey, gateway.isConnected {
                // Reset the current session via gateway RPC (archives old transcript, new sessionId)
                slashCommandResult = "Resetting session..."
                Task {
                    _ = try? await gateway.sessionsReset(sessionKey: key)
                    activeSessionId = nil
                    selectedSession = nil
                    chatMessages = []
                    await refreshSessions()
                    // Pick up the new sessionId for the same key
                    if let refreshed = sessions.first(where: { $0.key == key }) {
                        activeSessionId = refreshed.sessionId
                    }
                    slashCommandResult = "Session reset. Chat history archived."
                    if !args.isEmpty {
                        slashCommandResult! += " Model hint: \(args)"
                    }
                }
            } else {
                // No active session or no gateway — just clear local state
                startNewSession()
                slashCommandResult = "New session. Next message starts a fresh conversation."
                if !args.isEmpty {
                    slashCommandResult! += " Model hint: \(args)"
                }
            }

        case "/compact":
            slashCommandResult = "Compacting session..."
            Task {
                let result = await service.runCommand("openclaw agent --to \(agent.name) --message \"/compact \(args)\" --session-id \(activeSessionId ?? "")")
                slashCommandResult = result.exitCode == 0 ? "Session compacted." : "Compact failed: \(result.output)"
            }

        case "/status":
            slashCommandResult = "Fetching status..."
            Task {
                let result = await service.runCommand("openclaw agent --to \(agent.name) --message \"/status\" --session-id \(activeSessionId ?? "")")
                slashCommandResult = result.output.isEmpty ? "No status info returned." : result.output
            }

        case "/think", "/thinking", "/t":
            if args.isEmpty {
                slashCommandResult = "Usage: /think <off|minimal|low|medium|high|xhigh>"
            } else {
                slashCommandResult = "Setting thinking level to: \(args)"
                if gateway.isConnected, let key = activeSessionKey {
                    Task {
                        _ = try? await gateway.sessionsPatch(sessionKey: key, patch: ["thinkingLevel": args])
                        slashCommandResult = "Thinking level set to: \(args)"
                    }
                }
            }

        case "/model":
            if args.isEmpty {
                slashCommandResult = "Current model: \(selectedSession?.model ?? "default")"
            } else {
                slashCommandResult = "Switching model to: \(args)"
                if gateway.isConnected, let key = activeSessionKey {
                    Task {
                        _ = try? await gateway.sessionsPatch(sessionKey: key, patch: ["model": args])
                        slashCommandResult = "Model set to: \(args)"
                    }
                }
            }

        case "/verbose", "/v":
            let level = args.isEmpty ? "on" : args
            slashCommandResult = "Verbose: \(level)"
            if gateway.isConnected, let key = activeSessionKey {
                Task {
                    _ = try? await gateway.sessionsPatch(sessionKey: key, patch: ["verboseLevel": level])
                }
            }

        case "/export", "/export-session":
            slashCommandResult = "Exporting session..."
            Task {
                let path = args.isEmpty ? "~/Desktop/session-export.html" : args
                let result = await service.runCommand("openclaw agent --to \(agent.name) --message \"/export-session \(path)\" --session-id \(activeSessionId ?? "")")
                slashCommandResult = result.exitCode == 0 ? "Exported to \(path)" : result.output
            }

        case "/context":
            slashCommandResult = "Fetching context..."
            Task {
                let mode = args.isEmpty ? "list" : args
                let result = await service.runCommand("openclaw agent --to \(agent.name) --message \"/context \(mode)\" --session-id \(activeSessionId ?? "")")
                slashCommandResult = result.output.isEmpty ? "No context info." : result.output
            }

        case "/help", "/commands":
            slashCommandResult = """
            /new [model] - Start new session
            /compact [instructions] - Compact context
            /status - Session status
            /think <level> - Set thinking level
            /model [name] - Switch model
            /verbose on|off - Toggle verbose
            /export [path] - Export session
            /context [list|detail|json] - View context
            """

        default:
            // Forward unknown slash commands to the agent
            chatMessages.append(ChatMessage(role: .user, content: input, timestamp: Date()))
            isSending = true
            if gateway.isConnected, let key = activeSessionKey {
                sendViaGateway(text: input, sessionKey: key)
            } else {
                sendViaCLI(text: input)
            }
        }
    }

    private func abortCurrentRun() {
        guard let key = activeSessionKey, gateway.isConnected else { return }
        Task {
            do {
                _ = try await gateway.chatAbort(sessionKey: key)
                isSending = false
                let streamedSoFar = gateway.streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !streamedSoFar.isEmpty {
                    chatMessages.append(ChatMessage(role: .agent, content: streamedSoFar + "\n\n[Aborted]", timestamp: Date()))
                }
                gateway.streamingText = ""
            } catch {
                chatMessages.append(ChatMessage(role: .error, content: "Abort failed: \(error.localizedDescription)", timestamp: Date()))
            }
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func startNewSession() {
        activeSessionId = nil
        activeSessionKey = nil
        selectedSession = nil
        chatMessages = []
        slashCommandResult = nil
    }

    /// Short display name for a session key (strips the `agent:<name>:` prefix)
    private func sessionDisplayKey(_ key: String) -> String {
        let parts = key.components(separatedBy: ":")
        if parts.count >= 3 {
            return parts.dropFirst(2).joined(separator: ":")
        }
        return key
    }

    private func sessionMenuLabel(_ session: AgentSession) -> String {
        var parts: [String] = []
        parts.append(sessionDisplayKey(session.key))
        if let model = session.model {
            parts.append("(\(model))")
        }
        if let updatedAt = session.updatedAt {
            let date = Date(timeIntervalSince1970: updatedAt / 1000)
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            parts.append(formatter.localizedString(for: date, relativeTo: Date()))
        }
        return parts.joined(separator: " ")
    }

    private func fileIcon(_ name: String) -> String {
        if name.hasSuffix(".md") { return "doc.richtext" }
        if name.hasSuffix(".json") { return "curlybraces" }
        if name.hasSuffix(".yaml") || name.hasSuffix(".yml") { return "list.bullet.rectangle" }
        if name.hasSuffix(".txt") { return "doc.text" }
        return "doc"
    }

    private func agentColor(_ status: AgentStatus) -> Color {
        switch status {
        case .online, .working: return Color.green
        case .idle: return Color.yellow
        case .offline: return Color.red
        case .unknown: return Color(nsColor: .tertiaryLabelColor)
        }
    }
}
