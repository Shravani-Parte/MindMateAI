import Foundation

/// A single band's check-in count (Identifiable so it can feed `ForEach` directly).
struct MoodBandCount: Identifiable {
    let id: String // band name
    let band: String
    let count: Int
}

/// Overall direction of a mood trend, used for arrows and chips across the UI.
enum MoodTrendDirection: String {
    case up = "Up"
    case down = "Down"
    case flat = "Steady"

    /// SF Symbol reflecting the direction (used in stat chips/cards).
    var symbol: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }
}

/// Pure, side-effect-free mood math over `DailyWellness` entries.
/// All inputs should be the entries themselves (any order — callers pick what they need);
/// outputs are always computed on date-sorted data.
enum TrendAnalyzer {

    /// Rough magnitude (points of combinedScore) that separates "real change" from noise.
    /// -0.2...0.2 is the "Neutral" band, so anything wider than half a band counts.
    static let meaningfulDelta: Double = 0.1

    static func sortedByDate(_ entries: [DailyWellness]) -> [DailyWellness] {
        entries.sorted { $0.date < $1.date }
    }

    static func average(of scores: [Double]) -> Double? {
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    static func averageScore(of entries: [DailyWellness]) -> Double? {
        average(of: entries.map(\.combinedScore))
    }

    /// Simple linear-regression slope of combinedScore against date, in points-per-day.
    /// Positive → mood rising over time; negative → falling.
    static func slopePerDay(of entries: [DailyWellness]) -> Double {
        let sorted = sortedByDate(entries)
        guard sorted.count >= 2 else { return 0 }

        let x = sorted.enumerated().map { Double($0.offset) }
        let y = sorted.map(\.combinedScore)
        let meanX = x.reduce(0, +) / Double(x.count)
        let meanY = y.reduce(0, +) / Double(y.count)

        var numerator = 0.0
        var denominator = 0.0
        for i in 0..<x.count {
            numerator += (x[i] - meanX) * (y[i] - meanY)
            denominator += (x[i] - meanX) * (x[i] - meanX)
        }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    static func direction(of entries: [DailyWellness]) -> MoodTrendDirection {
        let slope = slopePerDay(of: entries)
        if slope > 0.02 { return .up }
        if slope < -0.02 { return .down }
        return .flat
    }

    /// Change in average mood between two slices (e.g. last 7 days vs the 7 before).
    static func delta(between recent: [DailyWellness], and previous: [DailyWellness]) -> Double? {
        guard let recentAvg = averageScore(of: recent), let previousAvg = averageScore(of: previous) else {
            return nil
        }
        return recentAvg - previousAvg
    }

    /// Number of consecutive trailing entries (ending at the most recent) that sit in a
    /// band. `up` counts days at/above the High threshold, `down` at/below the Low one.
    static func trailingStreak(of entries: [DailyWellness], up: Bool) -> Int {
        let sorted = sortedByDate(entries)
        var count = 0
        var previousDate: Date?
        let threshold = up ? 0.2 : -0.2

        for entry in sorted.reversed() {
            let inBand = up ? entry.combinedScore >= threshold : entry.combinedScore <= threshold
            guard inBand else { break }

            if let previousDate {
                // The streak only continues across consecutive calendar days.
                let daysBetween = Calendar.current.dateComponents(
                    [.day], from: entry.date, to: previousDate
                ).day ?? 0
                guard daysBetween <= 1 else { break }
            }
            count += 1
            previousDate = entry.date
        }
        return count
    }

    /// Current streak of consecutive decline days (mood ≤ Low threshold).
    static func lowMoodStreak(of entries: [DailyWellness]) -> Int {
        trailingStreak(of: entries, up: false)
    }

    /// Current streak of consecutive rise days (mood ≥ High threshold).
    static func risingStreak(of entries: [DailyWellness]) -> Int {
        trailingStreak(of: entries, up: true)
    }

    // MARK: - Aggregations for charts

    /// Average combinedScore for each weekday (Sun=1 ... Sat=7), treating calendar days
    /// the user hasn't checked in on as "no data".
    static func sundayFirst(_ entry: DailyWellness) -> Int { Calendar.current.component(.weekday, from: entry.date) }

    static func weekdayAverages(of entries: [DailyWellness]) -> [(weekday: Int, label: String, score: Double?)] {
        let ordered = [2, 3, 4, 5, 6, 7, 1] // Mon → Sun
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var buckets: [Int: [Double]] = [:]
        for entry in entries {
            buckets[sundayFirst(entry), default: []].append(entry.combinedScore)
        }
        return ordered.enumerated().map { index, weekday in
            let scores = buckets[weekday] ?? []
            return (weekday, labels[index], average(of: scores))
        }
    }

    /// Average mood per trailing 7-day window, oldest → newest, up to `count` weeks,
    /// ending on the most recent entry. Entries older than the window are ignored.
    static func weeklyAverages(of entries: [DailyWellness], count: Int = 8) -> [(label: String, score: Double?)] {
        let sorted = sortedByDate(entries)
        guard let lastDate = sorted.last?.date else { return [] }

        var buckets = Array(repeating: [Double](), count: count)
        for entry in sorted {
            let daysBack = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: entry.date),
                to: Calendar.current.startOfDay(for: lastDate)
            ).day ?? 0
            let index = daysBack / 7
            guard index < count else { continue }
            buckets[count - 1 - index].append(entry.combinedScore)
        }

        let formatter = Date.FormatStyle().month(.abbreviated).day(.defaultDigits)
        return buckets.enumerated().compactMap { index, scores in
            guard !scores.isEmpty else { return nil }
            let weekStart = Calendar.current.date(
                byAdding: .day,
                value: -(count - 1 - index) * 7,
                to: Calendar.current.startOfDay(for: lastDate)
            ) ?? lastDate
            let label = index == count - 1 ? "This wk" : formatter.format(weekStart)
            return (label, average(of: scores))
        }
    }

    /// How many of the user's check-ins fall into each mood band (order: Very Low → Very High).
    static func bandDistribution(of entries: [DailyWellness]) -> [MoodBandCount] {
        Constants.bands.map { band in
            MoodBandCount(id: band, band: band, count: entries.filter { Constants.band(for: $0.combinedScore) == band }.count)
        }
    }

    /// The single best and worst (most negative) entry.
    static func extremes(of entries: [DailyWellness]) -> (best: DailyWellness?, worst: DailyWellness?) {
        guard !entries.isEmpty else { return (nil, nil) }
        let best = entries.max { $0.combinedScore < $1.combinedScore }
        let worst = entries.min { $0.combinedScore < $1.combinedScore }
        return (best, worst)
    }
}