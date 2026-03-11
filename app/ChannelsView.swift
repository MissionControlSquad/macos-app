import SwiftUI

private let supportedChannels: [(String, String, String)] = [
    ("whatsapp", "WhatsApp", "message.fill"),
    ("telegram", "Telegram", "paperplane.fill"),
    ("discord", "Discord", "gamecontroller.fill"),
    ("slack", "Slack", "number"),
    ("signal", "Signal", "lock.shield.fill"),
    ("imessage", "iMessage", "message.badge.filled.fill"),
    ("msteams", "MS Teams", "person.3.fill"),
    ("googlechat", "Google Chat", "bubble.left.and.text.bubble.right.fill"),
    ("mattermost", "Mattermost", "bubble.left.fill"),
    ("matrix", "Matrix", "square.grid.3x3.fill"),
    ("irc", "IRC", "terminal.fill"),
    ("nostr", "Nostr", "antenna.radiowaves.left.and.right"),
]

struct ChannelsView: View {
    @Bindable var service: OpenClawService
    @State private var channelListOutput = ""
    @State private var statusOutput = ""
    @State private var isLoading = false
    @State private var actionResult = ""
    @State private var actionIsError = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Channels")
                    .font(.title.bold())
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status summary
                    if !statusOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Live Status")
                                .font(.headline)
                            Text(statusOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Channel cards
                    Text("Messaging Platforms")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 12) {
                        ForEach(supportedChannels, id: \.0) { key, name, icon in
                            channelCard(key: key, name: name, icon: icon)
                        }
                    }

                    if !actionResult.isEmpty {
                        Text(actionResult)
                            .font(.callout)
                            .foregroundStyle(actionIsError ? .red : .green)
                    }
                }
                .padding()
            }
        }
        .task {
            await refresh()
        }
    }

    private func channelCard(key: String, name: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(name)
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Login") {
                    Task {
                        isLoading = true
                        let result = await service.channelLogin(channel: key)
                        actionResult = result.exitCode == 0
                            ? "\(name) login initiated"
                            : result.output
                        actionIsError = result.exitCode != 0
                        isLoading = false
                        await refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Logout") {
                    Task {
                        let result = await service.channelLogout(channel: key)
                        actionResult = result.exitCode == 0
                            ? "\(name) logged out"
                            : result.output
                        actionIsError = result.exitCode != 0
                        await refresh()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func refresh() async {
        isLoading = true
        let statusResult = await service.fetchChannelStatus()
        statusOutput = statusResult.output
        let listResult = await service.fetchChannels()
        channelListOutput = listResult.output
        isLoading = false
    }
}
