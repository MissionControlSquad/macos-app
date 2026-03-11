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
        VStack(spacing: 0) {
            HStack {
                Text("Memory")
                    .font(.title.bold())
                Spacer()
                Button {
                    Task { await fetchStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Memory Status")
                                .font(.headline)
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        if statusOutput.isEmpty {
                            Text("Loading...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(statusOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search Memory")
                            .font(.headline)

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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Results")
                                    .font(.subheadline.bold())

                                Text(searchResults)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
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
