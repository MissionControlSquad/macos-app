import SwiftUI

// MARK: - Channel Definitions

/// Setup field: a single credential or config value the user needs to provide
struct ChannelSetupField: Identifiable {
    let id: String        // config key suffix, e.g. "botToken"
    let label: String     // display label
    let placeholder: String
    let configKey: String // full config path, e.g. "channels.telegram.botToken"
    let isSecret: Bool    // mask input
    let isRequired: Bool
    let helpText: String?

    init(id: String, label: String, placeholder: String, configKey: String,
         isSecret: Bool = true, isRequired: Bool = true, helpText: String? = nil) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.configKey = configKey
        self.isSecret = isSecret
        self.isRequired = isRequired
        self.helpText = helpText
    }
}

/// Setup step: an instruction for the user (external action like creating a bot)
struct ChannelSetupStep {
    let instruction: String
    let url: String?      // external link to open
}

/// Full channel definition with setup flow
struct ChannelDef: Identifiable {
    let key: String
    let name: String
    let icon: String
    let description: String
    let steps: [ChannelSetupStep]  // pre-setup instructions
    let fields: [ChannelSetupField] // config fields to fill in
    let docsURL: String

    var id: String { key }
}

private let channels: [ChannelDef] = [
    ChannelDef(
        key: "telegram", name: "Telegram", icon: "paperplane.fill",
        description: "Connect to Telegram via BotFather bot token.",
        steps: [
            ChannelSetupStep(instruction: "Open Telegram and message @BotFather", url: "https://t.me/BotFather"),
            ChannelSetupStep(instruction: "Send /newbot and follow the prompts", url: nil),
            ChannelSetupStep(instruction: "Copy the bot token (format: 123:abc)", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "botToken", label: "Bot Token", placeholder: "123456:ABC-DEF...",
                              configKey: "channels.telegram.botToken"),
        ],
        docsURL: "https://docs.openclaw.ai/channels/telegram"
    ),
    ChannelDef(
        key: "discord", name: "Discord", icon: "gamecontroller.fill",
        description: "Connect to Discord with a bot application token.",
        steps: [
            ChannelSetupStep(instruction: "Go to Discord Developer Portal → New Application", url: "https://discord.com/developers/applications"),
            ChannelSetupStep(instruction: "Go to Bot → Add Bot → copy the Token", url: nil),
            ChannelSetupStep(instruction: "Enable Message Content Intent under Privileged Gateway Intents", url: nil),
            ChannelSetupStep(instruction: "Use OAuth2 URL Generator to invite bot (scopes: bot, applications.commands)", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "token", label: "Bot Token", placeholder: "MTIz...",
                              configKey: "channels.discord.token"),
        ],
        docsURL: "https://docs.openclaw.ai/channels/discord"
    ),
    ChannelDef(
        key: "slack", name: "Slack", icon: "number",
        description: "Connect to Slack with bot and app tokens (Socket Mode).",
        steps: [
            ChannelSetupStep(instruction: "Create a Slack app at api.slack.com", url: "https://api.slack.com/apps"),
            ChannelSetupStep(instruction: "Enable Socket Mode and generate an App Token (connections:write)", url: nil),
            ChannelSetupStep(instruction: "Install app to workspace and copy the Bot Token from OAuth", url: nil),
            ChannelSetupStep(instruction: "Subscribe to events: app_mention, message.im, message.channels", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "botToken", label: "Bot Token", placeholder: "xoxb-...",
                              configKey: "channels.slack.botToken"),
            ChannelSetupField(id: "appToken", label: "App Token", placeholder: "xapp-...",
                              configKey: "channels.slack.appToken"),
        ],
        docsURL: "https://docs.openclaw.ai/channels/slack"
    ),
    ChannelDef(
        key: "whatsapp", name: "WhatsApp", icon: "message.fill",
        description: "Connect to WhatsApp via QR code linking.",
        steps: [
            ChannelSetupStep(instruction: "Start the gateway: openclaw gateway", url: nil),
            ChannelSetupStep(instruction: "Run: openclaw channels login --channel whatsapp", url: nil),
            ChannelSetupStep(instruction: "Scan the QR code with WhatsApp on your phone", url: nil),
        ],
        fields: [],
        docsURL: "https://docs.openclaw.ai/channels/whatsapp"
    ),
    ChannelDef(
        key: "mattermost", name: "Mattermost", icon: "bubble.left.fill",
        description: "Connect to a Mattermost instance with a bot token.",
        steps: [
            ChannelSetupStep(instruction: "Create a bot account in Mattermost → Integrations → Bot Accounts", url: nil),
            ChannelSetupStep(instruction: "Copy the bot token and your Mattermost server URL", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "botToken", label: "Bot Token", placeholder: "mm-token...",
                              configKey: "channels.mattermost.botToken"),
            ChannelSetupField(id: "baseUrl", label: "Server URL", placeholder: "https://chat.example.com",
                              configKey: "channels.mattermost.baseUrl", isSecret: false),
        ],
        docsURL: "https://docs.openclaw.ai/channels/mattermost"
    ),
    ChannelDef(
        key: "matrix", name: "Matrix", icon: "square.grid.3x3.fill",
        description: "Connect to a Matrix homeserver with an access token.",
        steps: [
            ChannelSetupStep(instruction: "Create a Matrix account on any homeserver", url: "https://matrix.org/ecosystem/hosting/"),
            ChannelSetupStep(instruction: "Obtain an access token via the Matrix login API or Element settings", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "homeserver", label: "Homeserver URL", placeholder: "https://matrix.example.org",
                              configKey: "channels.matrix.homeserver", isSecret: false),
            ChannelSetupField(id: "accessToken", label: "Access Token", placeholder: "syt_...",
                              configKey: "channels.matrix.accessToken"),
        ],
        docsURL: "https://docs.openclaw.ai/channels/matrix"
    ),
    ChannelDef(
        key: "signal", name: "Signal", icon: "lock.shield.fill",
        description: "Connect to Signal via signal-cli (requires external setup).",
        steps: [
            ChannelSetupStep(instruction: "Install signal-cli on the gateway host", url: "https://github.com/AsamK/signal-cli/releases"),
            ChannelSetupStep(instruction: "Either link an existing account (signal-cli link) or register a new number", url: nil),
            ChannelSetupStep(instruction: "Enter the phone number used with signal-cli below", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "account", label: "Phone Number", placeholder: "+15551234567",
                              configKey: "channels.signal.account", isSecret: false),
            ChannelSetupField(id: "cliPath", label: "signal-cli Path", placeholder: "signal-cli",
                              configKey: "channels.signal.cliPath", isSecret: false, isRequired: false,
                              helpText: "Leave empty if signal-cli is on PATH"),
        ],
        docsURL: "https://docs.openclaw.ai/channels/signal"
    ),
    ChannelDef(
        key: "msteams", name: "MS Teams", icon: "person.3.fill",
        description: "Connect to Microsoft Teams via Azure Bot registration.",
        steps: [
            ChannelSetupStep(instruction: "Create an Azure Bot at portal.azure.com", url: "https://portal.azure.com/#create/Microsoft.AzureBot"),
            ChannelSetupStep(instruction: "Copy the App ID, create a client secret, and note the Tenant ID", url: nil),
            ChannelSetupStep(instruction: "Enable the Teams channel in Azure Bot → Channels", url: nil),
            ChannelSetupStep(instruction: "Install the plugin: openclaw plugins install @openclaw/msteams", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "appId", label: "App ID", placeholder: "00000000-0000-...",
                              configKey: "channels.msteams.appId", isSecret: false),
            ChannelSetupField(id: "appPassword", label: "App Password", placeholder: "Client secret value",
                              configKey: "channels.msteams.appPassword"),
            ChannelSetupField(id: "tenantId", label: "Tenant ID", placeholder: "00000000-0000-...",
                              configKey: "channels.msteams.tenantId", isSecret: false),
        ],
        docsURL: "https://docs.openclaw.ai/channels/msteams"
    ),
    ChannelDef(
        key: "googlechat", name: "Google Chat", icon: "bubble.left.and.text.bubble.right.fill",
        description: "Connect to Google Chat with a service account.",
        steps: [
            ChannelSetupStep(instruction: "Create a Google Cloud project and enable Chat API", url: "https://console.cloud.google.com"),
            ChannelSetupStep(instruction: "Create a service account and download the credentials JSON", url: nil),
            ChannelSetupStep(instruction: "Configure the Chat app in Google Admin → Chat API settings", url: nil),
        ],
        fields: [],
        docsURL: "https://docs.openclaw.ai/channels/googlechat"
    ),
    ChannelDef(
        key: "irc", name: "IRC", icon: "terminal.fill",
        description: "Connect to an IRC server with nick and channel list.",
        steps: [
            ChannelSetupStep(instruction: "Choose an IRC server (e.g. irc.libera.chat)", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "host", label: "Server", placeholder: "irc.libera.chat",
                              configKey: "channels.irc.host", isSecret: false),
            ChannelSetupField(id: "nick", label: "Nickname", placeholder: "openclaw-bot",
                              configKey: "channels.irc.nick", isSecret: false),
            ChannelSetupField(id: "ircChannels", label: "Channels", placeholder: "#openclaw, #general",
                              configKey: "channels.irc.channels", isSecret: false,
                              helpText: "Comma-separated list of channels to join"),
        ],
        docsURL: "https://docs.openclaw.ai/channels/irc"
    ),
    ChannelDef(
        key: "nostr", name: "Nostr", icon: "antenna.radiowaves.left.and.right",
        description: "Connect to the Nostr protocol with a private key.",
        steps: [
            ChannelSetupStep(instruction: "Generate a keypair: nak key generate (or use an existing nsec)", url: nil),
            ChannelSetupStep(instruction: "Install the plugin: openclaw plugins install @openclaw/nostr", url: nil),
        ],
        fields: [
            ChannelSetupField(id: "privateKey", label: "Private Key", placeholder: "nsec1...",
                              configKey: "channels.nostr.privateKey"),
        ],
        docsURL: "https://docs.openclaw.ai/channels/nostr"
    ),
    ChannelDef(
        key: "imessage", name: "iMessage", icon: "message.badge.filled.fill",
        description: "Connect to iMessage (macOS only).",
        steps: [
            ChannelSetupStep(instruction: "Ensure iMessage is set up on this Mac", url: nil),
        ],
        fields: [],
        docsURL: "https://docs.openclaw.ai/channels/imessage"
    ),
]

