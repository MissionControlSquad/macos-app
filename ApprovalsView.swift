import SwiftUI

struct ApprovalsView: View {
    @Bindable var gateway: GatewayWebSocket
    @State private var isLoading = false
    @State private var toast = ToastState()

    var body: some View {
        Group {
            if gateway.pendingApprovals.isEmpty {
                EmptyStateView(
                    icon: "checkmark.shield",
                    title: "No Pending Approvals",
                    message: "When an agent requests tool execution that needs your approval, it will appear here."
                )
            } else {
                List {
                    ForEach(Array(gateway.pendingApprovals.enumerated()), id: \.offset) { _, approval in
                        approvalRow(approval)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            ToastBanner(toast: toast)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .navigationTitle("Approvals")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ConnectionBadge(isConnected: gateway.isConnected)
            }
        }
    }

    private func approvalRow(_ approval: [String: Any]) -> some View {
        let requestId = approval["requestId"] as? String ?? "unknown"
        let tool = approval["tool"] as? String ?? approval["name"] as? String ?? "Unknown tool"
        let description = approval["description"] as? String ?? approval["message"] as? String ?? ""
        let sessionKey = approval["sessionKey"] as? String ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title3)
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool)
                        .font(.callout.bold())
                    if !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if !sessionKey.isEmpty {
                        Text("Session: \(sessionKey)")
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                    Text("ID: \(requestId.prefix(12))...")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        resolveApproval(requestId: requestId, decision: "rejected")
                    } label: {
                        Label("Reject", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        resolveApproval(requestId: requestId, decision: "approved")
                    } label: {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func resolveApproval(requestId: String, decision: String) {
        Task {
            isLoading = true
            do {
                _ = try await gateway.approvalResolve(requestId: requestId, decision: decision)
                toast.show("Approval \(decision)")
            } catch {
                toast.show(error.localizedDescription, isError: true)
            }
            isLoading = false
        }
    }
}
