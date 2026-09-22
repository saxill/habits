import SwiftUI
import SwiftData

/// Stats tab — §4.2: overview + per-habit deep dive.
///
/// Every figure on this screen is derived from `Completion` history (§7); nothing here is
/// stored. Ranges are expressed in whole weeks so the heatmap's columns are weeks and its
/// rows are weekdays — a "last N days" grid whose columns are *not* weekdays reads as a
/// calendar while quietly not being one.
struct StatsView: View {
    @Environment(\.theme) private var theme
    @Query(sort: [SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]
    @State private var segment: Segment = .overview
    @State private var selectedHabit: Habit?
    @State private var overviewRange: Range = .d90
    /// One range per segment: the overview is a long-range density view, the habit dive goes
    /// down to a week.
    @State private var habitRange: Range = .d90

    enum Segment: String, CaseIterable, Identifiable {
        case overview, habits
        var id: String { rawValue }
    }

    enum Range: String, CaseIterable, Identifiable {
        case d7 = "7d", d30 = "30d", d90 = "90d", d180 = "180d", d365 = "365d", all = "all"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .d7: return 7
            case .d30: return 30
            case .d90: return 90
            case .d180: return 180
            case .d365: return 365
            case .all: return nil
            }
        }
    }

    /// Ranges offered per segment. The overview is a density view, so it starts at 30d — a
    /// shorter grid is too few week-columns to read — and stops at 180d, where the heatmap is
    /// still legible; a year would draw the same picture as 180d and read as a broken control.
    /// 30d matters most for a new user, whose 90d map is otherwise mostly pre-tracking grey.
    static let overviewRanges: [Range] = [.d30, .d90, .d180]
    static let habitRanges: [Range] = [.d7, .d30, .d90, .d365, .all]

    var body: some View {
        VStack(spacing: 0) {
            header
            segmentBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch segment {
                    case .overview:
                        OverviewPanel(habits: habits, range: $overviewRange)
                    case .habits:
                        HabitStatsPanel(habits: habits, selected: $selectedHabit, range: $habitRange)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(hex: theme.background))
        .onAppear {
            #if DEBUG
            // Simulator-only hook: `simctl` can't tap, so this is how the second segment gets
            // rendered for inspection. Mirrors DEBUG_TAB in RootView.
            if let raw = ProcessInfo.processInfo.environment["DEBUG_SEGMENT"],
               let match = Segment.allCases.first(where: { $0.rawValue == raw }) {
                segment = match
            }
            // The range bars are taps too, so ranges are reachable only this way. Their extremes
            // are where the heatmap's sizing maths is tightest (53 columns at 365d).
            if let raw = ProcessInfo.processInfo.environment["DEBUG_RANGE"],
               let match = Range.allCases.first(where: { $0.rawValue == raw }) {
                overviewRange = match
                habitRange = match
            }
            #endif
        }
    }

    private var segmentBar: some View {
        HStack(spacing: 6) {
            ForEach(Segment.allCases) { s in
                segmentTab(s)
            }
        }
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func segmentTab(_ s: Segment) -> some View {
        let isSelected: Bool = s == segment
        let tint: Color = isSelected ? theme.statsColor : Color(hex: theme.comment)
        let weight: Font.Weight = isSelected ? .bold : .regular
        return Button {
            segment = s
        } label: {
            Text(s.rawValue)
                .term(12, weight)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? theme.statsColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.rawValue) view")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var header: some View {
        VStack(spacing: 10) {
            PromptHeader(command: "stats", accent: theme.statsColor)
            Divider().overlay(Color(hex: theme.comment).opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Day windows

/// The whole weeks a range touches: Monday-start, ending with the week containing today.
/// Whole weeks are what let the heatmap align rows to weekdays.
enum DayWindow {
    /// A heatmap of one week per column stops being legible well before a year: 53 columns on a
    /// phone is a 3pt smudge and the weekday labels collide. So the *visual* is capped at about
    /// half a year and says which span it is showing, while the numbers beside it still cover
    /// the full range the user selected.
    static let maxWeeks = 27

    struct Window {
        let from: Date     // Monday of the first displayed week
        let to: Date       // today
        let start: Date    // first day inside the range — `from` unless the cap bit
        let weeks: Int     // columns actually drawn
        /// `last 90d`, or `last 27 weeks` when the cap shortened the visual.
        func label(_ range: StatsView.Range) -> String {
            weeks < (range.days ?? Int.max) / 7 + 1 ? "last \(weeks) weeks" : "last \(range.rawValue)"
        }
    }

    static func monday(of date: Date, calendar: Calendar = .current) -> Date {
        let wd = calendar.component(.weekday, from: date)   // 1 = Sun
        let offset = (wd + 5) % 7                          // days since Monday
        return calendar.date(byAdding: .day, value: -offset,
                             to: calendar.startOfDay(for: date))!
    }

    /// First day the range covers, before any display cap.
    static func rangeStart(range: StatsView.Range, habits: [Habit],
                           today: Date = Date(), calendar: Calendar = .current) -> Date {
        let end = calendar.startOfDay(for: today)
        guard let days = range.days else {
            // "all": from the oldest thing we know about.
            return habits.map { Achievements.firstTrackedDay($0) }.min() ?? end
        }
        return calendar.date(byAdding: .day, value: -(days - 1), to: end)!
    }

    static func display(range: StatsView.Range, habits: [Habit], today: Date = Date(),
                        calendar: Calendar = .current) -> Window {
        let end = calendar.startOfDay(for: today)
        var start = rangeStart(range: range, habits: habits, today: today, calendar: calendar)
        let capped = calendar.date(byAdding: .day, value: -(maxWeeks * 7 - 1), to: end)!
        if start < capped { start = capped }
        let from = monday(of: start, calendar: calendar)
        let weeks = (calendar.dateComponents([.day], from: from, to: end).day ?? 0) / 7 + 1
        return Window(from: from, to: end, start: start, weeks: weeks)
    }

    /// Every date in the grid, column by column, Monday first. Dates before `start` or after
    /// `to` are `nil` so the grid keeps its shape without inventing data.
    static func grid(from: Date, to: Date, start: Date, calendar: Calendar = .current) -> [[Date?]] {
        var columns: [[Date?]] = []
        var weekStart = from
        while weekStart <= to {
            var column: [Date?] = []
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                column.append(day >= start && day <= to ? day : nil)
            }
            columns.append(column)
            weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        }
        return columns
    }

    /// The grid's in-range days as a flat list.
    static func days(from: Date, to: Date, start: Date, calendar: Calendar = .current) -> [Date] {
        grid(from: from, to: to, start: start, calendar: calendar).flatMap { $0.compactMap { $0 } }
    }
}

// MARK: - Due-day accounting

/// Habit-day tallies — the one place a completion rate is defined.
///
/// A day is *due* when the habit was scheduled that weekday **and** was already tracked
/// (`Achievements.firstTrackedDay`). Both halves matter, and each was a bug before it lived
/// here: treating `createdAt` as the start reported 614% for seeded history, and counting raw
/// calendar days reported `8/64` for a habit ten days old. Completions logged on days the habit
/// wasn't scheduled are deliberately excluded from both sides — they're a bonus, not a fraction
/// of a day that was never due.
enum HabitDays {
    static func tally(habits: [Habit], days: [Date], calendar: Calendar = .current) -> (due: Int, done: Int) {
        var due = 0, done = 0
        for day in days {
            let weekday = calendar.component(.weekday, from: day)
            for habit in habits where habit.scheduleDays.contains(weekday)
                && Achievements.firstTrackedDay(habit) <= day {
                due += 1
                if habit.completion(on: day, calendar: calendar) != nil { done += 1 }
            }
        }
        return (due, done)
    }

    static func rate(_ tally: (due: Int, done: Int)) -> Double {
        tally.due > 0 ? Double(tally.done) / Double(tally.due) : 0
    }
}

// MARK: - Overview

private struct OverviewPanel: View {
    @Environment(\.theme) private var theme
    let habits: [Habit]
    @Binding var range: StatsView.Range

    /// The heatmap's window: capped to a legible number of columns.
    private var display: DayWindow.Window {
        DayWindow.display(range: range, habits: habits)
    }

    /// The range's own start, uncapped — what the tallies are measured over.
    private var rangeStart: Date {
        DayWindow.rangeStart(range: range, habits: habits)
    }

    var body: some View {
        let today = Date()
        let completions = habits.flatMap { $0.completions }
        let doneToday = habits.filter { $0.completion(on: today) != nil }.count
        let tally = HabitDays.tally(habits: habits, days: windowDays)
        let rate = HabitDays.rate(tally)

        return VStack(alignment: .leading, spacing: 16) {
            statGrid(today: doneToday, total: completions.count)
            TermSegmentBar(
                options: StatsView.overviewRanges.map { (id: $0.id, label: $0.rawValue) },
                selection: range.id,
                accent: theme.statsColor
            ) { id in
                range = StatsView.overviewRanges.first { $0.id == id } ?? .d90
            }
            heatmapCard
            weekdayCard
            HStack(spacing: 0) {
                Text(verbatim: "\(tally.done)/\(tally.due) habit-days")
                    .term(11)
                    .foregroundStyle(Color(hex: theme.comment))
                    .monospacedDigit()
                Spacer()
                Text(verbatim: "\(Int((rate * 100).rounded()))% over \(range.rawValue)")
                    .term(11, .semibold)
                    .foregroundStyle(theme.statsColor)
                    .monospacedDigit()
            }
            .padding(.top, 2)
        }
    }

    private var windowDays: [Date] {
        DayWindow.days(
            from: DayWindow.monday(of: rangeStart),
            to: Calendar.current.startOfDay(for: Date()),
            start: rangeStart
        )
    }

    /// Before anything was tracked, a day was neither kept nor missed — rendering those as
    /// "missed" would paint a wall of failure across the front of every long range.
    private var trackingStart: Date {
        habits.map { Achievements.firstTrackedDay($0) }.min()
            ?? Calendar.current.startOfDay(for: Date())
    }

    private func statGrid(today: Int, total: Int) -> some View {
        let completions = habits.flatMap { $0.completions }
        let currentStreak: Int = Streaks.overall(completions: completions)
        let best: Int = habits.map { Streaks.bestStreak($0) }.max() ?? 0
        let firstRow: [(String, String)] = [("[today]", "\(today)"), ("[streak]", "\(currentStreak)")]
        let secondRow: [(String, String)] = [("[best]", "\(best)"), ("[total]", "\(total)")]
        return VStack(spacing: 6) {
            statRow(firstRow)
            statRow(secondRow)
        }
    }

    private func statRow(_ cells: [(String, String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(cells, id: \.0) { pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.0).term(11).foregroundStyle(Color(hex: theme.comment))
                    Text(verbatim: pair.1).term(18, .bold).foregroundStyle(.white).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "// completions · \(display.label(range))")
                .term(11)
                .foregroundStyle(Color(hex: theme.comment))
            WeekHeatmap(
                window: display,
                ratio: { day in
                    guard day >= trackingStart else { return -1 }
                    return Streaks.dayRatio(day, habits: habits)
                },
                accent: theme.statsColor
            )
        }
        .padding(12)
        // Full width even when the grid is narrower than the card, so this box matches the
        // weekday card below it rather than shrinking to its content.
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
    }

    private var weekdayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// by weekday", size: 11)
            WeekdayBreakdown(habits: habits, window: display, accent: theme.statsColor)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Week-aligned heatmap

/// Weeks across, weekdays down — GitHub's layout, which is the only one where a column means
/// a week and a row means a weekday. Cell size follows the column count so the grid fills the
/// card at every range.
struct WeekHeatmap: View {
    @Environment(\.theme) private var theme
    let window: DayWindow.Window
    /// `nil` day → nothing was scheduled (a rest day); `0` → scheduled and missed.
    let ratio: (Date) -> Double
    let accent: Color
    var showLegend = true

    /// Monday-first single letters, matching the app's Mon-start weeks.
    private static let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]
    private let labelWidth: CGFloat = 12

    var body: some View {
        let columns = DayWindow.grid(from: window.from, to: window.to, start: window.start)
        // Sized from a budget rather than a measurement: the card holds ~318pt of content on a
        // 375pt screen and ~336pt on a 393pt one, so 300 leaves clearance on every device while
        // still filling the width at the ranges the overview offers (14+ columns). Measuring
        // instead would make a year's 53 columns overflow, since cells can't go below a legible
        // floor.
        let legendWidth: CGFloat = showLegend ? 30 : 0
        let gap: CGFloat = columns.count > 20 ? 1.5 : 3
        let grid = 300 - labelWidth - gap - 8 - legendWidth
        // The cap is really a height budget: seven 26pt rows plus gaps is ~200pt, which is as
        // tall as this card should get. Without it a one-column grid draws 44pt squares and
        // runs off the bottom of the screen (see the 7d week row, which handles that case).
        let step = (grid - gap * CGFloat(columns.count - 1)) / CGFloat(max(1, columns.count))
        let cell = min(26, max(2, step))

        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                ForEach(0..<7, id: \.self) { row in
                    Text(Self.weekdayLabels[row])
                        .term(8)
                        .foregroundStyle(Color(hex: theme.comment))
                        .frame(width: labelWidth, height: cell)
                }
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        cellView(column[row], size: cell)
                    }
                }
            }
            if showLegend {
                legend(cell: cell).padding(.leading, 5)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: Date?, size: CGFloat) -> some View {
        if let day {
            let r = ratio(day)
            // At a year's 53 columns a cell is ~3pt: a proportional radius would round it into
            // a dot, and a 1pt ring would be wider than the cell.
            let radius = max(0.5, size * 0.18)
            RoundedRectangle(cornerRadius: radius)
                .fill(fill(for: r))
                .frame(width: size, height: size)
                .overlay(
                    Calendar.current.isDateInToday(day) && size >= 8
                        ? RoundedRectangle(cornerRadius: radius)
                            .stroke(accent, lineWidth: 1) : nil
                )
        } else {
            // Outside the range: keep the shape, claim nothing.
            Color.clear.frame(width: size, height: size)
        }
    }

    private func fill(for r: Double) -> Color {
        if r < 0 { return Color(hex: theme.comment).opacity(0.12) }   // nothing scheduled
        if r == 0 { return Color(hex: theme.comment).opacity(0.25) }  // scheduled, missed
        return accent.opacity(0.25 + 0.75 * min(1, r))
    }

    private func legend(cell: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("more").term(8).foregroundStyle(Color(hex: theme.comment))
            ForEach([1.0, 0.6, 0.3, 0.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level == 0 ? Color(hex: theme.comment).opacity(0.25) : accent.opacity(0.25 + 0.75 * level))
                    .frame(width: cell * 0.7, height: cell * 0.7)
            }
            Text("less").term(8).foregroundStyle(Color(hex: theme.comment))
        }
    }
}

// MARK: - Weekday breakdown

/// Completion rate per weekday across the window. Answers the question a heatmap can't show
/// at a glance: *which* days you actually skip.
private struct WeekdayBreakdown: View {
    @Environment(\.theme) private var theme
    let habits: [Habit]
    let window: DayWindow.Window
    let accent: Color

    /// Monday-first, matching `WeekHeatmap`.
    private static let labels = ["M", "T", "W", "T", "F", "S", "S"]
    private static let weekdays = [2, 3, 4, 5, 6, 7, 1]

    private struct Row: Identifiable {
        let label: String
        let due: Int
        let done: Int
        var id: String { "\(label)-\(due)" }
        var rate: Double { HabitDays.rate((due: due, done: done)) }
    }

    private var rows: [Row] {
        let cal = Calendar.current
        let days = DayWindow.days(from: window.from, to: window.to, start: window.start)
        return Self.weekdays.enumerated().map { index, weekday in
            let matching = days.filter { cal.component(.weekday, from: $0) == weekday }
            let tally = HabitDays.tally(habits: habits, days: matching, calendar: cal)
            return Row(label: Self.labels[index], due: tally.due, done: tally.done)
        }
    }

    var body: some View {
        let rows = rows
        // The weakest weekday is the actionable one — flag it rather than making the reader
        // compare seven percentages.
        let worst = rows.filter { $0.due > 0 }.min { $0.rate < $1.rate }
        return VStack(spacing: 5) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.label)
                        .term(11, .semibold)
                        .foregroundStyle(Color(hex: theme.comment))
                        .frame(width: 10, alignment: .leading)
                    TermBar(fraction: row.rate, accent: accent, height: 6)
                    Text(verbatim: row.due > 0 ? "\(Int((row.rate * 100).rounded()))%" : "—")
                        .term(10)
                        .foregroundStyle(
                            row.due == 0 ? Color(hex: theme.comment)
                            : row.id == worst?.id ? Color(hex: "#FF9F45")
                            : .white
                        )
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.label): \(row.due > 0 ? "\(Int((row.rate * 100).rounded())) percent" : "no habits scheduled")")
            }
        }
    }
}

