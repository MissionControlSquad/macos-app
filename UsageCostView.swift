import SwiftUI

struct UsageCostView: View {
    @Bindable var gateway: GatewayWebSocket
    @Bindable var service: OpenClawService
    @State private var usageData: [String: Any] = [:]
    @State private var costData: [String: Any] = [:]
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Usage stats
                GroupBox("Token Usage") {
                    if usageData.isEmpty && !isLoading {
                        Text("No usage data available. Send some messages to see stats here.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                            usageCard("Input Tokens", value: formatNumber(usageData["inputTokens"]), icon: "arrow.up.doc", color: Color.accentColor)
                            usageCard("Output Tokens", value: formatNumber(usageData["outputTokens"]), icon: "arrow.down.doc", color: Color.green)
                            usageCard("Total Tokens", value: formatNumber(usageData["totalTokens"]), icon: "sum", color: Color.purple)
                            usageCard("Requests", value: formatNumber(usageData["requests"] ?? usageData["totalRequests"]), icon: "bubble.left.and.bubble.right", color: Color.orange)
                        }

                        // Per-model breakdown if available
                        if let models = usageData["models"] as? [[String: Any]], !models.isEmpty {
                            Divider()
                            Text("By Model")
                                .font(.subheadline.bold())

                            ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                                HStack {
                                    Text(model["model"] as? String ?? model["name"] as? String ?? "Unknown")
                                        .font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    if let tokens = model["totalTokens"] as? Int {
                                        Text("\(tokens) tokens")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let requests = model["requests"] as? Int {
                                        Text("\(requests) req")
                                            .font(.caption)
                                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                // Cost breakdown
                GroupBox("Cost Estimate") {
                    if costData.isEmpty && !isLoading {
                        Text("No cost data available yet.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                            if let total = costData["totalCost"] as? Double {
                                usageCard("Total Cost", value: String(format: "$%.4f", total), icon: "dollarsign.circle", color: Color.green)
                            }
                            if let inputCost = costData["inputCost"] as? Double {
                                usageCard("Input Cost", value: String(format: "$%.4f", inputCost), icon: "arrow.up", color: Color.accentColor)
                            }
                            if let outputCost = costData["outputCost"] as? Double {
                                usageCard("Output Cost", value: String(format: "$%.4f", outputCost), icon: "arrow.down", color: Color.orange)
                            }
                        }

                        // Per-model costs
                        if let models = costData["models"] as? [[String: Any]], !models.isEmpty {
                            Divider()
                            Text("Cost by Model")
                                .font(.subheadline.bold())

                            ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                                HStack {
                                    Text(model["model"] as? String ?? model["name"] as? String ?? "Unknown")
                                        .font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    if let cost = model["totalCost"] as? Double {
                                        Text(String(format: "$%.4f", cost))
                                            .font(.caption.bold())
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                if let error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.callout)
                    .foregroundStyle(Color.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
        }
        .navigationTitle("Usage & Cost")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ConnectionBadge(isConnected: gateway.isConnected)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh usage data")
            }
        }
        .task {
            await loadData()
        }
    }

    private func usageCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatNumber(_ value: Any?) -> String {
        if let num = value as? Int {
            if num >= 1_000_000 { return String(format: "%.1fM", Double(num) / 1_000_000) }
            if num >= 1_000 { return String(format: "%.1fK", Double(num) / 1_000) }
            return "\(num)"
        }
        if let num = value as? Double {
            if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000) }
            if num >= 1_000 { return String(format: "%.1fK", num / 1_000) }
            return String(format: "%.0f", num)
        }
        return "—"
    }

    private func loadData() async {
        isLoading = true
        error = nil

        if gateway.isConnected {
            do {
                let usage = try await gateway.usageStatus()
                usageData = usage.raw
            } catch {
                self.error = "Usage: \(error.localizedDescription)"
            }
            do {
                let cost = try await gateway.usageCost()
                costData = cost.raw
            } catch {
                // Cost endpoint may not be available, that's OK
                print("[Usage] Cost fetch failed: \(error)")
            }
        } else {
            // Fallback to CLI
            let result = await service.runCommand("openclaw usage status --json")
            if result.exitCode == 0, let data = result.output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                usageData = json
            }
        }

        isLoading = false
    }
}
