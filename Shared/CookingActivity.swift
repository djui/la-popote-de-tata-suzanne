import ActivityKit
import Foundation

/// Live Activity shown while a cook-mode timer runs.
struct CookingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stepIndex: Int
        var stepCount: Int
        var stepText: String
        /// When the running timer ends; nil when no timer is running.
        var timerEnd: Date?
        var timerLabel: String?
    }

    var recipeId: UUID
    var recipeTitle: String
}
