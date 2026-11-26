# AgentCenter for macOS

A native macOS app (SwiftUI) for installing, running and managing [OpenClaw](https://docs.openclaw.ai)
AI agents on your own Mac. It wraps the `openclaw` command line tool and talks to the local OpenClaw
gateway, so everything runs on the machine.

> [!NOTE]
> The hosted AgentCenter service at agentcenter.cloud has been shut down. This app never depended on
> it: it only uses the local `openclaw` CLI and the gateway on `127.0.0.1`, so it keeps working.

## What it does

- **Guided setup:** checks for and installs Homebrew, Node.js and OpenClaw, then runs
  `openclaw onboard --install-daemon` to start the gateway.
- **Dashboard:** agents, sessions, logs and gateway status, with a sidebar for each area below.
- **Agents:** create, edit and delete agents and switch between them.
- **Models:** pick providers and models and save API keys through `openclaw onboard`.
- **Channels:** step-by-step setup for Telegram, Discord, Slack, WhatsApp, Mattermost, Matrix, Signal,
  Microsoft Teams, Google Chat, IRC, Nostr, iMessage and more.
- **Memory, Skills & Plugins, Tools, Automation (cron), Hooks, Approvals, Devices, Usage & Cost** and a
  built-in **Terminal**.

## Requirements

- macOS 26.2 or later (the project's deployment target)
- Xcode 26 or later to build
- Homebrew and Node.js (the app offers to install them on first run)

## Build and run

1. Open `app.xcodeproj` in Xcode.
2. Select the `app` scheme and your Mac as the destination.
3. Press Run.

The project ships without a development team. Pick your own under the target's **Signing & Capabilities**
before the first run, and keep that change out of your commits. The bundle identifier is `agentcenter.app`;
change it too if you distribute your own build.

## How it works

| Piece | File |
|---|---|
| Runs `openclaw` commands and captures their output | `app/ShellService.swift`, `app/OpenClawService.swift` |
| WebSocket connection to the gateway at `ws://127.0.0.1:18789` | `app/GatewayWebSocket.swift` |
| App state shared across views | `app/AppState.swift` |
| First-run setup | `app/OnboardingView.swift`, `app/SetupView.swift` |
| Main window and sidebar | `app/ContentView.swift`, `app/DashboardView.swift` |

The project uses an Xcode folder-synchronized group, so new Swift files are picked up automatically. A
few views (`ApprovalsView.swift`, `CronView.swift`, `DevicesView.swift`, `HooksView.swift`,
`MarkdownTextView.swift`, `ToolsCatalogView.swift`, `UsageCostView.swift`) live at the repository root and
are referenced from the project file.

OpenClaw's own configuration lives under `~/.openclaw/`. The app changes it mostly through the CLI,
and edits OpenClaw's auth profile file directly when you change or remove a provider key. Provider keys
therefore sit in OpenClaw's files on the Mac, not in this app.

## Contributing and security

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
- Report security problems privately as described in [SECURITY.md](SECURITY.md), never in a public issue.
- Questions and ideas go to [Discussions](https://github.com/MissionControlSquad/macos-app/discussions).

## License

[MIT](LICENSE). Copyright © 2026 Jagodana LLC. OpenClaw is a separate project with its own license.