// MARK: - Per-habit deep dive (§4.2)

private struct HabitStatsPanel: View {
    @Environment(\.theme) private var theme
    let habits: [Habit]
    @Binding var selected: Habit?
    @Binding var range: StatsView.Range

    private var activeHabit: Habit? { selected ?? habits.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if habits.isEmpty {
                CommentText(text: "// no habits yet")
            } else {
                HabitChipBar(habits: habits, selected: activeHabit) { selected = $0 }
                TermSegmentBar(
                    options: StatsView.habitRanges.map { (id: $0.id, label: $0.rawValue) },
                    selection: range.id,
                    accent: theme.statsColor
                ) { id in
                    range = StatsView.habitRanges.first { $0.id == id } ?? .d90
                }
                if let habit = activeHabit {
                    SummaryCard(habit: habit)
                    CompletionsCard(habit: habit, range: range)
                    heatmapCard(habit)
                }            }
        }
    }

    private func heatmapCard(_ habit: Habit) -> some View {
        let window = DayWindow.display(range: range, habits: habits)
        let accent = Color(hex: habit.color.hex)
        // Seven days is a row, not a matrix: as whole-week columns the shortest range is one or
        // two slivers of 44pt squares running off the bottom of the screen.
        let isWeek = range == .d7
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "// \(habit.name) · \(isWeek ? "this week" : window.label(range))")
                .term(11)
                .foregroundStyle(Color(hex: theme.comment))
            if isWeek {
                HabitWeekRow(habit: habit, accent: accent)
            } else {
                WeekHeatmap(
                    window: window,
                    ratio: { day in
                        let wd = Calendar.current.component(.weekday, from: day)
                        // Off-schedule days and days before the habit existed are rest days, not
                        // misses — only a day that was actually due can be failed.
                        guard habit.scheduleDays.contains(wd),
                              day >= Achievements.firstTrackedDay(habit) else { return -1 }
                        return habit.completion(on: day) != nil ? 1 : 0
                    },
                    accent: accent,
                    showLegend: false
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
    }
}

