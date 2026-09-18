import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    let profile: UserProfile

    @Query(sort: \DailyWellness.date, order: .reverse) private var entries: [DailyWellness]
    @State private var showCheckIn = false

    private var sortedEntries: [DailyWellness] { TrendAnalyzer.sortedByDate(entries) }

    private var todayEntry: DailyWellness? {
        entries.first { Calendar.current.isDateInToday($0.date) }
    }

    /// Last 7 days in chronological (oldest → newest) order.
    private var last7Days: [DailyWellness] {
        Array(entries.prefix(7)).reversed()
    }

    /// The 7 days before `last7Days`, for week-over-week comparisons.
    private var previous7Days: [DailyWellness] {
        guard sortedEntries.count > 7 else { return [] }
        return Array(sortedEntries.suffix(14).prefix(7))
    }

    private var weekDelta: Double? {
        TrendAnalyzer.delta(between: last7Days, and: previous7Days)
    }

    /// The 2 most useful insights for the home screen.
    private var homeInsights: [TrendInsight] {
        Array(TrendInsights.make(for: sortedEntries).prefix(2))
    }

    private var streak: Int {
        var count = 0
        var day = Calendar.current.startOfDay(for: .now)
        let dates = Set(entries.map { Calendar.current.startOfDay(for: $0.date) })
        while dates.contains(day) {
            count += 1
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    private var todayBand: String {
        guard let todayEntry else { return "Neutral" }
        return Constants.band(for: todayEntry.combinedScore)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    moodCard

                    Button {
                        showCheckIn = true
                    } label: {
                        Label(
                            todayEntry == nil ? "Daily Check-In" : "Update Today's Check-In",
                            systemImage: "square.and.pencil"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .controlSize(.large)

                    if last7Days.count > 1 {
                        trendCard
                    }

                    if !homeInsights.isEmpty {
                        insightChips
                    }

                    streakRow
                }
                .padding()
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(profile: profile)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showCheckIn) {
                DailyCheckInView(existingEntry: todayEntry)
            }
        }
    }

    @ViewBuilder
    private var headerCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(greeting), \(profile.name.isEmpty ? "there" : profile.name) 👋")
                    .font(.title.bold())
                Text(todayEntry == nil
                     ? "Take a quiet moment to check in with yourself."
                     : "You're feeling \(todayBand.lowercased()) today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(.teal.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.teal.opacity(0.28), Color.mint.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    @ViewBuilder
    private var moodCard: some View {
        HStack(spacing: 16) {
            MoodGauge(score: todayEntry?.combinedScore ?? 0, size: 92)

            VStack(alignment: .leading, spacing: 3) {
                Text("Today's Mood")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let today = todayEntry {
                    Text(Constants.band(for: today.combinedScore))
                        .font(.title2.bold())
                    Text(String(format: "Score: %.2f", today.combinedScore))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No check-in yet")
                        .font(.title3.bold())
                    Text("Tap below to get started")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

        if let today = todayEntry, !today.journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                breakdownRow(label: "Mood slider", value: today.manualMoodScore ?? 0)
                breakdownRow(label: "From your journal", value: today.journalSentimentScore)

                HStack(spacing: 6) {
                    Image(systemName: sourceIcon(for: today.journalSentimentSource))
                    Text("Journal analyzed with \(today.journalSentimentSource)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("7-Day Trend").font(.headline)
                Spacer()
                if let weekDelta {
                    Label(
                        String(format: "%+.2f", weekDelta),
                        systemImage: weekDelta >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(weekDelta >= 0 ? Color.green : Color.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (weekDelta >= 0 ? Color.green : Color.red).opacity(0.12),
                        in: Capsule()
                    )
                }
            }

            MoodAreaChart(
                days: last7Days.map {
                    TrendDay(id: $0.date, date: $0.date, score: $0.combinedScore)
                },
                color: .teal,
                height: 180
            )

            HStack(spacing: 12) {
                Label(
                    "Avg: \(String(format: "%.2f", TrendAnalyzer.averageScore(of: last7Days) ?? 0))",
                    systemImage: "chart.bar.fill"
                )
                Spacer()
                Label(
                    "Best: \(Constants.band(for: TrendAnalyzer.extremes(of: last7Days).best?.combinedScore ?? 0))",
                    systemImage: "crown.fill"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var insightChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A bit of insight").font(.headline)
            ForEach(homeInsights) { insight in
                InsightRow(insight: insight)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var streakRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            Text("\(streak)-day check-in streak")
            Spacer()
            if streak > 0 {
                Text("Keep it up!")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.14), Color.yellow.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func sourceIcon(for rawSource: String) -> String {
        switch SentimentSource(rawValue: rawSource) {
        case .bert: return "brain.head.profile"
        case .ollama: return "server.rack"
        default: return "waveform.path.ecg"
        }
    }

    private func breakdownRow(label: String, value: Double) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.2f", value)).font(.caption.monospacedDigit())
        }
    }
}