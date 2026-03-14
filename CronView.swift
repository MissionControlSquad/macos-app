import SwiftUI

struct CronView: View {
    @Bindable var service: OpenClawService
    @Bindable var gateway: GatewayWebSocket
    @State private var cronJobs: [[String: Any]] = []
    @State private var cronRuns: [[String: Any]] = []
    @State private var isLoading = false
    @State private var showAddJob = false
    @State private var selectedTab: CronTab = .jobs

    // Add job form
    @State private var newJobName = ""
    @State private var newJobSchedule = ""
    @State private var newJobMessage = ""
    @State private var toast = ToastState()
    @State private var jobToDelete: String?
    @State private var showDeleteConfirm = false

    enum CronTab: String, CaseIterable {
        case jobs = "Scheduled Jobs"
        case history = "Run History"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tabs
            Picker("", selection: $selectedTab) {
                ForEach(CronTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Schedule presets
                    if selectedTab == .jobs {
                        GroupBox("Common Schedules") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 8) {
                                schedulePreset("Every minute", "* * * * *")
                                schedulePreset("Every 5 min", "*/5 * * * *")
                                schedulePreset("Every hour", "0 * * * *")
                                schedulePreset("Every day 9AM", "0 9 * * *")
                                schedulePreset("Every Monday", "0 9 * * 1")
                                schedulePreset("Every 1st", "0 0 1 * *")
                            }
                        }

                        // Current jobs
                        GroupBox("Scheduled Jobs") {
                            if isLoading {
                                LoadingStateView(message: "Loading jobs...", compact: true)
                            } else if cronJobs.isEmpty {
                                Text("No cron jobs configured. Add one to get started.")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            } else {
                                ForEach(Array(cronJobs.enumerated()), id: \.offset) { _, job in
                                    cronJobRow(job)
                                }
                            }
                        }
                    }

