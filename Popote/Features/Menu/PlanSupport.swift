import SwiftUI

// Small helpers shared by the Menu and Courses screens.

/// Locale-aware date labels ("9 nov.", "lundi 10 nov.") for the menu and shopping screens.
enum PlanDates {
    static var calendar: Calendar { LocalDay.mondayCalendar }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// `d MMM`, e.g. "9 nov.".
    static func dayMonth(_ date: Date, locale: Locale = AppLanguage.current.locale) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).day().month(.abbreviated))
    }

    /// "9 nov. – 15 nov."
    static func range(_ start: Date, _ end: Date, locale: Locale = AppLanguage.current.locale) -> String {
        "\(dayMonth(start, locale: locale)) – \(dayMonth(end, locale: locale))"
    }

    /// Capitalised "Lundi 10 nov." (`weekday:long, day:numeric, month:short`).
    static func dayTitle(_ date: Date, locale: Locale = AppLanguage.current.locale) -> String {
        long(date, locale: locale).capitalizedFirst
    }

    /// "lundi 10 nov."
    static func long(_ date: Date, locale: Locale = AppLanguage.current.locale) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.wide).day().month(.abbreviated))
    }

    static func shortWeekday(_ date: Date, locale: Locale = AppLanguage.current.locale) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated)).capitalizedFirst
    }

    static func dayNumber(_ date: Date, locale: Locale = AppLanguage.current.locale) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar).day())
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Toast

/// A lightweight banner, the app's equivalent of the website's sonner toasts.
struct PlanToast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var systemImage: String?
    var actionTitle: LocalizedStringKey?
    var action: (@MainActor () -> Void)?

    static func == (a: PlanToast, b: PlanToast) -> Bool { a.id == b.id }
}

private struct PlanToastModifier: ViewModifier {
    @Binding var toast: PlanToast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 10) {
                    if let icon = toast.systemImage {
                        Image(systemName: icon).foregroundStyle(Palette.onPrimary.opacity(0.85))
                    }
                    Text(toast.text)
                        .font(AppFont.body(15, weight: .semibold))
                        .foregroundStyle(Palette.onPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let title = toast.actionTitle, let action = toast.action {
                        Button(title) {
                            action()
                            self.toast = nil
                        }
                        .font(AppFont.body(15, weight: .heavy))
                        .foregroundStyle(Palette.lemon)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Palette.primary, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: 520)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { self.toast = nil }
                .accessibilityElement(children: .combine)
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(4))
                    if self.toast?.id == toast.id { self.toast = nil }
                }
            }
        }
        .animation(.snappy, value: toast)
        .onChange(of: toast) { _, new in
            if let new { AccessibilityNotification.Announcement(new.text).post() }
        }
    }
}

extension View {
    func planToast(_ toast: Binding<PlanToast?>) -> some View { modifier(PlanToastModifier(toast: toast)) }
}

// MARK: - Servings stepper

/// `Personnes  [−] n [+]`, minimum 1.
struct ServingsStepper: View {
    @Binding var servings: Int
    var title: LocalizedStringKey = "Personnes"

    var body: some View {
        Stepper(value: $servings, in: 1...99) {
            HStack {
                Text(title)
                    .font(AppFont.body(16, weight: .semibold))
                Spacer()
                Text(servings, format: .number)
                    .font(AppFont.body(17, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .sensoryFeedback(.selection, trigger: servings)
    }
}
