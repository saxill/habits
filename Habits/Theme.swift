import SwiftUI

// MARK: - Themes (§5.3)

struct TerminalTheme: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var background: String
    var foreground: String
    var comment: String
    var habitsAccent: String
    var statsAccent: String
    var profileAccent: String

    var isCustom: Bool { id.hasPrefix("custom-") }

    static func builtin() -> [TerminalTheme] {
        [
            TerminalTheme(id: "ansi-dark", name: "ansi dark", background: "#000000",
                          foreground: "#E8E8E8", comment: "#6E6E73",
                          habitsAccent: "#FFB454", statsAccent: "#4ADE80", profileAccent: "#FF6BD6"),
            TerminalTheme(id: "dracula", name: "dracula", background: "#282A36",
                          foreground: "#F8F8F2", comment: "#6272A4",
                          habitsAccent: "#FFB86C", statsAccent: "#50FA7B", profileAccent: "#FF79C6"),
            TerminalTheme(id: "solarized-dark", name: "solarized dark", background: "#002B36",
                          foreground: "#93A1A1", comment: "#586E75",
                          habitsAccent: "#B58900", statsAccent: "#859900", profileAccent: "#D33682"),
        ]
    }

    /// Convenience accessors used across views (replaces the old static TabAccent).
    var bg: Color { Color(hex: background) }
    var fg: Color { Color(hex: foreground) }
    var commentColor: Color { Color(hex: comment) }
    var habitsColor: Color { Color(hex: habitsAccent) }
    var statsColor: Color { Color(hex: statsAccent) }
    var profileColor: Color { Color(hex: profileAccent) }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    /// "#RRGGBB" — used by the theme editor's ColorPicker bindings.
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

// MARK: - Theme store (built-ins + user-customized palettes, persisted to UserDefaults)

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published private(set) var customThemes: [TerminalTheme]

    init() {
        customThemes = TerminalTheme.loadCustom()
    }

    var all: [TerminalTheme] { TerminalTheme.builtin() + customThemes }

    func byId(_ id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? all[0]
    }

    func upsert(_ theme: TerminalTheme) {
        if let i = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[i] = theme
        } else {
            customThemes.append(theme)
        }
    }

    func delete(_ theme: TerminalTheme) {
        customThemes.removeAll { $0.id == theme.id }
    }

    static func duplicate(_ source: TerminalTheme) -> TerminalTheme {
        TerminalTheme(id: "custom-" + UUID().uuidString.prefix(8).lowercased(),
                      name: source.name + " copy", background: source.background,
                      foreground: source.foreground, comment: source.comment,
                      habitsAccent: source.habitsAccent, statsAccent: source.statsAccent,
                      profileAccent: source.profileAccent)
    }
}

extension TerminalTheme {
    private static let customKey = "customThemes.v1"

    static func loadCustom() -> [TerminalTheme] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.customThemes) else { return [] }
        return (try? JSONDecoder().decode([TerminalTheme].self, from: data)) ?? []
    }

    static func saveCustom(_ themes: [TerminalTheme]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(themes), forKey: SettingsKey.customThemes)
    }
}

// MARK: - Settings keys

enum SettingsKey {
    static let username = "username"
    static let themeId = "themeId"
    static let promptSymbol = "promptSymbol"
    static let textSize = "textSize"          // 0/1/2 → default/larger/largest
    static let crossOutCompleted = "crossOutCompleted"
    static let moveCompletedToBottom = "moveCompletedToBottom"
    static let customThemes = "customThemes.v1"
    static let liveActivitiesEnabled = "liveActivitiesEnabled"
    static let laShowTimer = "laShowTimer"
    static let laShowProgress = "laShowProgress"
    static let laShowName = "laShowName"
    static let seeded = "seeded.v1"
}

enum TextScale {
    /// base monospace size × scale
    static func multiplier(for tier: Int) -> CGFloat { [1.0, 1.18, 1.36][max(0, min(2, tier))] }
}

// MARK: - Monospace font helper

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var fontScale: CGFloat {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

private struct TermFontModifier: ViewModifier {
    @Environment(\.fontScale) var scale
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: .monospaced))
    }
}

extension View {
    /// Monospace terminal text at the given base size (scaled by user's text-size setting).
    func term(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> some View {
        modifier(TermFontModifier(size: size, weight: weight))
    }
}