import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    let profile: UserProfile

    @Query(sort: \DailyWellness.date, order: .reverse) private var entries: [DailyWellness]
    @State private var showCheckIn = false

    private var todayEntry: DailyWellness? {
        entries.first { Calendar.current.isDateInToday($0.date) }
    }

    private var last7Days: [DailyWellness] {
        Array(entries.prefix(7)).reversed()
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Hi, \(profile.name.isEmpty ? "there" : profile.name) 👋")
                        .font(.title2.bold())

                    moodCard

                    if last7Days.count > 1 {
                        VStack(alignment: .leading) {
                            Text("7-Day Trend").font(.headline)
                            Chart(last7Days) { entry in
                                LineMark(
                                    x: .value("Date", entry.date, unit: .day),
                                    y: .value("Mood", entry.combinedScore)
                                )
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Date", entry.date, unit: .day),
                                    y: .value("Mood", entry.combinedScore)
                                )
                            }
                            .chartYScale(domain: -1...1)
                            .frame(height: 180)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }

                    Button {
                        showCheckIn = true
                    } label: {
                        Label(
                            todayEntry == nil ? "Daily Check-In" : "Update Today's Check-In",
                            systemImage: "square.and.pencil"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("\(streak)-day check-in streak")
                        Spacer()
                    }
                    .font(.subheadline)
                }
                .padding()
            }
            .navigationTitle("MindMate")
            .sheet(isPresented: $showCheckIn) {
                DailyCheckInView(existingEntry: todayEntry)
            }
        }
    }

    @ViewBuilder
    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Mood").font(.headline)
            if let today = todayEntry {
                Text(Constants.band(for: today.combinedScore)).font(.title.bold())
                Text(String(format: "Score: %.2f", today.combinedScore))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No check-in yet today").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