// MARK: - Channels View

struct ChannelsView: View {
    @Bindable var service: OpenClawService
    @State private var enabledChannels: Set<String> = []
    @State private var isLoading = false
    @State private var toast = ToastState()
    @State private var busyChannel: String?
    @State private var setupChannel: ChannelDef?
    @State private var showWhatsAppSetup = false

    private var connectedChannels: [ChannelDef] {
        channels.filter { enabledChannels.contains($0.key) }
    }

    private var availableChannels: [ChannelDef] {
        channels.filter { !enabledChannels.contains($0.key) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Connected channels section
                if isLoading {
                    GroupBox {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Checking channels…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                    } label: {
                        SectionHeader("Connected")
                    }
                } else if !connectedChannels.isEmpty {
                    GroupBox {
                        VStack(spacing: 1) {
                            ForEach(connectedChannels) { channel in
                                connectedRow(channel: channel)
                                if channel.id != connectedChannels.last?.id {
                                    Divider()
                                }
                            }
                        }
                    } label: {
                        SectionHeader("Connected", count: connectedChannels.count)
                    }
                }

                // Available channels grid
                GroupBox {
                    if !isLoading && connectedChannels.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("No channels connected yet. Choose a platform below to get started.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 10) {
                        ForEach(availableChannels) { channel in
                            availableCard(channel: channel)
                        }
                    }
                } label: {
                    SectionHeader("Available", count: availableChannels.count)
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
                .help("Refresh channel status")
            }
        }
        .task { await refresh() }
        .sheet(item: $setupChannel) { channel in
            ChannelSetupSheet(channel: channel, service: service, toast: $toast) {
                setupChannel = nil
                Task { await refresh() }
            }
        }
        .sheet(isPresented: $showWhatsAppSetup) {
            WhatsAppSetupSheet(service: service) {
                showWhatsAppSetup = false
                Task { await refresh() }
            }
        }
    }

