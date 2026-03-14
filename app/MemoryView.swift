import SwiftUI

struct MemoryView: View {
    @Bindable var service: OpenClawService
    @State private var searchQuery = ""
    @State private var searchResults = ""
    @State private var statusOutput = ""
    @State private var isSearching = false
    @State private var isLoading = false
    @State private var selectedAgent: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Status card
                GroupBox("Memory Status") {
                    if statusOutput.isEmpty {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(statusOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Actions
                HStack(spacing: 12) {
                    Button {
                        Task {
                            isLoading = true
                            let result = await service.memoryIndex()
                            statusOutput = result.output
                            isLoading = false
                        }
                    } label: {
                        Label("Rebuild Index", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                // Search
                GroupBox("Search Memory") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("What do you want to find?", text: $searchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { search() }

                            Button {
                                search()
                            } label: {
                                Label("Search", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(searchQuery.isEmpty || isSearching)
                        }

                        if isSearching {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Searching...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !searchResults.isEmpty {
                            Divider()
                            Text("Results")
                                .font(.subheadline.bold())
                            Text(searchResults)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Memory")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await fetchStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh memory status")
                }
            }
        }
        .task {
            await fetchStatus()
        }
    }

    private func fetchStatus() async {
        isLoading = true
        let result = await service.memoryStatus()
        statusOutput = result.output
        isLoading = false
    }

    private func search() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            let result = await service.memorySearch(query: searchQuery)
            searchResults = result.output
            isSearching = false
        }
    }
}
