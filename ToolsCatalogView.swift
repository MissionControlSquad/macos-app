import SwiftUI

struct ToolsCatalogView: View {
    @Bindable var gateway: GatewayWebSocket
    @State private var tools: [[String: Any]] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchText = ""
    @State private var selectedTool: [String: Any]?

    private var filteredTools: [[String: Any]] {
        if searchText.isEmpty { return tools }
        return tools.filter { tool in
            let name = tool["name"] as? String ?? ""
            let desc = tool["description"] as? String ?? ""
            return name.localizedCaseInsensitiveContains(searchText)
                || desc.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if tools.isEmpty && !isLoading {
                EmptyStateView(
                    icon: "wrench.and.screwdriver",
                    title: "No Tools Available",
                    message: error ?? "Connect to the gateway to see available tools."
                )
            } else {
                HSplitView {
                    // Tool list
                    VStack(spacing: 0) {
                        if filteredTools.isEmpty && !searchText.isEmpty {
                            EmptyStateView(
                                icon: "magnifyingglass",
                                title: "No Results",
                                message: "No tools match \"\(searchText)\". Try a different search term."
                            )
                        } else {
                            List(selection: Binding<String?>(
                                get: { selectedTool?["name"] as? String },
                                set: { newName in
                                    selectedTool = filteredTools.first { ($0["name"] as? String) == newName }
                                }
                            )) {
                                ForEach(Array(filteredTools.enumerated()), id: \.offset) { _, tool in
                                    let name = tool["name"] as? String ?? "Unknown"
                                    let desc = tool["description"] as? String ?? ""
                                    let category = tool["category"] as? String

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Image(systemName: toolIcon(for: category))
                                                .font(.caption)
                                                .foregroundStyle(Color.accentColor)
                                            Text(name)
                                                .font(.callout.bold())
                                        }
                                        if !desc.isEmpty {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .tag(name)
                                }
                            }
                        }
                    }
                    .frame(minWidth: 250, idealWidth: 300)

                    // Tool detail
                    if let tool = selectedTool {
                        toolDetailView(tool)
                    } else {
                        EmptyStateView(
                            icon: "wrench",
                            title: "Select a Tool",
                            message: "Choose a tool from the list to see its details."
                        )
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search tools...")
        .navigationTitle("Tools Catalog")
        .navigationSubtitle(tools.isEmpty ? "" : "\(tools.count) tools")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ConnectionBadge(isConnected: gateway.isConnected)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadTools() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh tools catalog")
            }
        }
        .task {
            await loadTools()
        }
    }

    // MARK: - Tool Detail

    private func toolDetailView(_ tool: [String: Any]) -> some View {
        let name = tool["name"] as? String ?? "Unknown"
        let desc = tool["description"] as? String ?? ""
        let category = tool["category"] as? String ?? "general"
        let parameters = tool["parameters"] as? [[String: Any]] ?? tool["inputSchema"] as? [[String: Any]] ?? []
        let schema = tool["inputSchema"] as? [String: Any]

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: toolIcon(for: category))
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.title3.bold())
                        StatusBadge(label: category, color: Color.accentColor)
                    }
                }

                if !desc.isEmpty {
                    Text(desc)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Parameters
                if !parameters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Parameters")
                            .font(.headline)

                        ForEach(Array(parameters.enumerated()), id: \.offset) { _, param in
                            parameterRow(param)
                        }
                    }
                } else if let schema, let properties = schema["properties"] as? [String: Any] {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Input Schema")
                            .font(.headline)

                        let required = schema["required"] as? [String] ?? []

                        ForEach(Array(properties.keys.sorted()), id: \.self) { key in
                            if let propInfo = properties[key] as? [String: Any] {
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(key)
                                                .font(.system(.callout, design: .monospaced).bold())
                                            if required.contains(key) {
                                                Text("required")
                                                    .font(.caption2)
                                                    .foregroundStyle(Color.red)
                                            }
                                        }
                                        if let type = propInfo["type"] as? String {
                                            Text(type)
                                                .font(.caption)
                                                .foregroundStyle(Color.purple)
                                        }
                                        if let desc = propInfo["description"] as? String {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(.quinary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                } else {
                    Text("No parameters documented.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Raw JSON
                DisclosureGroup("Raw Definition") {
                    if let jsonData = try? JSONSerialization.data(withJSONObject: tool, options: [.prettyPrinted, .sortedKeys]),
                       let jsonStr = String(data: jsonData, encoding: .utf8) {
                        ScrollView(.horizontal) {
                            Text(jsonStr)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                        .padding(8)
                        .background(.quinary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding()
        }
    }

    private func parameterRow(_ param: [String: Any]) -> some View {
        let name = param["name"] as? String ?? "?"
        let type = param["type"] as? String ?? ""
        let desc = param["description"] as? String ?? ""
        let required = param["required"] as? Bool ?? false

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.system(.callout, design: .monospaced).bold())
                    Text(type)
                        .font(.caption)
                        .foregroundStyle(Color.purple)
                    if required {
                        Text("required")
                            .font(.caption2)
                            .foregroundStyle(Color.red)
                    }
                }
                if !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func toolIcon(for category: String?) -> String {
        switch category?.lowercased() {
        case "file", "filesystem": return "doc.fill"
        case "shell", "terminal", "exec": return "terminal.fill"
        case "network", "http", "web": return "globe"
        case "search", "find": return "magnifyingglass"
        case "memory", "store": return "brain.head.profile"
        case "git", "vcs": return "arrow.triangle.branch"
        default: return "wrench.fill"
        }
    }

    private func loadTools() async {
        guard gateway.isConnected else {
            error = "Not connected to gateway"
            return
        }

        isLoading = true
        error = nil

        do {
            let result = try await gateway.toolsCatalog()
            // The result may have tools at the top level or under a "tools" key
            if let toolsList = result["tools"] as? [[String: Any]] {
                tools = toolsList
            } else if let toolsList = result.raw as? [String: Any],
                      let items = toolsList["items"] as? [[String: Any]] {
                tools = items
            } else {
                // Try treating the whole payload as tool entries
                tools = [result.raw]
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
