import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if let profile = profiles.first, profile.hasCompletedOnboarding {
            MainTabView(profile: profile)
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    let profile: UserProfile

    var body: some View {
        TabView {
            HomeView(profile: profile)
                .tabItem { Label("Home", systemImage: "house.fill") }

            ChatView(profile: profile)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }

            SettingsView(profile: profile)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [UserProfile.self, DailyWellness.self, ChatSession.self, ChatMessage.self, CrisisEvent.self], inMemory: true)
}
