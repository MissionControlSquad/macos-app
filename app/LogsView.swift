import SwiftUI

struct LogsView: View {
    @Bindable var service: OpenClawService
    @State private var logOutput = ""
    @State private var isLoading = false
    @State private var logLimit = 100
    @State private var autoRefresh = false
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs")
                    .font(.title.bold())
                Spacer()

                Picker("Lines", selection: $logLimit) {
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("500").tag(500)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Toggle("Auto", isOn: $autoRefresh)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button {
                    Task { await fetchLogs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()

            Divider()

            // Log output
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logOutput.isEmpty ? "No logs available. Make sure the gateway is running." : logOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                        .id("logEnd")
                }
                .onChange(of: logOutput) {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.textBackgroundColor))
        }
        .task {
            await fetchLogs()
        }
        .onChange(of: autoRefresh) {
            if autoRefresh {
                refreshTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(5))
                        if !Task.isCancelled {
                            await fetchLogs()
                        }
                    }
                }
            } else {
                refreshTask?.cancel()
            }
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private func fetchLogs() async {
        isLoading = true
        let result = await service.fetchLogs(limit: logLimit)
        logOutput = result.output
        isLoading = false
    }
}
