import SwiftUI

struct DevicesView: View {
    @Bindable var gateway: GatewayWebSocket
    @State private var pairedDevices: [[String: Any]] = []
    @State private var pendingDevices: [[String: Any]] = []
    @State private var isLoading = false
    @State private var toast = ToastState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Pending pairing requests
                if !pendingDevices.isEmpty {
                    GroupBox {
                        ForEach(Array(pendingDevices.enumerated()), id: \.offset) { _, device in
                            pendingDeviceRow(device)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.orange)
                            Text("Pending Pairing Requests")
                            Spacer()
                            Text("\(pendingDevices.count)")
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }

                // Paired devices
                GroupBox {
                    if pairedDevices.isEmpty && !isLoading {
                        Text("No paired devices found.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(Array(pairedDevices.enumerated()), id: \.offset) { _, device in
                            pairedDeviceRow(device)
                        }
                    }
                } label: {
                    HStack {
                        Text("Paired Devices")
                        Spacer()
                        Text("\(pairedDevices.count) device\(pairedDevices.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Presence (online devices)
                if !gateway.presenceEntries.isEmpty {
                    GroupBox {
                        ForEach(Array(gateway.presenceEntries.enumerated()), id: \.offset) { _, entry in
                            presenceRow(entry)
                        }
                    } label: {
                        HStack {
                            Text("Online Now")
                            Spacer()
                            Text("\(gateway.presenceEntries.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ToastBanner(toast: toast)
            }
            .padding()
        }
        .navigationTitle("Devices")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ConnectionBadge(isConnected: gateway.isConnected)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh devices")
            }
        }
        .task {
            await loadDevices()
        }
    }

    // MARK: - Pending Device Row

    private func pendingDeviceRow(_ device: [String: Any]) -> some View {
        let requestId = device["requestId"] as? String ?? device["deviceId"] as? String ?? "unknown"
        let platform = device["platform"] as? String ?? "unknown"
        let clientId = device["clientId"] as? String ?? ""
        let clientMode = device["clientMode"] as? String ?? ""

        return HStack(spacing: 12) {
            Image(systemName: platformIcon(platform))
                .font(.title2)
                .foregroundStyle(Color.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(clientId.isEmpty ? "Unknown Client" : clientId)
                    .font(.callout.bold())
                HStack(spacing: 8) {
                    Text(platform)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !clientMode.isEmpty {
                        Text(clientMode)
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                CopyableText(requestId, preview: "ID: \(requestId.prefix(16))...")
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    rejectDevice(requestId: requestId)
                } label: {
                    Label("Reject", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    approveDevice(requestId: requestId)
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(6)
    }

    // MARK: - Paired Device Row

    private func pairedDeviceRow(_ device: [String: Any]) -> some View {
        let deviceId = device["deviceId"] as? String ?? "unknown"
        let platform = device["platform"] as? String ?? "unknown"
        let clientId = device["clientId"] as? String ?? ""
        let clientMode = device["clientMode"] as? String ?? ""
        let role = device["role"] as? String ?? ""
        let scopes = device["scopes"] as? [String] ?? device["approvedScopes"] as? [String] ?? []
        let createdAtMs = device["createdAtMs"] as? Double ?? device["approvedAtMs"] as? Double

        return HStack(spacing: 12) {
            Image(systemName: platformIcon(platform))
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(clientId.isEmpty ? "Device" : clientId)
                        .font(.callout.bold())
                    if !role.isEmpty {
                        StatusBadge(label: role, color: Color.purple)
                    }
                }

                HStack(spacing: 8) {
                    Text(platform)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !clientMode.isEmpty {
                        Text(clientMode)
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                    if let ts = createdAtMs {
                        Text("Paired \(formattedDate(ts))")
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }

                if !scopes.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(scopes.prefix(4), id: \.self) { scope in
                            Text(scope.replacingOccurrences(of: "operator.", with: ""))
                                .font(.system(.caption2, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if scopes.count > 4 {
                            Text("+\(scopes.count - 4)")
                                .font(.caption2)
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                }

                CopyableText(deviceId, preview: "\(deviceId.prefix(20))...")
            }

            Spacer()

            Button {
                removeDevice(deviceId: deviceId)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
            .help("Remove device")
        }
        .padding(6)
    }

    // MARK: - Presence Row

    private func presenceRow(_ entry: [String: Any]) -> some View {
        let clientId = entry["clientId"] as? String ?? entry["client"] as? String ?? "Unknown"
        let platform = entry["platform"] as? String ?? ""
        let mode = entry["mode"] as? String ?? entry["clientMode"] as? String ?? ""

        return HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Image(systemName: platformIcon(platform))
                .font(.callout)
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)

            Text(clientId)
                .font(.callout)

            if !platform.isEmpty {
                Text(platform)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !mode.isEmpty {
                Text(mode)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }

            Spacer()
        }
        .padding(6)
    }

    // MARK: - Actions

    private func approveDevice(requestId: String) {
        Task {
            isLoading = true
            do {
                _ = try await gateway.devicePairApprove(requestId: requestId)
                toast.show("Device approved")
                await loadDevices()
            } catch {
                toast.show(error.localizedDescription, isError: true)
            }
            isLoading = false
        }
    }

    private func rejectDevice(requestId: String) {
        Task {
            isLoading = true
            do {
                _ = try await gateway.devicePairReject(requestId: requestId)
                toast.show("Device rejected")
                await loadDevices()
            } catch {
                toast.show(error.localizedDescription, isError: true)
            }
            isLoading = false
        }
    }

    private func removeDevice(deviceId: String) {
        Task {
            isLoading = true
            do {
                _ = try await gateway.devicePairRemove(deviceId: deviceId)
                toast.show("Device removed")
                await loadDevices()
            } catch {
                toast.show(error.localizedDescription, isError: true)
            }
            isLoading = false
        }
    }

    // MARK: - Helpers

    private func platformIcon(_ platform: String) -> String {
        switch platform.lowercased() {
        case "darwin", "macos": return "desktopcomputer"
        case "linux": return "server.rack"
        case "win32", "windows": return "pc"
        case "ios": return "iphone"
        case "android": return "phone"
        default: return "laptopcomputer"
        }
    }

    private func formattedDate(_ ms: Double) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadDevices() async {
        guard gateway.isConnected else { return }
        isLoading = true

        do {
            let result = try await gateway.devicePairList()
            if let paired = result["paired"] as? [[String: Any]] {
                pairedDevices = paired
            } else if let devices = result["devices"] as? [[String: Any]] {
                pairedDevices = devices
            }
            if let pending = result["pending"] as? [[String: Any]] {
                pendingDevices = pending
            }
        } catch {
            toast.show(error.localizedDescription, isError: true)
        }

        isLoading = false
    }
}
