import SwiftUI
import SwiftData

struct SettingsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @State private var remindersEnabled = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    Text(profile.name)
                    Text(profile.occupation).foregroundStyle(.secondary)
                }

                Section("Reminders") {
                    Toggle("Daily check-in reminder", isOn: $remindersEnabled)
                }

                Section("Privacy") {
                    NavigationLink("Crisis Resources") {
                        CrisisResourcesView()
                    }
                    Text("All data stays on this device. Nothing is sent to a server.")
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

    private func deleteAll() {
        try? context.delete(model: DailyWellness.self)
        try? context.delete(model: ChatMessage.self)
        try? context.delete(model: ChatSession.self)
        try? context.delete(model: CrisisEvent.self)
        try? context.delete(model: UserProfile.self)
        try? context.save()
    }
}