                    // Run history tab
                    if selectedTab == .history {
                        GroupBox {
                            if isLoading {
                                LoadingStateView(message: "Loading history...", compact: true)
                            } else if cronRuns.isEmpty {
                                Text("No cron run history available.")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            } else {
                                ForEach(Array(cronRuns.enumerated()), id: \.offset) { _, run in
                                    cronRunRow(run)
                                }
                            }
                        } label: {
                            HStack {
                                Text("Run History")
                                Spacer()
                                Text("\(cronRuns.count) runs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    ToastBanner(toast: toast)
                }
                .padding()
            }
        }
        .navigationTitle("Automation")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ConnectionBadge(isConnected: gateway.isConnected)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddJob = true
                } label: {
                    Label("Add Job", systemImage: "plus")
                }
                .help("Add a new scheduled job")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh jobs and run history")
            }
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: $showAddJob) {
            addJobSheet
        }
        .confirmationDialog(
            "Remove Job",
            isPresented: $showDeleteConfirm,
            presenting: jobToDelete
        ) { name in
            Button("Remove \"\(name)\"", role: .destructive) {
                performRemoveJob(name: name)
            }
            Button("Cancel", role: .cancel) {}
        } message: { name in
            Text("This will permanently remove the scheduled job \"\(name)\". This action cannot be undone.")
        }
    }

    // MARK: - Cron Job Row

    private func cronJobRow(_ job: [String: Any]) -> some View {
        let name = job["name"] as? String ?? "unnamed"
        let schedule = job["schedule"] as? String ?? ""
        let message = job["message"] as? String ?? ""
        let enabled = job["enabled"] as? Bool ?? true

        return HStack(spacing: 12) {
            Image(systemName: enabled ? "clock.arrow.2.circlepath" : "clock.badge.xmark")
                .font(.title3)
                .foregroundStyle(enabled ? Color.accentColor : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.callout.bold())
                    if !enabled {
                        StatusBadge(label: "Disabled", color: Color.secondary)
                    }
                }
                Text(schedule)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    runJob(name: name)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Run now")

                Button {
                    jobToDelete = name
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
                .help("Remove job")
            }
        }
        .padding(6)
    }

    // MARK: - Cron Run Row

    private func cronRunRow(_ run: [String: Any]) -> some View {
        let name = run["name"] as? String ?? run["jobName"] as? String ?? "?"
        let status = run["status"] as? String ?? run["result"] as? String ?? "unknown"
        let startedAt = run["startedAt"] as? Double ?? run["timestamp"] as? Double
        let duration = run["durationMs"] as? Double ?? run["duration"] as? Double

        return HStack(spacing: 12) {
            Image(systemName: runStatusIcon(status))
                .font(.callout)
                .foregroundStyle(runStatusColor(status))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.callout.bold())
                    Text(status)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(runStatusColor(status).opacity(0.15))
                        .foregroundStyle(runStatusColor(status))
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    if let ts = startedAt {
                        Text(formattedDate(ts))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let dur = duration {
                        Text(String(format: "%.1fs", dur / 1000.0))
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
            }

            Spacer()
        }
        .padding(4)
    }

    // MARK: - Schedule Preset

    private func schedulePreset(_ label: String, _ cron: String) -> some View {
        Button {
            newJobSchedule = cron
            showAddJob = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout)
                Text(cron)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Job Sheet

    private var addJobSheet: some View {
        VStack(spacing: 0) {
            Form {
                Section("Job Details") {
                    TextField("Name", text: $newJobName, prompt: Text("e.g. daily-summary"))
                    TextField("Schedule (cron)", text: $newJobSchedule, prompt: Text("e.g. 0 9 * * *"))
                        .font(.system(.body, design: .monospaced))
                }

                Section("Message") {
                    TextEditor(text: $newJobMessage)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    showAddJob = false
                    clearForm()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create Job") {
                    Task {
                        await addJob()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newJobName.isEmpty || newJobSchedule.isEmpty || newJobMessage.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 340)
    }

    // MARK: - Actions

    private func addJob() async {
        let name = newJobName
        if gateway.isConnected {
            do {
                _ = try await gateway.cronAdd(name: newJobName, schedule: newJobSchedule, message: newJobMessage)
                showAddJob = false
                clearForm()
                toast.show("Cron job '\(name)' created")
                await refresh()
            } catch {
                toast.show(error.localizedDescription, isError: true)
            }
        } else {
            let result = await service.addCronJob(
                name: newJobName,
                schedule: newJobSchedule,
                message: newJobMessage
            )
            if result.exitCode == 0 {
                showAddJob = false
                clearForm()
                toast.show("Cron job '\(name)' created")
                await refresh()
            } else {
                toast.show(result.output, isError: true)
            }
        }
    }

    private func performRemoveJob(name: String) {
        Task {
            if gateway.isConnected {
                do {
                    _ = try await gateway.cronRemove(name: name)
                    toast.show("Job '\(name)' removed")
                    await refresh()
                } catch {
                    toast.show(error.localizedDescription, isError: true)
                }
            } else {
                let result = await service.runCommand("openclaw cron remove \(name)")
                toast.show(
                    result.exitCode == 0 ? "Job '\(name)' removed" : result.output,
                    isError: result.exitCode != 0
                )
                await refresh()
            }
        }
    }

    private func runJob(name: String) {
        Task {
            if gateway.isConnected {
                do {
                    _ = try await gateway.cronRun(name: name)
                    toast.show("Job '\(name)' triggered")
                } catch {
                    toast.show(error.localizedDescription, isError: true)
                }
            } else {
                let result = await service.runCommand("openclaw cron run \(name)")
                toast.show(
                    result.exitCode == 0 ? "Job '\(name)' triggered" : result.output,
                    isError: result.exitCode != 0
                )
            }
        }
    }

    // MARK: - Helpers

    private func refresh() async {
        isLoading = true

        if gateway.isConnected {
            // Load jobs via gateway
            do {
                let result = try await gateway.cronList()
                if let jobs = result["jobs"] as? [[String: Any]] {
                    cronJobs = jobs
                } else if let jobs = result["items"] as? [[String: Any]] {
                    cronJobs = jobs
                }
            } catch {
                toast.show("Failed to load jobs: \(error.localizedDescription)", isError: true)
            }

            // Load run history via gateway
            do {
                let result = try await gateway.cronRuns()
                if let runs = result["runs"] as? [[String: Any]] {
                    cronRuns = runs
                } else if let runs = result["items"] as? [[String: Any]] {
                    cronRuns = runs
                }
            } catch {
                // Run history may not be available, that's OK
                print("[Cron] Failed to load run history: \(error)")
            }
        } else {
            // Fallback to CLI
            let result = await service.fetchCronJobs()
            // Parse CLI output into structured data if possible
            if let data = result.output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let jobs = json["jobs"] as? [[String: Any]] {
                cronJobs = jobs
            }
        }

        isLoading = false
    }

    private func clearForm() {
        newJobName = ""
        newJobSchedule = ""
        newJobMessage = ""
    }

    private func runStatusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "success", "completed", "ok": return "checkmark.circle.fill"
        case "failed", "error": return "xmark.circle.fill"
        case "running", "in_progress": return "play.circle.fill"
        case "skipped": return "forward.fill"
        default: return "circle"
        }
    }

    private func runStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "success", "completed", "ok": return Color.green
        case "failed", "error": return Color.red
        case "running", "in_progress": return Color.accentColor
        case "skipped": return Color.secondary
        default: return Color.secondary
        }
    }

    private func formattedDate(_ ms: Double) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
