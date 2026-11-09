import Foundation

/// Picks which meal the "Menu du jour" widget (and the Siri intent) shows at a given moment.
///
/// Until 15:00 the headline is today's lunch ("CE MIDI"), afterwards today's dinner ("CE SOIR").
/// When that slot is empty, the next planned meal is shown with its own label ("DEMAIN MIDI", "JEUDI SOIR"…).
extension WidgetSnapshot {
    static let lunch = "déjeuner"
    static let dinner = "dîner"

    struct Selection: Hashable, Sendable {
        var label: String
        var meal: Meal
        /// Other dishes planned for the same slot.
        var extraCount: Int
        var nextLabel: String?
        var next: Meal?
    }

    /// Hours at which the headline can change: 11:00, 15:00 and midnight.
    static let boundaryHours = [11, 15]

    static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func mealOrder(_ type: String) -> Int { type == lunch ? 0 : 1 }

    /// The slot that is "current" at `date`: today's lunch before 15:00, otherwise today's dinner.
    static func currentSlot(at date: Date, calendar: Calendar = .current) -> (day: String, mealType: String) {
        let hour = calendar.component(.hour, from: date)
        return (dayFormatter(calendar).string(from: date), hour < 15 ? lunch : dinner)
    }

    /// The next moment the widget should refresh: 11:00, 15:00 or the following midnight.
    static func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        for hour in boundaryHours {
            if let d = calendar.date(byAdding: .hour, value: hour, to: start), d > date { return d }
        }
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(3600)
    }

    /// Meals sorted by day, then lunch before dinner (keeps the stored order within a slot).
    var sortedMeals: [Meal] {
        meals.enumerated().sorted { a, b in
            (a.element.date, Self.mealOrder(a.element.mealType), a.offset) < (b.element.date, Self.mealOrder(b.element.mealType), b.offset)
        }.map(\.element)
    }

    func selection(at date: Date, calendar: Calendar = .current) -> Selection? {
        let slot = Self.currentSlot(at: date, calendar: calendar)
        let key = (slot.day, Self.mealOrder(slot.mealType))
        let upcoming = sortedMeals.filter { ($0.date, Self.mealOrder($0.mealType)) >= key }
        guard let first = upcoming.first else { return nil }
        let sameSlot = upcoming.filter { $0.date == first.date && $0.mealType == first.mealType }
        let next = upcoming.first { $0.date != first.date || $0.mealType != first.mealType }
        return Selection(
            label: Self.label(for: first, at: date, calendar: calendar),
            meal: first,
            extraCount: sameSlot.count - 1,
            nextLabel: next.map { Self.label(for: $0, at: date, calendar: calendar) },
            next: next
        )
    }

    /// "CE MIDI", "CE SOIR", "DEMAIN MIDI", "VENDREDI SOIR"…
    static func label(for meal: Meal, at date: Date, calendar: Calendar = .current) -> String {
        let f = dayFormatter(calendar)
        let today = f.string(from: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date).map { f.string(from: $0) }
        let isLunch = meal.mealType == lunch
        if meal.date == today {
            return isLunch ? String(localized: "CE MIDI") : String(localized: "CE SOIR")
        }
        if meal.date == tomorrow {
            return isLunch ? String(localized: "DEMAIN MIDI") : String(localized: "DEMAIN SOIR")
        }
        let day = f.date(from: meal.date).map {
            $0.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)).uppercased()
        } ?? meal.date
        return isLunch ? String(localized: "\(day) MIDI") : String(localized: "\(day) SOIR")
    }

    /// Deep link opened when the widget is tapped.
    static func url(for meal: Meal?) -> URL {
        if let id = meal?.recipeId { return URL(string: "popote://recette/\(id.uuidString)")! }
        return URL(string: "popote://menu")!
    }

    static func thumbnailURL(_ file: String?) -> URL? {
        guard let file else { return nil }
        return containerURL?.appending(path: file)
    }
}
