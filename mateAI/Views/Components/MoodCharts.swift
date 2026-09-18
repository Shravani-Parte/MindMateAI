import SwiftUI
import Charts

// MARK: - Shared mood styling

extension Color {
    /// Color used for a sentiment score's band (red → orange → gray → green → blue).
    static func mood(_ score: Double) -> Color {
        band(Constants.band(for: score))
    }

    /// Color used for a band name ("Very Low" ... "Very High").
    static func band(_ name: String) -> Color {
        switch name {
        case "Very Low": return .red
        case "Low": return .orange
        case "High": return .green
        case "Very High": return .blue
        default: return .gray
        }
    }
}

/// Emoji shown for a sentiment score across Home, Trends, and Check-in.
enum MoodEmoji {
    static func forScore(_ score: Double) -> String {
        switch Constants.band(for: score) {
        case "Very Low": return "😞"
        case "Low": return "😕"
        case "Neutral": return "😐"
        case "High": return "🙂"
        default: return "😄"
        }
    }
}

// MARK: - Containers

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Mood gauge

/// A circular progress gauge that sweeps the readable arc for a score in [-1, 1].
/// Used as the hero visual for "your mood right now".
struct MoodGauge: View {
    let score: Double
    var size: CGFloat = 96
    var lineWidth: CGFloat = 11
    var showsCaption = true

    private var progress: Double { (score + 1) / 2 }
    private var band: String { Constants.band(for: score) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .teal, .blue, .purple],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: progress)

            VStack(spacing: 2) {
                Text(MoodEmoji.forScore(score))
                    .font(.system(size: size * 0.3))
                if showsCaption {
                    Text(band)
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mood: \(band)")
    }
}

// MARK: - Mood line/area chart

struct TrendDay: Identifiable {
    let id: Date
    let date: Date
    let score: Double
}

/// Gradient-filled area + line + point diagram for a mood series over dates.
struct MoodAreaChart: View {
    let days: [TrendDay]
    var color: Color = .teal
    var height: CGFloat = 180
    var showsPoints = true

    var body: some View {
        Chart(days) { day in
            AreaMark(
                x: .value("Date", day.date, unit: .day),
                y: .value("Mood", day.score)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.35), color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", day.date, unit: .day),
                y: .value("Mood", day.score)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

            if showsPoints {
                PointMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Mood", day.score)
                )
                .foregroundStyle(color)
                .symbolSize(28)
            }

            RuleMark(y: .value("Neutral", 0))
                .foregroundStyle(.gray.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: -1...1)
        .frame(height: height)
    }
}

// MARK: - Weekday pattern

struct WeekdayMood: Identifiable {
    let id: Int
    let label: String
    let score: Double?
}

struct WeekdayMoodChart: View {
    let days: [WeekdayMood]

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Day", day.label),
                y: .value("Mood", day.score ?? 0)
            )
            .foregroundStyle(day.score.map { Color.mood($0) } ?? Color(.systemGray3).opacity(0.5))
            .cornerRadius(5)
        }
        .chartYScale(domain: -1...1)
        .frame(height: 140)
    }
}

// MARK: - Week-by-week comparison

struct WeekMood: Identifiable {
    let id: Int
    let label: String
    let score: Double
}

struct WeeklyMoodChart: View {
    let weeks: [WeekMood]

    var body: some View {
        Chart(weeks) { week in
            BarMark(
                x: .value("Week", week.label),
                y: .value("Mood", week.score)
            )
            .foregroundStyle(Color.mood(week.score))
            .cornerRadius(5)

            RuleMark(y: .value("Neutral", 0))
                .foregroundStyle(.gray.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: -1...1)
        .frame(height: 150)
    }
}

// MARK: - Band distribution

/// Horizontal "how many check-ins per band" bars — instant visual of the mood mix.
struct BandDistributionView: View {
    let bands: [MoodBandCount]

    private var maxCount: Int {
        max(bands.map(\.count).max() ?? 1, 1)
    }