/// One habit's current Mon–Sun week, as a row of cells — the shape that fits seven days.
private struct HabitWeekRow: View {
    @Environment(\.theme) private var theme
    let habit: Habit
    let accent: Color

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return HStack(spacing: 5) {
            ForEach(Array(Date().weekDates().enumerated()), id: \.offset) { index, day in
                VStack(spacing: 4) {
                    Text(Self.letters[index])
                        .term(9)
                        .foregroundStyle(Color(hex: theme.comment))
                    cell(for: day, calendar: cal, today: today)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func cell(for day: Date, calendar: Calendar, today: Date) -> some View {
        let isFuture = day > today
        let due = !isFuture && habit.scheduleDays.contains(calendar.component(.weekday, from: day))
            && day >= Achievements.firstTrackedDay(habit)
        let done = due && habit.completion(on: day) != nil
        let fill: Color = done ? accent
            : due ? Color(hex: theme.comment).opacity(0.28)
            : Color(hex: theme.comment).opacity(0.12)
        RoundedRectangle(cornerRadius: 5)
            .fill(isFuture ? Color.clear : fill)
            .frame(height: 38)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        calendar.isDateInToday(day) ? accent
                        : Color(hex: theme.comment).opacity(isFuture ? 0.18 : 0),
                        lineWidth: 1
                    )
            )
            .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)): \(done ? "done" : due ? "missed" : "not scheduled")")
    }
}

