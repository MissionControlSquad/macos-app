import SwiftUI

struct CronView: View {
    @Bindable var service: OpenClawService
    @State private var cronOutput = ""
    @State private var isLoading = false
    @State private var showAddJob = false

    // Add job form
    @State private var newJobName = ""
    @State private var newJobSchedule = ""
    @State private var newJobMessage = ""
    @State private var actionResult = ""
    @State private var actionIsError = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Automation")
                    .font(.title.bold())
                Spacer()
                Button {
                    showAddJob = true
                } label: {
                    Label("Add Job", systemImage: "plus")
                }
                .buttonStyle(.bordered)

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
                    // Schedule presets
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Common Schedules")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 8) {
                            schedulePreset("Every minute", "* * * * *")
                            schedulePreset("Every 5 min", "*/5 * * * *")
                            schedulePreset("Every hour", "0 * * * *")
                            schedulePreset("Every day 9AM", "0 9 * * *")
                            schedulePreset("Every Monday", "0 9 * * 1")
                            schedulePreset("Every 1st", "0 0 1 * *")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Current jobs output
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scheduled Jobs")
                            .font(.headline)

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if cronOutput.isEmpty {
                            Text("No cron jobs configured. Add one to get started.")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        } else {
                            Text(cronOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if !actionResult.isEmpty {
                        Text(actionResult)
                            .font(.callout)
                            .foregroundStyle(actionIsError ? .red : .green)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: $showAddJob) {
            addJobSheet
        }
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
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Job Sheet

    private var addJobSheet: some View {
        VStack(spacing: 16) {
            Text("Add Cron Job")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. daily-summary", text: $newJobName)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 400)

            VStack(alignment: .leading, spacing: 8) {
                Text("Schedule (cron expression)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. 0 9 * * *", text: $newJobSchedule)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: 400)

            VStack(alignment: .leading, spacing: 8) {
                Text("Message to send")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $newJobMessage)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                    .border(Color(.separatorColor), width: 1)
            }
            .frame(width: 400)

            HStack {
                Button("Cancel") {
                    showAddJob = false
                    clearForm()
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    Task {
                        let result = await service.addCronJob(
                            name: newJobName,
                            schedule: newJobSchedule,
                            message: newJobMessage
                        )
                        if result.exitCode == 0 {
                            actionResult = "Cron job '\(newJobName)' created"
                            actionIsError = false
                            showAddJob = false
                            clearForm()
                            await refresh()
                        } else {
                            actionResult = result.output
                            actionIsError = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newJobName.isEmpty || newJobSchedule.isEmpty || newJobMessage.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    // MARK: - Helpers

    private func refresh() async {
        isLoading = true
        let result = await service.fetchCronJobs()
        cronOutput = result.output
        isLoading = false
    }

    private func clearForm() {
        newJobName = ""
        newJobSchedule = ""
        newJobMessage = ""
    }
}
