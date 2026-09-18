import SwiftUI
import SwiftData

struct DailyCheckInView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let existingEntry: DailyWellness?

    @State private var moodSlider: Double
    @State private var journalText: String
    @State private var liveSentiment: Double = 0
    @State private var sentimentSource: SentimentSource = .onDevice
    @State private var isAnalyzing = false
    @State private var isSaving = false

    init(existingEntry: DailyWellness?) {
        self.existingEntry = existingEntry
        _moodSlider = State(initialValue: existingEntry?.manualMoodScore ?? 0)
        _journalText = State(initialValue: existingEntry?.journalText ?? "")
        _liveSentiment = State(initialValue: existingEntry?.journalSentimentScore ?? 0)
        _sentimentSource = State(
            initialValue: existingEntry.flatMap { SentimentSource(rawValue: $0.journalSentimentSource) } ?? .onDevice
        )
    }

    private var band: String { Constants.band(for: liveSentiment) }
    private var hasJournalText: Bool {
        !journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var combinedPreview: Double {
        DailyWellness.computeCombined(
            manualMoodScore: moodSlider,
            journalSentimentScore: liveSentiment,
            journalText: journalText
        )
    }
    private var sliderTint: Color { Color.mood(moodSlider) }

    var body: some View {
        NavigationStack {
            Form {
                Section("How are you feeling? (\(String(format: "%.1f", moodSlider)))") {
                    Slider(value: $moodSlider, in: -1...1, step: 0.1)
                        .tint(sliderTint)
                    HStack {
                        Label("Low", systemImage: "cloud.rain.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("😐")
                        Spacer()
                        Label("High", systemImage: "sun.max.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextEditor(text: $journalText)
                        .frame(minHeight: 120)
                    if isAnalyzing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Analyzing what you wrote…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if hasJournalText {
                        HStack(spacing: 8) {
                            Circle().fill(Color.mood(liveSentiment)).frame(width: 10, height: 10)
                            Text("Detected mood from your description: \(band)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Label(sentimentSource.rawValue, systemImage: sourceIcon)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                            .labelStyle(.titleAndIcon)
                    }
                } header: {
                    Text("Journal (optional)")
                } footer: {
                    Text("Your words carry the most weight: the description drives your combined score (~70%), so a few honest sentences here genuinely move your mood even if the slider stays neutral.")
                }
                .task(id: journalText) {
                    await analyzeJournalText()
                }

                if hasJournalText {
                    Section("Mood Breakdown") {
                        HStack(spacing: 16) {
                            MoodGauge(score: combinedPreview, size: 76, showsCaption: false)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Combined score")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f", combinedPreview))
                                    .font(.title3.bold().monospacedDigit())
                                Text(Constants.band(for: combinedPreview))
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.mood(combinedPreview))
                            }
                            Spacer(minLength: 0)
                        }
                        breakdownRow(label: "Mood slider", value: moodSlider)
                        breakdownRow(label: "From your description", value: liveSentiment)
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Text("Save Check-In")
                            if isSaving {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isSaving || isAnalyzing)
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

    /// Debounced (300ms) LLM-or-on-device analysis of the journal *description* text,
    /// triggered automatically as the user types via `.task(id: journalText)`, which
    /// SwiftUI cancels and restarts whenever `journalText` changes.
    private func analyzeJournalText() async {
        guard hasJournalText else {
            liveSentiment = 0
            sentimentSource = .onDevice
            isAnalyzing = false
            return
        }
        // Skip a redundant re-analysis when simply re-opening an entry whose text hasn't
        // changed since it was last saved.
        if let existingEntry, journalText == existingEntry.journalText {
            return
        }
        isAnalyzing = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }

        let result = await SentimentService.shared.deepScore(for: journalText)
        guard !Task.isCancelled else { return }

        liveSentiment = result.score
        sentimentSource = result.source
        isAnalyzing = false
    }

    private var sourceIcon: String {
        switch sentimentSource {
        case .bert: return "brain.head.profile"
        case .ollama: return "server.rack"
        case .onDevice: return "waveform.path.ecg"
        }
    }

    private func breakdownRow(label: String, value: Double) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(String(format: "%.2f", value))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        isSaving = true
        Task {
            // Use whatever the live analysis already found for this exact text when
            // available; otherwise (e.g. saving instantly after pasting) run it fresh so
            // the saved entry always reflects the description, not a stale/zero value.
            let result: (score: Double, source: SentimentSource)
            if hasJournalText, !isAnalyzing {
                result = (liveSentiment, sentimentSource)
            } else {
                result = await SentimentService.shared.deepScore(for: journalText)
            }

            if let existing = existingEntry {
                existing.updateScores(
                    manualMood: moodSlider,
                    journalText: journalText,
                    journalSentiment: result.score,
                    journalSentimentSource: result.source.rawValue
                )
            } else {
                let entry = DailyWellness(
                    manualMoodScore: moodSlider,
                    journalText: journalText,
                    journalSentimentScore: result.score,
                    journalSentimentSource: result.source.rawValue
                )
                context.insert(entry)
            }
            try? context.save()
            isSaving = false
            dismiss()
        }
    }
}
