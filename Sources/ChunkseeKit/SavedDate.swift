import Foundation

/// Mojang's saved timestamps, shared by name caches and advancement criteria.
enum SavedDate {
    // Modern DateFormatter is thread safe on our 64-bit macOS target. Configure this private
    // instance before publication; readers never change its locale, format or other settings.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    static func parse(_ text: String) -> Date? { formatter.date(from: text) }
}