/// Terminal-styled habit selector, replacing a system menu — the app avoids system pickers
/// everywhere else (§5.1), and a menu can't show the habit's own colour.
private struct HabitChipBar: View {
    @Environment(\.theme) private var theme
    let habits: [Habit]
    let selected: Habit?
    let onSelect: (Habit) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(habits) { habit in
                    let isSelected = habit.id == selected?.id
                    let accent = Color(hex: habit.color.hex)
                    Button {
                        onSelect(habit)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: habit.icon)
                                .font(.system(size: 10, design: .monospaced))
                            Text(habit.name).term(12, isSelected ? .semibold : .regular)
                        }
                        .foregroundStyle(isSelected ? accent : Color(hex: theme.comment))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? accent.opacity(0.16) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    isSelected ? accent.opacity(0.6) : Color(hex: theme.comment).opacity(0.3),
                                    lineWidth: 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(habit.name)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
        // This one scrolls sideways, which is also how tabs are swiped — without the opt-out a
        // flick along the chip row would change tab as well as scroll.
        .tabSwipeDeadZone()
        .accessibilityIdentifier("habit-chips")
    }
}

private struct SummaryCard: View {
    @Environment(\.theme) private var theme
    let habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// summary", size: 11)
            row("mode", habit.type == .timed ? "timed (\(habit.targetLabel))" : "manual")
            row("schedule", scheduleLabel)
            row("streak", "\(Streaks.habitStreak(habit))")
            row("best", "\(Streaks.bestStreak(habit))")
            row("since", Achievements.firstTrackedDay(habit).formatted(date: .abbreviated, time: .omitted))
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The habit's real schedule — `daily` / `weekdays` / `weekends` / `M·W·F`. This used to
    /// be hardcoded to "daily", which was a lie for anything scheduled less often.
    private var scheduleLabel: String {
        let days = habit.scheduleDays
        if days.count == 7 { return "daily" }
        if days.isEmpty { return "unscheduled" }
        if days == [2, 3, 4, 5, 6] { return "weekdays" }
        if days == [1, 7] { return "weekends" }
        let names = ["", "S", "M", "T", "W", "T", "F", "S"]
        return [2, 3, 4, 5, 6, 7, 1].filter { days.contains($0) }.map { names[$0] }.joined(separator: "·")
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(key).term(12).foregroundStyle(Color(hex: theme.comment))
            Spacer()
            Text(value).term(12, .semibold).foregroundStyle(.white)
        }
    }
}

