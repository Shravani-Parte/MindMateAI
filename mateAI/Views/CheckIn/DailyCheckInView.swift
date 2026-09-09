import SwiftUI
import SwiftData

struct DailyCheckInView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let existingEntry: DailyWellness?

    @State private var moodSlider: Double
    @State private var journalText: String
    @State private var liveSentiment: Double = 0

    init(existingEntry: DailyWellness?) {
        self.existingEntry = existingEntry
        _moodSlider = State(initialValue: existingEntry?.manualMoodScore ?? 0)
        _journalText = State(initialValue: existingEntry?.journalText ?? "")
    }

    private var band: String { Constants.band(for: liveSentiment) }

    var body: some View {
        NavigationStack {
            Form {
                Section("How are you feeling? (\(String(format: "%.1f", moodSlider)))") {
                    Slider(value: $moodSlider, in: -1...1, step: 0.1)
                    HStack {
                        Text("😞")
                        Spacer()
                        Text("😐")
                        Spacer()
                        Text("😊")
                    }
                }

                Section("Journal (optional)") {
                    TextEditor(text: $journalText)
                        .frame(minHeight: 120)
                        .onChange(of: journalText) { _, newValue in
                            liveSentiment = SentimentService.shared.score(for: newValue)
                        }
                    if !journalText.isEmpty {
                        HStack {
                            Circle().fill(colorForBand(band)).frame(width: 10, height: 10)
                            Text("Detected mood: \(band)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Save Check-In") { save() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Daily Check-In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func colorForBand(_ band: String) -> Color {
        switch band {
        case "Very Low": return .red
        case "Low": return .orange
        case "Neutral": return .gray
        case "High": return .green
        case "Very High": return .blue
        default: return .gray
        }
    }

    private func save() {
        let sentiment = SentimentService.shared.score(for: journalText)
        if let existing = existingEntry {
            existing.manualMoodScore = moodSlider
            existing.journalText = journalText
            existing.journalSentimentScore = sentiment
            existing.combinedScore = (moodSlider + sentiment) / 2.0
        } else {
            let entry = DailyWellness(
                manualMoodScore: moodSlider,
                journalText: journalText,
                journalSentimentScore: sentiment
            )
            context.insert(entry)
        }
        try? context.save()
        dismiss()
    }
}
