import SwiftUI
import SwiftData

/// Stats tab — MVP per PRD §10: overview heatmap + per-habit deep dive.
/// (Month/Week chart views are v2 scope.)
struct StatsView: View {
    @Environment(\.theme) private var theme
    @Query(sort: [SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]
    @State private var segment: Segment = .overview
    @State private var selectedHabit: Habit?

    enum Segment: String, CaseIterable, Identifiable {
        case overview, habits
        var id: String { rawValue }
    }

    enum Range: String, CaseIterable, Identifiable {
        case d7 = "7d", d30 = "30d", d90 = "90d", d365 = "365d", all = "all"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .d7: return 7
            case .d30: return 30
            case .d90: return 90
            case .d365: return 365
            case .all: return nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            segmentBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch segment {
                    case .overview: OverviewPanel(habits: habits)
                    case .habits: HabitStatsPanel(habits: habits, selected: $selectedHabit)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(hex: theme.background))
    }

    /// Terminal-style secondary nav (§4.2) — custom control, tinted per stats accent.
    private var segmentBar: some View {
        HStack(spacing: 6) {
            ForEach(Segment.allCases) { s in
                Button {
                    segment = s
                } label: {
                    Text(s.rawValue)
                        .term(12, segment == s ? .bold : .regular)
                        .foregroundStyle(segment == s ? theme.statsColor : Color(hex: theme.comment))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(segment == s ? theme.statsColor.opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.rawValue) view")
            }
        }
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.top, 10)
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

// MARK: - Overview: aggregate numbers + 30-day heatmap

private struct OverviewPanel: View {
    @Environment(\.theme) private var theme
    let habits: [Habit]

    var body: some View {
        let completions = habits.flatMap { $0.completions }
        let today = Date()
        let cal = Calendar.current
        let doneToday = habits.filter { $0.completion(on: today) != nil }.count
        let streak = Streaks.overall(completions: completions)
        let last30 = completions.filter { c in
            guard let d = cal.date(byAdding: .day, value: -30, to: today) else { return false }
            return c.day >= d
        }.count

        return VStack(alignment: .leading, spacing: 16) {
            statGrid(today: doneToday, streak: streak, last30: last30, total: completions.count)
            Heatmap(habits: habits)
            CommentText(text: "// month & week chart views ship in v2")
        }
    }

    private func statGrid(today: Int, streak: Int, last30: Int, total: Int) -> some View {
        let cols: [[(String, String)]] = [
            [("[today]", "\(today)"), ("[streak]", "\(streak)")],
            [("[30d]", "\(last30)"), ("[total]", "\(total)")],
        ]
        return VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(cols[r], id: \.0) { pair in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pair.0).term(11).foregroundStyle(Color(hex: theme.comment))
                            Text(pair.1).term(18, .bold).foregroundStyle(.white).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// GitHub-style square heatmap of the last 5 weeks, colored by daily completion ratio.
private struct Heatmap: View {
    @Environment(\.theme) private var theme
    let habits: [Habit]

    var body: some View {
        let cal = Calendar.current
        let days = (0..<35).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }.reversed()
        VStack(alignment: .leading, spacing: 6) {
            CommentText(text: "// completions · last 5 weeks", size: 11)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 3), count: 7), spacing: 3) {
                ForEach(days, id: \.self) { day in
                    let ratio = Streaks.dayRatio(day, habits: habits)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ratio <= 0 ? Color(hex: theme.comment).opacity(0.25) : theme.statsColor.opacity(0.25 + 0.75 * max(0, ratio)))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            cal.isDateInToday(day) ?
                                RoundedRectangle(cornerRadius: 3).stroke(theme.statsColor, lineWidth: 1) : nil
                        )
                }
            }
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Per-habit deep dive (§4.2)

private struct HabitStatsPanel: View {
    @Environment(\.theme) private var theme
    let habits: [Habit]
    @Binding var selected: Habit?
    @State private var range: StatsView.Range = .d30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: habitSelection) {
                ForEach(habits) { h in
                    Text(h.name).term(12).tag(h)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(hex: theme.comment))
                    .allowsHitTesting(false)
            }

            TermSegmentBar(
                options: StatsView.Range.allCases.map { (id: $0.id, label: $0.rawValue) },
                selection: range.id,
                accent: theme.statsColor
            ) { selectedId in
                range = StatsView.Range.allCases.first { $0.id == selectedId } ?? .d30
            }

            if let habit = activeHabit {
                SummaryCard(habit: habit)
                CompletionsCard(habit: habit, range: range)
            } else {
                CommentText(text: "// no habits yet")
            }
        }
    }

    private var habitSelection: Binding<Habit?> {
        Binding(
            get: { selected ?? habits.first },
            set: { selected = $0 }
        )
    }
    private var activeHabit: Habit? { selected ?? habits.first }
}

private struct SummaryCard: View {
    @Environment(\.theme) private var theme
    let habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// summary", size: 11)
            row("mode", habit.type == .timed ? "timed (\(habit.targetLabel.replacingOccurrences(of: "// ", with: "")))" : "manual")
            row("schedule", "daily")
            row("streak", "\(Streaks.habitStreak(habit))")
            row("best", "\(Streaks.bestStreak(habit))")
            row("tracked", "\(habit.completions.count)d")
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let window: (from: Date, days: Int?) = {
            if let d = range.days {
                return (cal.date(byAdding: .day, value: -d, to: cal.startOfDay(for: Date()))!, d)
            }
            return (habit.createdAt, nil)
        }()
        let inRange = habit.completions.filter { $0.day >= window.from }
        let daysTracked = window.days ?? max(1, cal.dateComponents([.day], from: window.from, to: Date()).day ?? 1)
        let rate = daysTracked > 0 ? Double(inRange.count) / Double(daysTracked) : 0

        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// completions", size: 11)
            row("completions", "\(inRange.count)")
            row("rate", String(format: "%.0f%%", rate * 100))
            row("days", "\(inRange.count)/\(daysTracked)")
            // bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: theme.comment).opacity(0.25))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.statsColor)
                        .frame(width: geo.size.width * min(1, rate))
                }
            }
            .frame(height: 5)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(key).term(12).foregroundStyle(Color(hex: theme.comment))
            Spacer()
            Text(value).term(12, .semibold).foregroundStyle(.white).monospacedDigit()
        }
    }
}