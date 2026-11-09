import CoreText
import SwiftUI
import UIKit
import WidgetKit

@main
struct PopoteWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayMenuWidget()
        CookingLiveActivity()
    }
}

// MARK: - Fonts and colours

/// Registers the bundled Fraunces / Nunito files once (the extension has no UIAppFonts entry).
enum WidgetFonts {
    static let registered: Bool = {
        for name in ["Fraunces-SemiBold", "Nunito-Bold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return true
    }()

    static func display(_ size: CGFloat) -> Font {
        _ = registered
        return UIFont(name: "Fraunces-SemiBold", size: size) != nil
            ? .custom("Fraunces-SemiBold", size: size, relativeTo: .headline)
            : .system(size: size, weight: .semibold, design: .serif)
    }

    static func label(_ size: CGFloat) -> Font {
        _ = registered
        return UIFont(name: "Nunito-Bold", size: size) != nil
            ? .custom("Nunito-Bold", size: size, relativeTo: .caption)
            : .system(size: size, weight: .bold, design: .rounded)
    }
}

enum WidgetPalette {
    static let background = dynamic(light: 0xFBF6EC, dark: 0x16203A)
    static let foreground = dynamic(light: 0x3B2E25, dark: 0xF2EBDD)
    static let muted = dynamic(light: 0x857462, dark: 0xA79E8F)
    static let accent = dynamic(light: 0x1F3157, dark: 0xE8CF6E)
    static let line = dynamic(light: 0xE6DBC8, dark: 0x283150)
    static let tileTop = Color(red: 0x2B / 255, green: 0x41 / 255, blue: 0x6E / 255)
    static let tileBottom = Color(red: 0x18 / 255, green: 0x26 / 255, blue: 0x4A / 255)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Timeline

struct MenuEntry: TimelineEntry {
    let date: Date
    let selection: WidgetSnapshot.Selection?
    let thumbnail: UIImage?
    let isPlaceholder: Bool

    static func make(at date: Date, snapshot: WidgetSnapshot?) -> MenuEntry {
        let selection = snapshot?.selection(at: date)
        let thumb = WidgetSnapshot.thumbnailURL(selection?.meal.thumbnailFile).flatMap { UIImage(contentsOfFile: $0.path) }
        return MenuEntry(date: date, selection: selection, thumbnail: thumb, isPlaceholder: false)
    }

    static var placeholder: MenuEntry { sample(redacted: true) }

    static func sample(redacted: Bool) -> MenuEntry {
        let meal = WidgetSnapshot.Meal(date: "", mealType: WidgetSnapshot.dinner, title: "Gratin dauphinois", recipeId: nil, servings: 4)
        let next = WidgetSnapshot.Meal(date: "", mealType: WidgetSnapshot.lunch, title: "Salade niçoise", recipeId: nil, servings: 4)
        return MenuEntry(date: .now,
                         selection: .init(label: String(localized: "CE SOIR"), meal: meal, extraCount: 0,
                                          nextLabel: String(localized: "DEMAIN MIDI"), next: next),
                         thumbnail: nil, isPlaceholder: redacted)
    }
}

struct MenuProvider: TimelineProvider {
    func placeholder(in context: Context) -> MenuEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (MenuEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        if context.isPreview, snapshot?.selection(at: .now) == nil {
            completion(.sample(redacted: false))
        } else {
            completion(.make(at: .now, snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MenuEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        var dates = [Date.now]
        // Entries at every meal boundary (11:00, 15:00, midnight) for the next two days.
        while dates.count < 7, let last = dates.last {
            dates.append(WidgetSnapshot.nextBoundary(after: last))
        }
        let entries = dates.map { MenuEntry.make(at: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct TodayMenuWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayMenu", provider: MenuProvider()) { entry in
            TodayMenuView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(WidgetSnapshot.url(for: entry.selection?.meal))
        }
        .configurationDisplayName("Menu du jour")
        .description("Le prochain repas prévu au menu.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TodayMenuView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MenuEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let s = entry.selection {
                Text(s.label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .widgetAccentable()
                Text(s.meal.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .lineLimit(2)
                if let next = s.next, let label = s.nextLabel {
                    Text("\(label.capitalized) : \(next.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("MENU")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .widgetAccentable()
                Text("Rien de prévu")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = entry.selection {
                thumbnail(size: 52)
                Spacer(minLength: 0)
                Text(s.label)
                    .font(WidgetFonts.label(11))
                    .foregroundStyle(WidgetPalette.accent)
                Text(s.meal.title)
                    .font(WidgetFonts.display(17))
                    .foregroundStyle(WidgetPalette.foreground)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: Medium

    private var medium: some View {
        HStack(spacing: 14) {
            if let s = entry.selection {
                thumbnail(size: 118)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.label)
                        .font(WidgetFonts.label(11))
                        .foregroundStyle(WidgetPalette.accent)
                    Text(s.meal.title)
                        .font(WidgetFonts.display(19))
                        .foregroundStyle(WidgetPalette.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        if let servings = s.meal.servings {
                            Label("\(servings) pers.", systemImage: "person.2")
                        }
                        if s.extraCount > 0 {
                            Text("+ \(s.extraCount) autre(s) plat(s)")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.muted)
                    Spacer(minLength: 0)
                    if let next = s.next, let label = s.nextLabel {
                        Rectangle().fill(WidgetPalette.line).frame(height: 1)
                        Link(destination: WidgetSnapshot.url(for: next)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(label)
                                    .font(WidgetFonts.label(10))
                                    .foregroundStyle(WidgetPalette.muted)
                                Text(next.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WidgetPalette.foreground)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                empty
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: Pieces

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WidgetPalette.accent)
            Spacer(minLength: 0)
            Text("Rien de prévu")
                .font(WidgetFonts.display(17))
                .foregroundStyle(WidgetPalette.foreground)
            Text("Touche pour remplir le menu.")
                .font(.system(size: 12))
                .foregroundStyle(WidgetPalette.muted)
        }
    }

    private func thumbnail(size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [WidgetPalette.tileTop, WidgetPalette.tileBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image = entry.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.32, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .accessibilityHidden(true)
    }
}

#Preview(as: .systemMedium) {
    TodayMenuWidget()
} timeline: {
    MenuEntry.sample(redacted: false)
}
