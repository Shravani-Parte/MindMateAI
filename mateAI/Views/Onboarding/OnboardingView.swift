import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var occupation = ""
    @State private var workHours = ""
    @State private var stressors = ""
    @State private var sleepHours: Double = 7
    @State private var exerciseFrequency = ""
    @State private var supportSystem = ""
    @State private var goals = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("About You") {
                    TextField("Name", text: $name)
                    TextField("Occupation", text: $occupation)
                    TextField("Typical work hours (e.g. 9–6)", text: $workHours)
                }

                Section("Wellness Context") {
                    TextField("What stresses you most lately?", text: $stressors, axis: .vertical)
                    Stepper(
                        "Sleep: \(sleepHours, specifier: "%.1f") hrs/night",
                        value: $sleepHours, in: 3...12, step: 0.5
                    )
                    TextField("Exercise frequency (e.g. 3x/week)", text: $exerciseFrequency)
                    TextField("Who's your support system?", text: $supportSystem)
                    TextField("A wellness goal right now", text: $goals, axis: .vertical)
                }

                Section {
                    Text("MindMate is a private, on-device wellness companion. It is not a substitute for licensed medical or mental health care. In an emergency, contact local emergency services immediately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Get Started") { saveProfile() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Welcome to MindMate")
        }
    }

    private func saveProfile() {
        let profile = UserProfile(
            name: name,
            occupation: occupation,
            typicalWorkHours: workHours,
            stressors: stressors,
            sleepHours: sleepHours,
            exerciseFrequency: exerciseFrequency,
            supportSystem: supportSystem,
            goals: goals,
            hasCompletedOnboarding: true
        )
        context.insert(profile)
        try? context.save()
    }
}