    // MARK: - Connected Row

    private func connectedRow(channel: ChannelDef) -> some View {
        HStack(spacing: 12) {
            // Green status dot
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            Image(systemName: channel.icon)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 20)

            Text(channel.name)
                .font(.body.weight(.medium))

            Spacer()

            Button {
                if channel.key == "whatsapp" {
                    showWhatsAppSetup = true
                } else {
                    setupChannel = channel
                }
            } label: {
                Text("Settings")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                Task {
                    busyChannel = channel.key
                    let r = await service.disableChannel(channel: channel.key)
                    busyChannel = nil
                    toast.show(
                        r.exitCode == 0 ? "\(channel.name) disconnected" : r.output,
                        isError: r.exitCode != 0
                    )
                    await refresh()
                }
            } label: {
                if busyChannel == channel.key {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Disconnect")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(busyChannel != nil)

            Link(destination: URL(string: channel.docsURL)!) {
                Image(systemName: "book")
                    .foregroundStyle(.secondary)
            }
            .help("View docs")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Available Card

    private func availableCard(channel: ChannelDef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: channel.icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(channel.name)
                    .font(.headline)
                Spacer()
            }

            Text(channel.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button {
                    if channel.key == "whatsapp" {
                        showWhatsAppSetup = true
                    } else {
                        setupChannel = channel
                    }
                } label: {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Link(destination: URL(string: channel.docsURL)!) {
                    Image(systemName: "book")
                        .foregroundStyle(.secondary)
                }
                .help("View docs")
            }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Data

    private func refresh() async {
        isLoading = true
        var enabled: Set<String> = []

        // Check each channel's enabled status in parallel
        await withTaskGroup(of: (String, Bool).self) { group in
            for channel in channels {
                group.addTask {
                    let r = await service.configGet("channels.\(channel.key).enabled")
                    let val = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (channel.key, r.exitCode == 0 && val == "true")
                }
            }
            for await (key, isEnabled) in group {
                if isEnabled { enabled.insert(key) }
            }
        }

        enabledChannels = enabled
        isLoading = false
    }
}

// MARK: - Channel Setup Sheet

struct ChannelSetupSheet: View {
    let channel: ChannelDef
    let service: OpenClawService
    @Binding var toast: ToastState
    let onDone: () -> Void

    @State private var fieldValues: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveResult: SaveResult?
    @State private var currentStep = 0

    enum SaveResult {
        case success
        case failure(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: channel.icon)
                    .font(.title2)
                    .foregroundStyle(.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect \(channel.name)")
                        .font(.title3.weight(.semibold))
                    Text(channel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { onDone() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !channel.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Setup Steps")
                                .font(.headline)

                            ForEach(Array(channel.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.4))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.instruction)
                                            .font(.callout)

                                        if let url = step.url, let link = URL(string: url) {
                                            Link(url, destination: link)
                                                .font(.caption)
                                        }
                                    }
                                }
                                .onTapGesture {
                                    currentStep = index
                                }
                            }
                        }
                    }

                    if !channel.fields.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Credentials")
                                .font(.headline)

                            ForEach(channel.fields) { field in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Text(field.label)
                                            .font(.subheadline.weight(.medium))
                                        if field.isRequired {
                                            Text("*")
                                                .foregroundStyle(.red)
                                        }
                                    }

                                    if field.isSecret {
                                        SecureField(field.placeholder, text: binding(for: field.id))
                                            .textFieldStyle(.roundedBorder)
                                    } else {
                                        TextField(field.placeholder, text: binding(for: field.id))
                                            .textFieldStyle(.roundedBorder)
                                    }

                                    if let help = field.helpText {
                                        Text(help)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(field.configKey)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }

                    if channel.fields.isEmpty && channel.key != "imessage" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Configuration Required")
                                .font(.headline)
                            Text("This channel requires manual configuration. Follow the steps above, then click Enable to activate it.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Link("View full setup guide →", destination: URL(string: channel.docsURL)!)
                                .font(.callout)
                        }
                    }

                    if let result = saveResult {
                        switch result {
                        case .success:
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(channel.name) configured and enabled")
                                        .font(.callout.weight(.medium))
                                    Text("Restart the gateway to apply: openclaw gateway restart")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        case .failure(let msg):
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(msg)
                                    .font(.caption)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") { onDone() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if saveResult?.isSuccess == true {
                    Button("Restart Gateway") {
                        Task {
                            isSaving = true
                            _ = await service.restartGateway()
                            isSaving = false
                            toast.show("\(channel.name) — gateway restarting")
                            onDone()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Done") { onDone() }
                } else if channel.fields.isEmpty {
                    Button {
                        Task { await enableOnly() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Enable")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                } else {
                    Button {
                        Task { await saveAndEnable() }
                    } label: {
                        if isSaving {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Saving…")
                            }
                        } else {
                            Text("Save & Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !allRequiredFieldsFilled)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 560)
    }

    private func binding(for fieldId: String) -> Binding<String> {
        Binding(
            get: { fieldValues[fieldId, default: ""] },
            set: { fieldValues[fieldId] = $0 }
        )
    }

    private var allRequiredFieldsFilled: Bool {
        channel.fields.filter(\.isRequired).allSatisfy { field in
            !(fieldValues[field.id, default: ""].trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func saveAndEnable() async {
        isSaving = true
        saveResult = nil

        for field in channel.fields {
            let value = fieldValues[field.id, default: ""].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            let result: CommandResult
            if field.id == "ircChannels" {
                let items = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let json = "[" + items.map { "\"\($0)\"" }.joined(separator: ",") + "]"
                result = await service.configSetJSON(field.configKey, value: json)
            } else {
                result = await service.configSetString(field.configKey, value: value)
            }

            if result.exitCode != 0 {
                saveResult = .failure("Failed to set \(field.label): \(result.output)")
                isSaving = false
                return
            }
        }

        let enableResult = await service.enableChannel(channel: channel.key)
        if enableResult.exitCode != 0 {
            saveResult = .failure("Failed to enable: \(enableResult.output)")
            isSaving = false
            return
        }

        saveResult = .success
        isSaving = false
    }

    private func enableOnly() async {
        isSaving = true
        let r = await service.enableChannel(channel: channel.key)
        if r.exitCode == 0 {
            saveResult = .success
        } else {
            saveResult = .failure(r.output)
        }
        isSaving = false
    }
}

// MARK: - WhatsApp Setup (Checklist Style)

struct WhatsAppSetupSheet: View {
    let service: OpenClawService
    let onDone: () -> Void

    // Gateway
    @State private var gatewayRunning = false
    @State private var isCheckingGateway = true
    @State private var isStartingGateway = false

    // Link
    @State private var whatsappLinked = false
    @State private var loginProcess: StreamingProcess?
    @State private var linkError: String?
    @State private var showQR = false

    // Config
    @State private var configSaved = false
    @State private var dmPolicy = "pairing"
    @State private var allowedNumber = ""
    @State private var isSavingConfig = false

    // Pairing
    @State private var pairingCode = ""
    @State private var isApprovingPairing = false
    @State private var pairingResult: String?

    // Expand/collapse — nil means auto (show incomplete steps expanded)
    @State private var expandedStep: Int?

    // Track saved config values so we know when user changed something
    @State private var savedDmPolicy = ""
    @State private var savedAllowedNumber = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "message.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect WhatsApp")
                        .font(.title3.weight(.semibold))
                    Text("Complete each step to connect your WhatsApp account")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { cleanup(); onDone() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Checklist
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // 1. Gateway
                    checklistItem(
                        number: 1,
                        title: "Gateway Running",
                        subtitle: "The gateway manages your WhatsApp connection",
                        isComplete: gatewayRunning,
                        isChecking: isCheckingGateway
                    ) {
                        if !gatewayRunning && !isCheckingGateway {
                            HStack(spacing: 8) {
                                Button {
                                    Task { await startGateway() }
                                } label: {
                                    if isStartingGateway {
                                        HStack(spacing: 4) {
                                            ProgressView().controlSize(.small)
                                            Text("Starting…")
                                        }
                                    } else {
                                        Label("Start Gateway", systemImage: "play.fill")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isStartingGateway)

                                Button {
                                    Task { await checkGateway() }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    Divider().padding(.leading, 40)

                    // 2. Link WhatsApp
                    checklistItem(
                        number: 2,
                        title: "WhatsApp Linked",
                        subtitle: "Scan a QR code to connect your WhatsApp account",
                        isComplete: whatsappLinked,
                        isChecking: false
                    ) {
                        if showQR {
                            qrSection
                        } else {
                            HStack(spacing: 8) {
                                if whatsappLinked {
                                    Button {
                                        showQR = true
                                        whatsappLinked = false
                                        startLoginProcess()
                                    } label: {
                                        Label("Re-link Device", systemImage: "qrcode")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(!gatewayRunning)
                                } else {
                                    Button {
                                        showQR = true
                                        startLoginProcess()
                                    } label: {
                                        Label("Scan QR Code", systemImage: "qrcode")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(!gatewayRunning)
                                }

                                Button {
                                    service.openInTerminal("openclaw channels login --channel whatsapp")
                                } label: {
                                    Label("Use Terminal", systemImage: "terminal")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!gatewayRunning)

                                if !gatewayRunning {
                                    Text("Start the gateway first")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Divider().padding(.leading, 40)

                    // 3. Configure Access
                    checklistItem(
                        number: 3,
                        title: "Access Control",
                        subtitle: "Choose who can message your bot and add your phone number",
                        isComplete: configSaved,
                        isChecking: false
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("DM Policy", selection: $dmPolicy) {
                                Text("Pairing — approve new users with a code (recommended)").tag("pairing")
                                Text("Allowlist — only pre-approved numbers").tag("allowlist")
                                Text("Open — anyone can message").tag("open")
                            }
                            .pickerStyle(.radioGroup)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your WhatsApp phone number (auto-approved):")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    TextField("+1 555 123 4567", text: $allowedNumber)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 200)

                                    if configChanged {
                                        Button {
                                            Task { await saveConfig() }
                                        } label: {
                                            if isSavingConfig {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Text("Save Changes")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .disabled(isSavingConfig || !whatsappLinked)
                                    } else if !configSaved {
                                        Button {
                                            Task { await saveConfig() }
                                        } label: {
                                            if isSavingConfig {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Text("Save")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .disabled(isSavingConfig || !whatsappLinked)
                                    }
                                }
                            }

                            if !whatsappLinked && !configSaved {
                                Text("Link WhatsApp first (step 2)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 4. Test / Pair — only shown for pairing mode
                    if dmPolicy == "pairing" {
                        Divider().padding(.leading, 40)

                        checklistItem(
                            number: 4,
                            title: "Test Connection",
                            subtitle: "Send a message and approve the pairing code",
                            isComplete: pairingResult?.contains("Approved") == true || pairingResult?.contains("approved") == true,
                            isChecking: false
                        ) {
                            if configSaved {
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. Open WhatsApp on your phone")
                                        Text("2. Send any message to your bot's number")
                                        Text("3. You'll receive an 8-character code — enter it below:")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    HStack(spacing: 8) {
                                        TextField("AB12CD34", text: $pairingCode)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(maxWidth: 160)

                                        Button {
                                            Task { await approvePairing() }
                                        } label: {
                                            if isApprovingPairing {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Label("Approve", systemImage: "checkmark.circle")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .disabled(pairingCode.trimmingCharacters(in: .whitespaces).isEmpty || isApprovingPairing)
                                    }

                                    if let result = pairingResult {
                                        let isSuccess = result.contains("approved") || result.contains("Approved")
                                        HStack(spacing: 6) {
                                            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .foregroundStyle(isSuccess ? .green : .red)
                                            Text(result)
                                                .font(.caption)
                                        }
                                    }
                                }
                            } else {
                                Text("Complete the steps above first")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { cleanup(); onDone() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 540, height: 540)
        .task { await detectState() }
    }

    // MARK: - Config Change Tracking

    /// Whether the user has changed config values from what's saved
    private var configChanged: Bool {
        configSaved && (dmPolicy != savedDmPolicy || allowedNumber != savedAllowedNumber)
    }

    // MARK: - Expand/Collapse Helpers

    /// Whether a step should show its content expanded
    private func isExpanded(_ step: Int) -> Bool {
        if let expanded = expandedStep {
            return expanded == step
        }
        // Auto-expand: show the first incomplete step
        return false
    }

    // MARK: - Checklist Item

    private func checklistItem<Content: View>(
        number: Int,
        title: String,
        subtitle: String,
        isComplete: Bool,
        isChecking: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let expanded = expandedStep == number

        return VStack(alignment: .leading, spacing: 0) {
            // Clickable header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedStep = expanded ? nil : number
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // Status icon
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 24, height: 24)
                    } else if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                            .frame(width: 24, height: 24)
                    } else {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1.5)
                                .frame(width: 24, height: 24)
                            Text("\(number)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(isComplete && !expanded ? .secondary : .primary)
                            if isComplete {
                                Text("Done")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        if !expanded {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            // Expandable content
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    content()
                        .padding(.top, 2)
                }
                .padding(.leading, 36)
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - QR Section

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = linkError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Retry") {
                        linkError = nil
                        startLoginProcess()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        service.openInTerminal("openclaw channels login --channel whatsapp")
                    } label: {
                        Label("Use Terminal", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if let process = loginProcess {
                if process.isRunning && process.output.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for QR code…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !process.output.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open WhatsApp → Settings → Linked Devices → Link a Device, then scan:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        GroupBox {
                            Text(process.output)
                                .font(.system(size: 4, design: .monospaced))
                                .lineSpacing(-2)
                                .kerning(-0.5)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(4)
                        }
                        .background(.white)
                        .frame(maxHeight: 180)
                    }

                    if !process.isRunning && process.exitCode == 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Linked successfully!")
                                .font(.caption.weight(.medium))
                        }
                        .onAppear { whatsappLinked = true }
                    }

                    if process.isRunning {
                        Button("Stop") { process.stop() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func detectState() async {
        isCheckingGateway = true

        // Check gateway
        await service.fetchGatewayStatus()
        gatewayRunning = service.gatewayStatus?.running ?? false
        isCheckingGateway = false

        // Check if WhatsApp is enabled (linked previously)
        let enabledResult = await service.configGet("channels.whatsapp.enabled")
        if enabledResult.exitCode == 0 {
            let val = enabledResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if val == "true" {
                whatsappLinked = true
            }
        }

        // Check if config was already saved
        let policyResult = await service.configGet("channels.whatsapp.dmPolicy")
        if policyResult.exitCode == 0 {
            let value = policyResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            if !value.isEmpty && value != "null" && value != "undefined" {
                configSaved = true
                dmPolicy = value
                savedDmPolicy = value
            }
        }

        // Load saved phone number
        let allowResult = await service.configGet("channels.whatsapp.allowFrom")
        if allowResult.exitCode == 0 {
            let raw = allowResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = raw.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
               let first = arr.first {
                allowedNumber = first
                savedAllowedNumber = first
            }
        }

        // Auto-expand the first incomplete step
        if !gatewayRunning {
            expandedStep = 1
        } else if !whatsappLinked {
            expandedStep = 2
        } else if !configSaved {
            expandedStep = 3
        } else if dmPolicy == "pairing" {
            expandedStep = 4
        }
    }

    private func checkGateway() async {
        isCheckingGateway = true
        await service.fetchGatewayStatus()
        gatewayRunning = service.gatewayStatus?.running ?? false
        isCheckingGateway = false
    }

    private func startGateway() async {
        isStartingGateway = true
        _ = await service.startGateway()
        try? await Task.sleep(for: .seconds(3))
        await checkGateway()
        isStartingGateway = false
    }

    private func saveConfig() async {
        isSavingConfig = true
        _ = await service.configSetString("channels.whatsapp.dmPolicy", value: dmPolicy)

        if !allowedNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            let number = allowedNumber.trimmingCharacters(in: .whitespaces)
            _ = await service.configSetJSON("channels.whatsapp.allowFrom", value: "[\"\(number)\"]")
        }

        _ = await service.enableChannel(channel: "whatsapp")
        configSaved = true
        savedDmPolicy = dmPolicy
        savedAllowedNumber = allowedNumber
        isSavingConfig = false
    }

    private func startLoginProcess() {
        loginProcess = service.channelLoginStreaming(channel: "whatsapp")
        loginProcess?.start()

        Task {
            try? await Task.sleep(for: .seconds(5))
            if let proc = loginProcess, !proc.isRunning && proc.exitCode != 0 {
                linkError = proc.output.isEmpty ? "Process exited with code \(proc.exitCode)" : proc.output
                loginProcess = nil
            }
        }
    }

    private func approvePairing() async {
        let code = pairingCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isApprovingPairing = true
        let r = await service.pairingApprove(channel: "whatsapp", code: code)
        if r.exitCode == 0 {
            pairingResult = "Approved! \(r.output)"
            pairingCode = ""
        } else {
            pairingResult = r.output
        }
        isApprovingPairing = false
    }

    private func cleanup() {
        loginProcess?.stop()
        loginProcess = nil
    }
}
