import ActivityKit
import AudioToolbox
import Foundation
import Observation
import UIKit
import UserNotifications

/// A cook-mode timer (SPEC §A.3 "Timers"). Paused timers keep `remaining` and have no `endsAt`.
struct CookTimer: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var label: String
    var total: Int
    var endsAt: Date?
    var remaining: Double?
    var done = false

    var isPaused: Bool { !done && endsAt == nil }

    func secondsLeft(at now: Date) -> Int {
        if done { return 0 }
        if let endsAt { return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up))) }
        return max(0, Int((remaining ?? 0).rounded(.up)))
    }
}

/// What is saved per recipe so the cook can pick up where they left off (12 h).
struct SavedCookSession: Codable, Equatable, Sendable {
    var step: Int
    var struck: [Int]
    var servings: Int
    var timers: [CookTimer]
    var savedAt: Date

    static let lifetime: TimeInterval = 12 * 3600

    var isWorthResuming: Bool { step > 0 || !struck.isEmpty || !timers.isEmpty }

    private static func key(_ id: UUID) -> String { "popote-cuisine-\(id.uuidString.lowercased())" }

    static func load(_ recipeId: UUID, now: Date = .now, defaults: UserDefaults = .standard) -> SavedCookSession? {
        guard let data = defaults.data(forKey: key(recipeId)),
              let s = try? JSONDecoder.popote.decode(SavedCookSession.self, from: data) else { return nil }
        guard now.timeIntervalSince(s.savedAt) < lifetime else {
            defaults.removeObject(forKey: key(recipeId))
            return nil
        }
        return s
    }

    func save(_ recipeId: UUID, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder.popote.encode(self) { defaults.set(data, forKey: Self.key(recipeId)) }
    }

    static func clear(_ recipeId: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(recipeId))
    }
}

/// Runs the timers: countdown tick, alarm (sound + haptic), local notifications and the Live Activity.
@MainActor
@Observable
final class CookTimerCenter {
    private(set) var timers: [CookTimer] = []
    private(set) var now = Date()

    let recipeId: UUID
    let recipeTitle: String
    /// Current step, mirrored into the Live Activity.
    var stepInfo: (index: Int, count: Int, text: String) = (0, 0, "") {
        didSet { updateActivity() }
    }

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var lastAlarm = Date.distantPast
    @ObservationIgnored private var activityId: String?
    @ObservationIgnored private var lastActivityState: CookingActivityAttributes.ContentState?

    init(recipeId: UUID, recipeTitle: String) {
        self.recipeId = recipeId
        self.recipeTitle = recipeTitle
        activityId = Activity<CookingActivityAttributes>.activities.first { $0.attributes.recipeId == recipeId }?.id
    }

    var anyDone: Bool { timers.contains(where: \.done) }

    // MARK: Actions

    func start(label: String, seconds: Int) {
        requestNotificationPermissionIfNeeded()
        let t = CookTimer(label: label, total: seconds, endsAt: .now.addingTimeInterval(TimeInterval(seconds)))
        timers.append(t)
        schedule(t)
        changed()
    }

