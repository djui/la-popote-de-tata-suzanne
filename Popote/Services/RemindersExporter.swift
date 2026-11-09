import EventKit
import Foundation

/// Exports the unchecked shopping items to a Reminders list named "Courses – La Popote".
/// Re-exporting reuses the list and skips titles that are already there and not completed.
@MainActor
enum RemindersExporter {
    enum Outcome: Equatable {
        case exported(added: Int, total: Int)
        case denied
        case failed(String)
    }

    static let listTitle = "Courses – La Popote"

    static func export(titles: [String]) async -> Outcome {
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { return .denied }
        } catch {
            return EKEventStore.authorizationStatus(for: .reminder) == .denied ? .denied : .failed(error.localizedDescription)
        }

        do {
            let list = try findOrCreateList(in: store)
            let existing = await openTitles(in: list, store: store)
            var added = 0
            for title in titles where !existing.contains(title) {
                let reminder = EKReminder(eventStore: store)
                reminder.title = title
                reminder.calendar = list
                try store.save(reminder, commit: false)
                added += 1
            }
            try store.commit()
            return .exported(added: added, total: titles.count)
        } catch {
            store.reset()
            return .failed(error.localizedDescription)
        }
    }

    private static func findOrCreateList(in store: EKEventStore) throws -> EKCalendar {
        if let list = store.calendars(for: .reminder).first(where: { $0.title == listTitle }) { return list }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = listTitle
        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else {
            throw NSError(domain: "RemindersExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Aucun compte Rappels disponible.")])
        }
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    private static func openTitles(in list: EKCalendar, store: EKEventStore) async -> Set<String> {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: Set((reminders ?? []).compactMap(\.title)))
            }
        }
    }
}
