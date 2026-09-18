import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query(sort: \DailyWellness.date) private var entries: [DailyWellness]

    private var sorted: [DailyWellness] { TrendAnalyzer.sortedByDate(entries) }
    private var latestScore: Double { sorted.last?.combinedScore ?? 0 }
    private var previousScore: Double? {
        sorted.count >= 2 ? sorted[sorted.count - 2].combinedScore : nil
    }
    private var vsYesterdayDelta: Double? {
        guard let previousScore else { return nil }
        return latestScore - previousScore
    }
    private var weeklyAverage: Double? {
        TrendAnalyzer.averageScore(of: Array(sorted.suffix(7)))
    }
    private var monthlyAverage: Double? {
        TrendAnalyzer.averageScore(of: Array(sorted.suffix(30)))
    }
    private var weekDelta: Double? {
        guard sorted.count >= 14 else { return nil }
        return TrendAnalyzer.delta(
            between: Array(sorted.suffix(7)),
            and: Array(sorted.suffix(14).prefix(7))
        )
    }
    private var direction: MoodTrendDirection { TrendAnalyzer.direction(of: sorted) }
    private var insights: [TrendInsight] { TrendInsights.make(for: sorted) }

    /// True when the most recent days all fall at/below the low-mood threshold.
    private var hasPersistentLowMood: Bool {
        let recent = Array(sorted.suffix(Constants.lowMoodStreakDaysForNudge))
        guard recent.count >= Constants.lowMoodStreakDaysForNudge else { return false }
        return recent.allSatisfy { $0.combinedScore <= Constants.lowMoodThreshold }
    }

    private var shouldShowNudge: Bool {
        hasPersistentLowMood
            || TrendAnalyzer.lowMoodStreak(of: sorted) >= Constants.lowMoodStreakDaysForNudge
            || (weekDelta ?? 0) <= Constants.lowMoodThreshold
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No Data Yet",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Complete a daily check-in to start seeing trends.")
                        )
                        .padding(.top, 60)
                    } else {
                        heroCard
                        overviewStats
                        moodTimelineCard
                        weeklyCard
                        weekdayCard
                        bandMixCard
                        insightsCard
                        if shouldShowNudge {
                            lowMoodNudge
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Trends")
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroCard: some View {
        HStack(spacing: 18) {
            MoodGauge(score: latestScore, size: 116, showsCaption: false)

            VStack(alignment: .leading, spacing: 6) {
                Text("Your mood now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(Constants.band(for: latestScore))
                    .font(.title.bold())
                    .foregroundStyle(Color.mood(latestScore))

                Text(String(format: "Score: %.2f", latestScore))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let delta = vsYesterdayDelta {
                    HStack(spacing: 4) {
                        Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                        Text("\(String(format: "%+.2f", delta)) vs yesterday")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(delta >= 0 ? .green : .red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (delta >= 0 ? Color.green : Color.red).opacity(0.12),
                        in: Capsule()
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.teal.opacity(0.24), Color.indigo.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    // MARK: - Stat cards

    private var overviewStats: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "7-Day Avg",
                value: weeklyAverage ?? 0,
                footnote: weeklyAverage.map { Constants.band(for: $0) } ?? "No data",
                symbol: "calendar"
            )

            StatCard(
                title: "30-Day Avg",
                value: monthlyAverage ?? 0,
                footnote: monthlyAverage.map { Constants.band(for: $0) } ?? "No data",
                symbol: "calendar.badge.clock"
            )

            StatCard(
                title: "Week Δ",
                value: weekDelta ?? 0,
                footnote: weekDelta == nil ? "Need 2 weeks" : "vs prior week",
                tint: (weekDelta ?? 0) >= 0 ? .green : .red,
                symbol: direction.symbol
            )
        }
    }

    // MARK: - Full mood timeline

    private var moodTimelineCard: some View {
        GlassCard {
            VStack(alignment: .leading) {
                HStack {
                    Text("Mood over time").font(.headline)
                    Spacer()
                    Label(direction.rawValue, systemImage: direction.symbol)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }

                MoodAreaChart(
                    days: sorted.map {
                        TrendDay(id: $0.date, date: $0.date, score: $0.combinedScore)
                    },
                    color: .teal,
                    height: 220
                )

                HStack {
                    Text("Negative")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Neutral")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Positive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Week by week

    @ViewBuilder
    private var weeklyCard: some View {
        let weeks = TrendAnalyzer.weeklyAverages(of: sorted).enumerated().map { index, item in
            WeekMood(id: index, label: item.label, score: item.score ?? 0)
        }

        GlassCard {
            VStack(alignment: .leading) {
                Text("Week by week").font(.headline)
                Text("Average mood per 7-day stretch")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if weeks.isEmpty {
                    Text("Not enough data for a weekly view yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    WeeklyMoodChart(weeks: weeks)
                }
            }
        }
    }

    // MARK: - Typical weekday

    private var weekdayCard: some View {
        GlassCard {
            VStack(alignment: .leading) {
                Text("Your typical week").font(.headline)
                Text("Average mood by weekday — gaps mean no check-in that day")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                WeekdayMoodChart(
                    days: TrendAnalyzer.weekdayAverages(of: sorted).map {
                        WeekdayMood(id: $0.weekday, label: $0.label, score: $0.score)
                    }
                )
            }
        }
    }

    // MARK: - Band mix

    private var bandMixCard: some View {
        GlassCard {
            VStack(alignment: .leading) {
                Text("Mood mix").font(.headline)
                Text("Where your check-ins land on the mood scale")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                BandDistributionView(bands: TrendAnalyzer.bandDistribution(of: sorted))
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Insights

    @ViewBuilder
    private var insightsCard: some View {
        if !insights.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Insights").font(.headline)

                    ForEach(insights) { insight in
                        InsightRow(insight: insight)
                        if insight.id != insights.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Nudge

    @ViewBuilder
    private var lowMoodNudge: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Text("Your mood trend has been low lately. Consider reaching out to a professional or trusted person — you don't have to carry it alone.")
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }
}