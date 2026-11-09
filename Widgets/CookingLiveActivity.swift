import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island presentation of a running cook-mode timer.
struct CookingLiveActivity: Widget {
    static let navy = Color(red: 0x12 / 255, green: 0x1A / 255, blue: 0x33 / 255)
    static let lemon = Color(red: 0xE8 / 255, green: 0xCF / 255, blue: 0x6E / 255)
    static let cream = Color(red: 0xF5 / 255, green: 0xEE / 255, blue: 0xDF / 255)
    static let muted = Color(red: 0xA9 / 255, green: 0xA3 / 255, blue: 0x91 / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookingActivityAttributes.self) { context in
            CookingLockScreenView(context: context)
                .activityBackgroundTint(Self.navy)
                .activitySystemActionForegroundColor(Self.lemon)
                .widgetURL(Self.url(context.attributes.recipeId))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.timerLabel ?? String(localized: "Minuteur"))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Self.lemon)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CookingCountdown(state: context.state)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Self.lemon)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.recipeTitle)
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .foregroundStyle(Self.muted)
                            .lineLimit(1)
                        Text(context.state.stepText)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Self.cream)
                            .lineLimit(2)
                        CookingProgress(state: context.state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.timerDone == true ? "bell.and.waves.left.and.right.fill" : "timer")
                    .foregroundStyle(Self.lemon)
            } compactTrailing: {
                CookingCountdown(state: context.state)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Self.lemon)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.timerDone == true ? "bell.fill" : "timer")
                    .foregroundStyle(Self.lemon)
            }
            .widgetURL(Self.url(context.attributes.recipeId))
            .keylineTint(Self.lemon)
        }
    }

    static func url(_ id: UUID) -> URL? { URL(string: "popote://recette/\(id.uuidString.lowercased())") }
}

private struct CookingLockScreenView: View {
    let context: ActivityViewContext<CookingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.recipeTitle)
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundStyle(CookingLiveActivity.muted)
                        .lineLimit(1)
                    Label {
                        Text(context.state.timerLabel ?? String(localized: "Minuteur")).lineLimit(1)
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(CookingLiveActivity.lemon)
                }
                Spacer(minLength: 8)
                CookingCountdown(state: context.state)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(CookingLiveActivity.lemon)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            Text("Étape \(context.state.stepIndex + 1) / \(context.state.stepCount) · \(context.state.stepText)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CookingLiveActivity.cream)
                .lineLimit(2)
            CookingProgress(state: context.state)
        }
        .padding(16)
    }
}

/// Counts down without updates from the app thanks to `Text(timerInterval:)`.
private struct CookingCountdown: View {
    let state: CookingActivityAttributes.ContentState

    var body: some View {
        if state.timerDone == true {
            Text("Terminé !")
        } else if let end = state.timerEnd {
            let start = min(state.timerStart ?? .now, end)
            Text(timerInterval: start...end, countsDown: true)
                .monospacedDigit()
        } else {
            Text("En pause")
        }
    }
}

private struct CookingProgress: View {
    let state: CookingActivityAttributes.ContentState

    var body: some View {
        if let end = state.timerEnd, let start = state.timerStart, start < end, state.timerDone != true {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(CookingLiveActivity.lemon)
        }
    }
}
