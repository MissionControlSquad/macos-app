import SwiftUI

struct TerminalView: View {
    @Bindable var service: OpenClawService
    @State private var customCommand = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(service.commandHistory) { result in
                        commandResultView(result)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.green)

                TextField("Enter command...", text: $customCommand)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { runCustomCommand() }

                Button("Run") { runCustomCommand() }
                    .buttonStyle(.borderedProminent)
                    .disabled(customCommand.isEmpty || service.isRunningCommand)
            }
            .padding()
        }
        .navigationTitle("Terminal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if service.isRunningCommand {
                    ProgressView()
                        .controlSize(.small)
                } else if !service.commandHistory.isEmpty {
                    Button {
                        service.commandHistory.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear history")
                }
            }
        }
    }

    private func commandResultView(_ result: CommandResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("$ \(result.command)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.green)
                Spacer()
                Text(result.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                if result.exitCode != 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                        .font(.caption)
                }
            }

            if result.output.isEmpty {
                Text("(no output)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(result.exitCode == 0 ? Color.green : Color.red)
                    .italic()
            } else {
                Text(result.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(result.exitCode == 0 ? .primary : Color.red)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func runCustomCommand() {
        guard !customCommand.isEmpty else { return }
        let cmd = customCommand
        customCommand = ""
        Task { await service.runCommand(cmd) }
    }
}
