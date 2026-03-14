import SwiftUI

struct LogsView: View {
    @Bindable var service: OpenClawService
    @State private var logOutput = ""
    @State private var isLoading = false
    @State private var logLimit = 100
    @State private var isLive = true
    @State private var streamProcess: StreamingProcess?
    @State private var isConnecting = true

    var body: some View {
        VStack(spacing: 0) {
            // Log output
            if isConnecting {
                LoadingStateView(message: "Connecting to log stream...")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        let displayText = isLive
                            ? (streamProcess?.output ?? "")
                            : logOutput

                        if displayText.isEmpty {
                            if isLive {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.accentColor)
                                    Text("Waiting for new log entries...")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                            } else {
                                EmptyStateView(
                                    icon: "doc.text.magnifyingglass",
                                    title: "No Logs",
                                    message: "No logs available. Make sure the gateway is running."
                                )
                                .padding(.top, 40)
                            }
                        } else {
                            Text(displayText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding()
                                .id("logEnd")
                        }
                    }
                    .onChange(of: streamProcess?.output) {
                        if isLive {
                            proxy.scrollTo("logEnd", anchor: .bottom)
                        }
                    }
                    .onChange(of: logOutput) {
                        if !isLive {
                            proxy.scrollTo("logEnd", anchor: .bottom)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            // Live status bar
            if isLive && !isConnecting {
                Divider()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text("Streaming live logs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let proc = streamProcess {
                        Text("\(proc.output.components(separatedBy: "\n").count) lines")
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                    Button("Stop") {
                        toggleLive()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !isLive {
                    Picker("Lines", selection: $logLimit) {
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("500").tag(500)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    toggleLive()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isLive ? Color.red : Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Live")
                    }
                }
                .buttonStyle(.bordered)
                .tint(isLive ? Color.red : nil)
                .help(isLive ? "Switch to static log view" : "Switch to live log stream")
            }
            ToolbarItem(placement: .primaryAction) {
                if !isLive {
                    Button {
                        Task { await fetchLogs() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh logs")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if isLive {
                        streamProcess?.output = ""
                    } else {
                        logOutput = ""
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear logs")
            }
        }
        .task {
            await startLiveStream()
        }
        .onDisappear {
            streamProcess?.stop()
        }
    }

    private func startLiveStream() async {
        isConnecting = true
        isLive = true
        let proc = service.startLogStream()
        proc.start()
        streamProcess = proc
        // Wait briefly for the stream to connect and start receiving data
        try? await Task.sleep(for: .milliseconds(500))
        isConnecting = false
    }

    private func fetchLogs() async {
        isLoading = true
        let result = await service.fetchLogs(limit: logLimit)
        logOutput = result.output
        isLoading = false
    }

    private func toggleLive() {
        if isLive {
            streamProcess?.stop()
            streamProcess = nil
            isLive = false
            // Load static logs when switching away from live
            Task { await fetchLogs() }
        } else {
            Task { await startLiveStream() }
        }
    }
}
