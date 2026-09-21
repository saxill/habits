import SwiftUI

// Terminal building blocks used across all tabs (§3, §5.1).

struct BracketCheckbox: View {
    let checked: Bool
    var color: Color = .white

    var body: some View {
        Text(checked ? "[✓]" : "[ ]")
            .term(13, .semibold)
            .foregroundStyle(checked ? color : Color(hex: "#6E6E73"))
            .monospacedDigit()
    }
}

struct CommentText: View {
    @Environment(\.theme) private var theme
    let text: String
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .term(size)
            .foregroundStyle(Color(hex: theme.comment))
    }
}

/// Screen header in prompt form: `user[pro]@init.Habits $ daily`
struct PromptHeader: View {
    @AppStorage(SettingsKey.username) private var username = "user"
    @AppStorage(SettingsKey.promptSymbol) private var symbol = "$"
    let command: String
    let accent: Color
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 0) {
            Text("\(username)[pro]@init.Habits ")
                .term(14, .semibold)
                .foregroundStyle(accent)
            Text(symbol + " ")
                .term(14, .semibold)
                .foregroundStyle(Color(hex: "#6E6E73"))
            Text(command)
                .term(14, .semibold)
                .foregroundStyle(.white)
            Spacer()
            trailing
        }
    }
}

/// Mon–Sun week strip with per-day completion fill bars (§4.1).
struct WeekStrip: View {
    @Environment(\.theme) private var theme
    let week: [Date]
    let selected: Date
    let onSelect: (Date) -> Void
    let habits: [Habit]
    private let cal = Calendar.current

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(orderedDays.enumerated()), id: \.1) { i, day in
                dayColumn(index: i, day: day)
            }
        }
    }

    private var orderedDays: [Date] {
        // `week` is always a Monday-start week (see Date.weekDates).
        week
    }

    private func dayColumn(index: Int, day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let ratio = Streaks.dayRatio(day, habits: habits)
        let isPast = day < cal.startOfDay(for: Date())
        let isFuture = !isPast && !cal.isDateInToday(day)

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 4) {
                Text(Self.letters[index])
                    .term(10)
                    .foregroundStyle(isSelected ? TabAccent.habits : Color(hex: theme.comment))
                Text("\(cal.component(.day, from: day))")
                    .term(13, .semibold)
                    .foregroundStyle(
                        isSelected ? TabAccent.habits :
                        isFuture ? Color(hex: theme.comment) :
                        .white
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isToday && !isSelected ? TabAccent.habits.opacity(0.25) : .clear)
                    )
                    .padding(.horizontal, 6)
                // fill bar: hatched/empty = future, intensity = completion %
                RoundedRectangle(cornerRadius: 2)
                    .fill(ratio <= 0 ? Color(hex: theme.comment).opacity(0.3) : TabAccent.habits.opacity(ratio < 0 ? 0.2 : 0.35 + 0.65 * ratio))
                    .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Reusable terminal-style segmented control — plain buttons, no system Picker quirks.
struct TermSegmentBar: View {
    let options: [(id: String, label: String)]
    let selection: String
    let accent: Color
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.id) { option in
                let isSelected = option.id == selection
                Button {
                    onSelect(option.id)
                } label: {
                    Text(option.label)
                        .term(11, isSelected ? .bold : .regular)
                        .foregroundStyle(isSelected ? accent : Color(hex: "#6E6E73"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSelected ? accent.opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

extension EnvironmentValues {
    var theme: TerminalTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = TerminalTheme.all[0]
}

extension Date {
    /// Monday-start week containing self.
    func weekDates(calendar: Calendar = .current) -> [Date] {
        let wd = calendar.component(.weekday, from: self)
        let offset = (wd + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: self))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
}