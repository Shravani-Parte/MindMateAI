import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query(sort: \DailyWellness.date) private var entries: [DailyWellness]

    private var weeklyAverage: Double {
        let last7 = Array(entries.suffix(7))
        guard !last7.isEmpty else { return 0 }
        return last7.map(\.combinedScore).reduce(0, +) / Double(last7.count)
    }

    private var monthlyAverage: Double {
        let last30 = Array(entries.suffix(30))
        guard !last30.isEmpty else { return 0 }
        return last30.map(\.combinedScore).reduce(0, +) / Double(last30.count)
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
                        Chart(entries) { entry in
                            LineMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value("Mood", entry.combinedScore)
                            )
                            .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: -1...1)
                        .frame(height: 220)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                        HStack(spacing: 16) {
                            statCard(title: "7-Day Avg", value: weeklyAverage)
                            statCard(title: "30-Day Avg", value: monthlyAverage)
                        }

                        if weeklyAverage <= Constants.lowMoodThreshold {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                Text("Your mood trend has been low lately. Consider reaching out to a professional or trusted person.")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Trends")
        }
    }

    private func statCard(title: String, value: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value)).font(.title2.bold())
            Text(Constants.band(for: value)).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
