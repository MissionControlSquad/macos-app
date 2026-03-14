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
    @State private var toast = ToastState()
    @State private var loadingChannel: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Status summary
                if !statusOutput.isEmpty {
                    GroupBox("Live Status") {
                        Text(statusOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Channel cards
                Text("Messaging Platforms")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 12) {
                    ForEach(supportedChannels, id: \.0) { key, name, icon in
                        channelCard(key: key, name: name, icon: icon)
                    }
                }

                ToastBanner(toast: toast)
            }
            .padding()
        }
        .navigationTitle("Channels")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh channels")
            }
        }
        .task {
            await refresh()
        }
    }

    private func channelCard(key: String, name: String, icon: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    Text(name)
                        .font(.headline)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            loadingChannel = key
                            let result = await service.channelLogin(channel: key)
                            toast.show(
                                result.exitCode == 0 ? "\(name) login initiated" : result.output,
                                isError: result.exitCode != 0
                            )
                            loadingChannel = nil
                            await refresh()
                        }
                    } label: {
                        if loadingChannel == key {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Login")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(loadingChannel != nil)

                    Button {
                        Task {
                            loadingChannel = key
                            let result = await service.channelLogout(channel: key)
                            toast.show(
                                result.exitCode == 0 ? "\(name) logged out" : result.output,
                                isError: result.exitCode != 0
                            )
                            loadingChannel = nil
                            await refresh()
                        }
                    } label: {
                        Text("Logout")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(loadingChannel != nil)
                }
            }
        }
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