    private var total: Int {
        bands.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(bands) { item in
                HStack(spacing: 10) {
                    Text(item.band)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(Color.band(item.band))
                                .frame(width: max(geo.size.width * CGFloat(item.count) / CGFloat(maxCount), item.count > 0 ? 8 : 0))
                        }
                    }
                    .frame(height: 10)

                    Text("\(item.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }
            }

            HStack {
                Text("\(total) check-ins")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Stat card

struct StatCard: View {
    let title: String
    let value: Double
    let footnote: String
    var tint: Color = .primary
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol ?? "chart.bar.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(format: symbolIsDelta ? "%+.2f" : "%.2f", value))
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(tint)

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var symbolIsDelta: Bool { symbol == "arrow.up.right" || symbol == "arrow.down.right" || symbol == "arrow.right" }
}

// MARK: - Insights

struct TrendInsight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let tint: Color
}

enum TrendInsights {
    /// Builds a short, human list of observations about the user's mood history. Empty
    /// when there isn't enough data. Order matters — the most useful insight stays first.
    static func make(for entries: [DailyWellness]) -> [TrendInsight] {
        let sorted = TrendAnalyzer.sortedByDate(entries)
        guard !sorted.isEmpty else { return [] }
        var insights: [TrendInsight] = []

        // 1) Week-over-week movement.
        if sorted.count >= 14 {
            let recent = Array(sorted.suffix(7))
            let previous = Array(sorted.suffix(14).prefix(7))
            if let delta = TrendAnalyzer.delta(between: recent, and: previous) {
                if delta >= 0.2 {
                    insights.append(TrendInsight(
                        icon: "arrow.up.right.circle.fill",
                        title: "This week beats last week",
                        detail: "Your average is up \(String(format: "%.2f", delta)) points week over week. Nice momentum!",
                        tint: .green
                    ))
                } else if delta <= -0.2 {
                    insights.append(TrendInsight(
                        icon: "arrow.down.right.circle.fill",
                        title: "This week is harder than last",
                        detail: "Your average dropped \(String(format: "%.2f", abs(delta))) points. Small steps still count.",
                        tint: .orange
                    ))
                }
            }
        }

        // 2) Weekday pattern (best & worst day of the week).
        if sorted.count >= 3 {
            let weekdayAverages = TrendAnalyzer.weekdayAverages(of: sorted)
            let scored = weekdayAverages.compactMap { weekday -> (label: String, score: Double)? in
                weekday.score.map { (weekday.label, $0) }
            }
            if scored.count >= 2 {
                if let best = scored.max(by: { $0.score < $1.score }),
                   let worst = scored.min(by: { $0.score < $1.score }),
                   best.score - worst.score >= 0.4 {
                    insights.append(TrendInsight(
                        icon: "calendar",
                        title: "\(best.label) is your brightest day",
                        detail: "Your mood tends to peak on \(best.label) and dip on \(worst.label). Plan something gentle for \(worst.label).",
                        tint: .blue
                    ))
                }
            }
        }

        // 3) Streaks.
        let rising = TrendAnalyzer.risingStreak(of: sorted)
        let declining = TrendAnalyzer.lowMoodStreak(of: sorted)
        if rising >= 3 {
            insights.append(TrendInsight(
                icon: "flame.fill",
                title: "\(rising)-day upswing",
                detail: "You've felt good for \(rising) days in a row. Keep leaning into what's working.",
                tint: .orange
            ))
        } else if declining >= 3 {
            insights.append(TrendInsight(
                icon: "hand.raised.fill",
                title: "\(declining)-day low stretch",
                detail: "A few hard days in a row. Reaching out to a trusted person can help buffer them.",
                tint: .red
            ))
        }

        // 4) Overall direction.
        if sorted.count >= 14 {
            switch TrendAnalyzer.direction(of: sorted) {
            case .up:
                insights.append(TrendInsight(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Overall trajectory: improving",
                    detail: "Your long-term mood is trending upward across \(sorted.count) check-ins.",
                    tint: .green
                ))
            case .down:
                insights.append(TrendInsight(
                    icon: "chart.line.downtrend.xyaxis",
                    title: "Overall trajectory: declining",
                    detail: "Your long-term mood is trending down across \(sorted.count) check-ins. Consider extra support.",
                    tint: .orange
                ))
            case .flat:
                break
            }
        }

        // 5) Consistency.
        let nonNeutral = meaningfulScores(sorted)
        if nonNeutral.count >= 3 {
            let positive = nonNeutral.filter { $0 >= 0 }
            let pct = Int((Double(positive.count) / Double(nonNeutral.count)) * 100)
            if pct >= 75 {
                insights.append(TrendInsight(
                    icon: "checkmark.seal.fill",
                    title: "Mostly positive days",
                    detail: "\(pct)% of your check-ins land on the positive half of the mood scale.",
                    tint: .teal
                ))
            }
        }

        return Array(insights.prefix(4))
    }

    /// Combined scores that fall clearly outside the neutral band (so consistency stats
    /// aren't swamped by "meh" days).
    private static func meaningfulScores(_ entries: [DailyWellness]) -> [Double] {
        entries.map(\.combinedScore).filter { abs($0) >= 0.2 }
    }
}

struct InsightRow: View {
    let insight: TrendInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon)
                .font(.title3)
                .foregroundStyle(insight.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.subheadline.bold())
                Text(insight.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}