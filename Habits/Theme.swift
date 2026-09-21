import SwiftUI

// MARK: - Themes (§5.3)

struct TerminalTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: String
    let foreground: String
    let comment: String
    let dim: String

    static let all: [TerminalTheme] = [
        TerminalTheme(id: "ansi-dark", name: "ansi dark", background: "#000000",
                      foreground: "#E8E8E8", comment: "#6E6E73", dim: "#9A9AA0"),
        TerminalTheme(id: "dracula", name: "dracula", background: "#282A36",
                      foreground: "#F8F8F2", comment: "#6272A4", dim: "#BD93F9"),
        TerminalTheme(id: "solarized-dark", name: "solarized dark", background: "#002B36",
                      foreground: "#93A1A1", comment: "#586E75", dim: "#839496"),
    ]

    static func byId(_ id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? all[0]
    }
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
}

// MARK: - Settings keys

enum SettingsKey {
    static let username = "username"
    static let themeId = "themeId"
    static let promptSymbol = "promptSymbol"
    static let textSize = "textSize"          // 0/1/2 → default/larger/largest
    static let crossOutCompleted = "crossOutCompleted"
    static let moveCompletedToBottom = "moveCompletedToBottom"
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

// MARK: - Per-tab accents (§5.3)

enum TabAccent {
    static let habits = Color(hex: "#FFB454")   // amber
    static let stats = Color(hex: "#4ADE80")    // green
    static let profile = Color(hex: "#FF6BD6")  // pink/magenta
}