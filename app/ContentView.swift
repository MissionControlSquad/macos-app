//
//  ContentView.swift
//  app
//
//  Created by DHARMIK JAGODANA on 10/03/26.
//

import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        Group {
            if appState.isChecking {
                loadingView
            } else if appState.needsSetup {
                OnboardingView(appState: appState)
            } else {
                DashboardView()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await appState.checkAll()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            Text("Checking your system")
                .font(.title3)

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(CheckItem.allCases, id: \.self) { item in
                        let status = appState.checkStatuses[item] ?? .pending

                        HStack(spacing: 12) {
                            ZStack {
                                if status == .checking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: statusIcon(status))
                                        .foregroundStyle(statusColor(status))
                                }
                            }
                            .frame(width: 20, height: 20)

                            Image(systemName: item.icon)
                                .foregroundStyle(status == .checking ? Color.accentColor : Color.secondary)
                                .frame(width: 16)

                            Text(item.rawValue)
                                .font(status == .checking ? .callout.bold() : .callout)
                                .foregroundStyle(status == .pending ? .tertiary : .primary)

                            Spacer()

                            if status == .passed {
                                Text(versionLabel(item))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        if item != CheckItem.allCases.last {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
            .frame(width: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusIcon(_ status: CheckStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .checking: return "circle" // unused, ProgressView shown instead
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: CheckStatus) -> Color {
        switch status {
        case .pending: return Color(nsColor: .quaternaryLabelColor)
        case .checking: return Color.accentColor
        case .passed: return Color.green
        case .failed: return Color.red.opacity(0.6)
        }
    }

    private func versionLabel(_ item: CheckItem) -> String {
        switch item {
        case .homebrew: return appState.brewVersion.components(separatedBy: " ").last ?? ""
        case .node: return appState.nodeVersion
        case .openclaw: return appState.openclawVersion.components(separatedBy: " ").last ?? ""
        case .gateway: return "running"
        case .onboarded: return "configured"
        default: return "installed"
        }
    }
}

#Preview {
    ContentView()
}
