import SwiftUI

/// Colour and icon of an aisle (`ingredient_categories.color` / `.icon`), with the website's fallbacks.
struct AisleStyle {
    var color: Color?
    var symbol: String

    init(_ aisle: IngredientCategory?) {
        color = aisle?.color.flatMap(Self.parse)
        symbol = Self.symbols[aisle?.icon ?? ""] ?? "basket"
    }

    /// lucide icon names → closest SF Symbols. Fallback: shopping-basket.
    static let symbols: [String: String] = [
        "apple": "leaf.fill", "carrot": "carrot", "leaf": "leaf", "croissant": "birthday.cake",
        "milk": "waterbottle", "cheese": "square.split.diagonal.2x2", "egg": "oval.portrait",
        "beef": "fork.knife", "drumstick": "bird", "ham": "fork.knife.circle", "fish": "fish",
        "wheat": "laurel.leading", "archive": "archivebox", "package": "shippingbox", "candy": "gift",
        "soup": "takeoutbag.and.cup.and.straw", "flame": "flame", "snowflake": "snowflake",
        "cup-soda": "mug", "spray-can": "bubbles.and.sparkles", "shopping-basket": "basket",
    ]

    /// Accepts `#rgb`, `#rrggbb` and `#rrggbbaa`; anything else (CSS functions…) falls back to the chip colour.
    static func parse(_ css: String) -> Color? {
        var hex = css.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count == 8 { hex = String(hex.prefix(6)) }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(hex: value)
    }
}

/// The small coloured square with the aisle icon.
struct AisleIcon: View {
    let style: AisleStyle
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: style.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(style.color == nil ? Palette.muted : Color.white)
            .frame(width: size, height: size)
            .background(style.color ?? Palette.chip, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
