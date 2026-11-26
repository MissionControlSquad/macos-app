# Contributing

Thanks for helping. Small, focused pull requests are the easiest to review and merge.

## Ground rules

- Be kind. Everyone taking part agrees to the [Code of Conduct](CODE_OF_CONDUCT.md).
- Security problems go through [private reporting](SECURITY.md), never a public issue or PR.
- For anything bigger than a fix, open a [discussion](https://github.com/MissionControlSquad/macos-app/discussions)
  or an issue first, so the approach is agreed before you spend time on it.

## Making a change

1. Fork the repository and create a branch from `main` (for example `fix/gateway-reconnect`).
2. Open `app.xcodeproj` in Xcode 26 or later and select your own team under
   **Signing & Capabilities**. Don't commit that change: keep your team ID out of the project file.
3. Build and run the `app` scheme, and check the change by hand against a local OpenClaw install.
4. Never log or persist provider API keys. The app hands keys to OpenClaw, which stores them in its
   own files under `~/.openclaw/`.
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/) (`fix:`, `feat:`,
   `docs:`, `chore:`), then open a pull request against `main` and fill in the template.

## Never commit secrets

Secret scanning with push protection is enabled on this repository and will block pushes that
contain recognised credentials. Per-user Xcode state (`xcuserdata/`, `DerivedData/`) is git-ignored.

## Review and merge

Every change lands through a pull request. The checks must pass and a code owner reviews it.
Pull requests are squash-merged, so the PR title becomes the commit message; write it as a
Conventional Commit.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
