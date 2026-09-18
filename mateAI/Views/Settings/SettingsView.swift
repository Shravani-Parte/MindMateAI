import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @State private var remindersEnabled = UserDefaults.standard.bool(forKey: Keys.remindersEnabled)
    @State private var reminderTime: Date = {
        if let stored = UserDefaults.standard.object(forKey: Keys.reminderTime) as? Date {
            return stored
        }
        return Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
    }()
    @State private var showDeleteConfirm = false

    @State private var ollamaEnabled = OllamaSettings.shared.isEnabled
    @State private var ollamaHost = OllamaSettings.shared.host
    @State private var ollamaModel = OllamaSettings.shared.model
    @State private var ollamaBertEnabled = OllamaSettings.shared.bertEnabled
    @State private var ollamaBertModel = OllamaSettings.shared.bertModel
    @State private var isTestingConnection = false
    @State private var connectionStatus: String?
    @State private var connectionSucceeded = false
    @State private var lastBackend = CounselorService.shared.lastUsedBackend

    private enum Keys {
        static let remindersEnabled = "reminders.enabled"
        static let reminderTime = "reminders.time"
        static let notificationID = "mindmate.dailyCheckIn"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    LabeledContent("Name", value: profile.name)
                    if !profile.occupation.isEmpty {
                        LabeledContent("Occupation", value: profile.occupation)
                    }
                }

                Section {
                    Toggle("Daily check-in reminder", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { _, _ in persistReminderSettings() }
                    if remindersEnabled {
                        DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: reminderTime) { _, _ in persistReminderSettings() }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("MindMate sends one local notification a day to nudge your check-in. Nothing is sent to a server.")
                }

                Section {
                    HStack {
                        Text("Active chat engine")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(lastBackend == .template ? Color.orange : Color.green)
                                .frame(width: 8, height: 8)
                            Text(lastBackend.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(lastBackend.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Priority: Ollama (if enabled & reachable) → Apple on-device model → Bundled Llama (MLX) → Supportive templates.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Journal sentiment reads the meaning of what you write — via a dedicated BERT classifier when available, otherwise the Ollama chat model or Apple's on-device NaturalLanguage model — not just the mood slider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("AI Engine")
                }

                Section {
                    Toggle("Use Ollama for chat & sentiment", isOn: $ollamaEnabled)
                        .onChange(of: ollamaEnabled) { _, newValue in
                            OllamaSettings.shared.isEnabled = newValue
                            connectionStatus = nil
                            if newValue { Task { await refreshOllamaStatus() } }
                        }

                    TextField("Server URL", text: $ollamaHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: ollamaHost) { _, newValue in
                            OllamaSettings.shared.host = newValue
                            connectionStatus = nil
                        }

                    TextField("Model", text: $ollamaModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: ollamaModel) { _, newValue in
                            OllamaSettings.shared.model = newValue
                            connectionStatus = nil
                        }

                    Button {
                        Task { await testOllamaConnection() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if isTestingConnection {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isTestingConnection)

                    if let connectionStatus {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundStyle(connectionSucceeded ? .green : .red)
                    }

                    Divider()

                    Toggle("Prefer BERT for journal sentiment", isOn: $ollamaBertEnabled)
                        .onChange(of: ollamaBertEnabled) { _, newValue in
                            OllamaSettings.shared.bertEnabled = newValue
                        }

                    TextField("BERT sentiment model", text: $ollamaBertModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: ollamaBertModel) { _, newValue in
                            OllamaSettings.shared.bertModel = newValue
                        }

                    if ollamaBertEnabled {
                        Text("BERT is a dedicated sentiment classifier (not a chat model), so journal text is scored like an ML sentiment model — typically faster and more consistent than asking a chat model to judge. Pull it once with `ollama pull \(ollamaBertModel)`.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Ollama (Local Gemma Model)")
                } footer: {
                    Text("On the machine that runs the model: install Ollama, run `ollama pull \(ollamaModel)`, then `ollama serve`. The Simulator reaches 127.0.0.1 directly; a physical device needs your Mac's LAN IP. Everything stays on your local network.")
                }

                Section("Privacy") {
                    NavigationLink("Crisis Resources") {
                        CrisisResourcesView()
                    }
                    Text(
                        ollamaEnabled
                        ? "Your data stays on this device except when Ollama is enabled above, which sends chat messages and journal text to the local server you configured — never to the public internet."
                        : "All data stays on this device. Nothing is sent to a server."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button("Delete All My Data", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }

                Section {
                    Text("MindMate is not a substitute for professional mental health care. If you are in crisis, contact local emergency services.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                LLMService.shared.refreshAvailability()
                lastBackend = CounselorService.shared.lastUsedBackend
            }
            .task {
                await refreshOllamaStatus()
            }
            .confirmationDialog(
                "Delete all data? This cannot be undone.",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) { deleteAll() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Reminders

    private func persistReminderSettings() {
        UserDefaults.standard.set(remindersEnabled, forKey: Keys.remindersEnabled)
        UserDefaults.standard.set(reminderTime, forKey: Keys.reminderTime)
        scheduleReminder()
    }

    private func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Keys.notificationID])
        guard remindersEnabled else { return }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                Task { @MainActor in
                    remindersEnabled = false
                    UserDefaults.standard.set(false, forKey: Keys.remindersEnabled)
                }
                return
            }
            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            let content = UNMutableNotificationContent()
            content.title = "Time for your MindMate check-in"
            content.body = "How are you feeling today? A minute of journaling can make a big difference."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: Keys.notificationID, content: content, trigger: trigger)
            Task {
                try? await center.add(request)
            }
        }
    }

    // MARK: - Ollama

    private func testOllamaConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }

        let result = await OllamaProvider.checkAvailability()
        if result.isFullyAvailable {
            connectionSucceeded = true
            connectionStatus = "✅ Connected — \(ollamaModel) is available."
        } else if result.isReachable {
            connectionSucceeded = false
            connectionStatus = "⚠️ Server reached, but \(ollamaModel) isn't pulled yet. Run `ollama pull \(ollamaModel)`."
        } else {
            connectionSucceeded = false
            connectionStatus = "⚠️ Couldn't reach Ollama at \(ollamaHost). Is `ollama serve` running?"
        }
    }

    /// Quiet background check so the screen reflects reality without tapping "Test".
    private func refreshOllamaStatus() async {
        guard ollamaEnabled, connectionStatus == nil else { return }
        let result = await OllamaProvider.checkAvailability()
        if result.isFullyAvailable {
            connectionSucceeded = true
            connectionStatus = "✅ Connected — \(ollamaModel) is available."
        } else if result.isReachable {
            connectionSucceeded = false
            connectionStatus = "⚠️ Server reached, but \(ollamaModel) isn't pulled yet."
        } else {
            connectionSucceeded = false
            connectionStatus = "⚠️ Not reachable at \(ollamaHost). Chat falls back to the on-device engine."
        }
    }

    private func deleteAll() {
        try? context.delete(model: DailyWellness.self)
        try? context.delete(model: ChatMessage.self)
        try? context.delete(model: ChatSession.self)
        try? context.delete(model: CrisisEvent.self)
        try? context.delete(model: UserProfile.self)
        try? context.save()
        LLMService.shared.resetSession()
    }
}