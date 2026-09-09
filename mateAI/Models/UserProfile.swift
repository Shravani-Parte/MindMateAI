import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var name: String
    var occupation: String
    var typicalWorkHours: String
    var stressors: String
    var sleepHours: Double
    var exerciseFrequency: String
    var supportSystem: String
    var goals: String
    var hasCompletedOnboarding: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        occupation: String = "",
        typicalWorkHours: String = "",
        stressors: String = "",
        sleepHours: Double = 7,
        exerciseFrequency: String = "",
        supportSystem: String = "",
        goals: String = "",
        hasCompletedOnboarding: Bool = false
    ) {
        self.id = id
        self.name = name
        self.occupation = occupation
        self.typicalWorkHours = typicalWorkHours
        self.stressors = stressors
        self.sleepHours = sleepHours
        self.exerciseFrequency = exerciseFrequency
        self.supportSystem = supportSystem
        self.goals = goals
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