    func togglePause(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }), !timers[i].done else { return }
        if let endsAt = timers[i].endsAt {
            timers[i].remaining = max(0, endsAt.timeIntervalSinceNow)
            timers[i].endsAt = nil
            unschedule(id)
        } else {
            timers[i].endsAt = .now.addingTimeInterval(timers[i].remaining ?? 0)
            timers[i].remaining = nil
            schedule(timers[i])
        }
        changed()
    }

    func addMinute(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }), !timers[i].done else { return }
        timers[i].total += 60
        if let endsAt = timers[i].endsAt {
            timers[i].endsAt = endsAt.addingTimeInterval(60)
            schedule(timers[i])
        } else {
            timers[i].remaining = (timers[i].remaining ?? 0) + 60
        }
        changed()
    }

    /// Cancel (running) or stop (done) a timer.
    func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
        unschedule(id)
        changed()
    }

    /// Restores saved timers; the ones that expired meanwhile are marked done.
    func restore(_ saved: [CookTimer]) {
        let now = Date.now
        timers = saved.map { t in
            var t = t
            if let e = t.endsAt, e <= now { t.done = true; t.endsAt = nil; t.remaining = 0 }
            return t
        }
        changed()
    }

    /// Clears every timer, its notification and the Live Activity.
    func reset(alsoCancel ids: [UUID] = []) {
        let all = timers.map(\.id) + ids
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: all.map(Self.notificationId))
        timers = []
        changed()
        endActivity()
    }

    /// Leaving cook mode: notifications stay scheduled (the timers are saved), the tick and activity stop.
    func suspend() {
        tickTask?.cancel()
        tickTask = nil
        endActivity()
    }

    // MARK: Tick

    private func changed() {
        now = .now
        if timers.isEmpty {
            tickTask?.cancel()
            tickTask = nil
        } else if tickTask == nil {
            tickTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.tick()
                }
            }
        }
        updateActivity()
    }

    private func tick() {
        let current = Date.now
        now = current
        var finished = false
        for i in timers.indices where !timers[i].done {
            if let e = timers[i].endsAt, e <= current {
                timers[i].done = true
                timers[i].endsAt = nil
                timers[i].remaining = 0
                finished = true
            }
        }
        if finished {
            updateActivity()
        }
        if anyDone, current.timeIntervalSince(lastAlarm) >= 1.5 {
            lastAlarm = current
            alarm()
        }
    }

    private func alarm() {
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    // MARK: Notifications

    private static func notificationId(_ id: UUID) -> String { "cook-timer-\(id.uuidString)" }

    private func requestNotificationPermissionIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
    }

    private func schedule(_ t: CookTimer) {
        guard let endsAt = t.endsAt else { return }
        let interval = endsAt.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "⏰ Minuteur terminé")
        content.body = t.label
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["recipeId": recipeId.uuidString]
        let request = UNNotificationRequest(identifier: Self.notificationId(t.id), content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    private func unschedule(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId(id)])
    }

    // MARK: Live Activity

    private func currentActivityState() -> CookingActivityAttributes.ContentState? {
        let running = timers.filter { $0.endsAt != nil }.sorted { $0.endsAt! < $1.endsAt! }
        let done = timers.first(where: \.done)
        guard !running.isEmpty || done != nil else { return nil }
        let active = timers.filter { !$0.isPaused }.count
        if let done {
            return .init(stepIndex: stepInfo.index, stepCount: stepInfo.count, stepText: stepInfo.text,
                         timerEnd: nil, timerLabel: done.label, timerStart: nil, activeTimers: active, timerDone: true)
        }
        let t = running[0]
        let end = t.endsAt!
        return .init(stepIndex: stepInfo.index, stepCount: stepInfo.count, stepText: stepInfo.text,
                     timerEnd: end, timerLabel: t.label,
                     timerStart: end.addingTimeInterval(-TimeInterval(t.total)), activeTimers: active, timerDone: false)
    }

    private func updateActivity() {
        guard let state = currentActivityState() else {
            endActivity()
            return
        }
        guard state != lastActivityState else { return }
        lastActivityState = state
        let content = ActivityContent(state: state, staleDate: state.timerEnd?.addingTimeInterval(3600))
        if let id = activityId, Self.liveActivity(id)?.activityState == .active {
            Task.detached { await Self.liveActivity(id)?.update(content) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            activityId = (try? Activity.request(
                attributes: CookingActivityAttributes(recipeId: recipeId, recipeTitle: recipeTitle),
                content: content, pushType: nil))?.id
        }
    }

    nonisolated private static func liveActivity(_ id: String) -> Activity<CookingActivityAttributes>? {
        Activity<CookingActivityAttributes>.activities.first { $0.id == id }
    }

    private func endActivity() {
        lastActivityState = nil
        guard let id = activityId else { return }
        activityId = nil
        Task.detached { await Self.liveActivity(id)?.end(nil, dismissalPolicy: .immediate) }
    }
}
