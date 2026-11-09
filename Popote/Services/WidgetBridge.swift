import Foundation

/// Publishes upcoming meals to the widget through the App Group.
@MainActor
enum WidgetBridge {
    static func publish(from store: AppStore) {}
    static func clear() {}
}