private struct CompletionsCard: View {
    @Environment(\.theme) private var theme
    let habit: Habit
    let range: StatsView.Range

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start: Date = {
            if let days = range.days {
                return cal.date(byAdding: .day, value: -(days - 1), to: today)!
            }
            return Achievements.firstTrackedDay(habit)
        }()
        // The denominator is days the habit was actually due — bounded by the range *and* by
        // when it started being tracked. Counting raw calendar days reported `8/64` for a habit
        // ten days old.
        let owed = HabitDays.tally(habits: [habit], days: windowDays(start: start, to: today, calendar: cal))
        let rate = HabitDays.rate(owed)
        let logged = habit.completions.filter { $0.day >= start }.count

        return VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// completions", size: 11)
            row("logged", "\(logged)")
            row("rate", "\(Int((rate * 100).rounded()))%")
            row("days", "\(owed.done)/\(owed.due)")
            TermBar(fraction: rate, accent: theme.statsColor)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private func windowDays(start: Date, to end: Date, calendar: Calendar) -> [Date] {
        guard start <= end else { return [] }
        var days: [Date] = []
        var day = start
        while day <= end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(key).term(12).foregroundStyle(Color(hex: theme.comment))
            Spacer()
            Text(value).term(12, .semibold).foregroundStyle(.white).monospacedDigit()
        }
    }
}
