import SwiftUI

enum AgentTab: String, CaseIterable {
    case chat = "Chat"
    case files = "Files"
    case sessions = "Sessions"
    case info = "Info"

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .files: return "doc.text.fill"
        case .sessions: return "clock.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct AgentDetailView: View {
    let agent: Agent
    @Bindable var service: OpenClawService
    @State private var selectedTab: AgentTab = .chat

    // Chat state
    @State private var messageText = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var isSending = false

    // Files state
    @State private var workspaceFiles: [WorkspaceFile] = []
    @State private var selectedFileContent: String?
    @State private var selectedFileName: String?

    // Sessions state
    @State private var sessions: [AgentSession] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()

            switch selectedTab {
            case .chat:
                chatView
            case .files:
                filesView
            case .sessions:
                sessionsView
            case .info:
                infoView
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if let emoji = agent.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.largeTitle)
            } else {
                Image(systemName: agent.agentStatus.icon)
                    .font(.title)
                    .foregroundStyle(agentColor(agent.agentStatus))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.displayName ?? agent.name)
                        .font(.title2.bold())
                    if agent.isDefault == true {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text(agent.workspace)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(agent.agentStatus.label)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(agentColor(agent.agentStatus).opacity(0.15))
                .foregroundStyle(agentColor(agent.agentStatus))
                .clipShape(Capsule())
        }
        .padding()
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AgentTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.caption)
                        Text(tab.rawValue)
                    }
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chatMessages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.tertiary)
                                Text("Send a message to start chatting with \(agent.name)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }

                        ForEach(chatMessages) { message in
                            chatBubble(message)
                                .id(message.id)
                        }

                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .id("thinking")
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
            }

            Divider()

            // Message input
            HStack(spacing: 8) {
                TextField("Message \(agent.name)...", text: $messageText, axis: .vertical)
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
                .foregroundStyle(messageText.isEmpty || isSending ? .tertiary : .accentColor)
                .disabled(messageText.isEmpty || isSending)
            }
            .padding(12)
        }
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
        case .agent: return Color(.controlBackgroundColor)
        case .error: return Color.red.opacity(0.1)
        }
    }

    // MARK: - Files View

    private var filesView: some View {
        HSplitView {
            // File list
            List(workspaceFiles, selection: $selectedFileName) { file in
                HStack(spacing: 8) {
                    Image(systemName: file.isDirectory ? "folder.fill" : fileIcon(file.name))
                        .foregroundStyle(file.isDirectory ? .blue : .secondary)

                    VStack(alignment: .leading) {
                        Text(file.name)
                            .font(.callout)
                        if !file.isDirectory {
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .tag(file.name)
                .onTapGesture {
                    if !file.isDirectory {
                        selectedFileName = file.name
                        Task {
                            selectedFileContent = await service.readWorkspaceFile(path: file.path)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)

            // File content
            VStack(spacing: 0) {
                if let fileName = selectedFileName {
                    HStack {
                        Image(systemName: fileIcon(fileName))
                        Text(fileName)
                            .font(.headline)
                        Spacer()
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Select a File", systemImage: "doc.text")
                    } description: {
                        Text("Choose a file from the sidebar to view its contents.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task {
            workspaceFiles = await service.listWorkspaceFiles(workspace: agent.workspace)
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
                    Task { sessions = await service.fetchSessions(agent: agent.name) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "clock")
                } description: {
                    Text("No conversation sessions found for this agent. Send a message to start one.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sessions) { session in
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.fill")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.key)
                                .font(.callout.bold())
                            if let model = session.model {
                                Text(model)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let agentId = session.agentId {
                            Text(agentId)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.controlBackgroundColor))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            sessions = await service.fetchSessions(agent: agent.name)
        }
    }

    // MARK: - Info View

    private var infoView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoSection("Agent", items: [
                    ("Name", agent.name),
                    ("Workspace", agent.workspace),
                    ("Agent Dir", agent.agentDir ?? "—"),
                    ("Default", agent.isDefault == true ? "Yes" : "No"),
                    ("Bindings", "\(agent.bindingsCount ?? 0)"),
                ])

                if let routes = agent.routes, !routes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Routes")
                            .font(.headline)

                        ForEach(routes, id: \.self) { route in
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundStyle(.secondary)
                                Text(route)
                                    .font(.callout)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Quick actions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await service.runCommand("openclaw gateway restart")
                            }
                        } label: {
                            Label("Restart Gateway", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            Task {
                                await service.deleteAgent(name: agent.name)
                            }
                        } label: {
                            Label("Delete Agent", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding()
        }
    }

    private func infoSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(items, id: \.0) { key, value in
                HStack(alignment: .top) {
                    Text(key)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                    Text(value)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func loadData() async {
        async let filesTask: () = { workspaceFiles = await service.listWorkspaceFiles(workspace: agent.workspace) }()
        async let sessionsTask: () = { sessions = await service.fetchSessions(agent: agent.name) }()
        _ = await (filesTask, sessionsTask)
    }

    private func sendMessage() {
        guard !messageText.isEmpty, !isSending else { return }
        let text = messageText
        messageText = ""

        chatMessages.append(ChatMessage(role: .user, content: text, timestamp: Date()))
        isSending = true

        Task {
            let result = await service.sendMessage(to: agent.name, message: text)
            isSending = false

            if result.exitCode == 0 {
                chatMessages.append(ChatMessage(role: .agent, content: result.output, timestamp: Date()))
            } else {
                chatMessages.append(ChatMessage(role: .error, content: result.output, timestamp: Date()))
            }
        }
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
        case .online, .working: return .green
        case .idle: return .yellow
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}
