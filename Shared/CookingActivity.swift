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
        /// When the running timer started (or was last resumed with its full remaining time); used for the progress bar.
        var timerStart: Date? = nil
        /// Number of timers currently running or ringing.
        var activeTimers: Int? = nil
        /// True when the soonest timer has finished and is ringing.
        var timerDone: Bool? = nil
    }

    var recipeId: UUID
    var recipeTitle: String
}
