import SwiftUI
import SwiftData

/// Root: tab bar habits / stats / profile (§6), theme + font-scale injected app-wide.
struct RootView: View {
    @ObservedObject private var store = ThemeStore.shared
    @AppStorage(SettingsKey.themeId) private var themeId = TerminalTheme.builtin()[0].id
    @AppStorage(SettingsKey.textSize) private var textSize = 0
    @State private var tab = 0
#if DEBUG
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Habit.createdAt)]) private var debugHabits: [Habit]
#endif

    var body: some View {
        TabView(selection: $tab) {
            HabitsView()
                .tabItem { Label("habits", systemImage: "checklist") }.tag(0)
            StatsView()
                .tabItem { Label("stats", systemImage: "chart.bar") }.tag(1)
            ProfileView()
                .tabItem { Label("profile", systemImage: "person.crop.circle") }.tag(2)
        }
        .tint(activeTheme.habitsColor)
        .environment(\.theme, activeTheme)
        .environment(\.fontScale, TextScale.multiplier(for: textSize))
        .onOpenURL { url in
            // simctl driving hooks (debug builds only)
            #if DEBUG
            switch url.host {
            case "tab-stats": tab = 1
            case "tab-profile": tab = 2
            case "tab-habits": tab = 0
            case "start-timer": debugStartTimer()
            default: break
            }
            #endif
        }
        .onAppear {
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["DEBUG_TAB"] == "stats" { tab = 1 }
            if env["DEBUG_TAB"] == "profile" { tab = 2 }
            if env["DEBUG_AUTO_TIMER"] == "1" {
                if let h = debugHabits.first(where: { $0.type == .timed }), h.startedAt == nil {
                    h.startedAt = Date()
                    try? modelContext.save()
                }
            }
            #endif
            // Live activities are process-bound: re-attach for any timer that survived a relaunch.
            for h in debugHabits where h.type == .timed && h.startedAt != nil {
                LiveActivityController.shared.start(habit: h, target: h.targetSeconds)
            }
        }
    }

    /// Active theme: resolves from the store on every render, so color edits apply live.
    private var activeTheme: TerminalTheme {
        store.byId(themeId)
    }

#if DEBUG
    private func debugStartTimer() {
        if let h = debugHabits.first(where: { $0.type == .timed }), h.startedAt == nil {
            h.startedAt = Date()
            LiveActivityController.shared.start(habit: h, target: h.targetSeconds)
            try? modelContext.save()
        }
    }
#endif
}

// MARK: - Habits tab (home) — §4.1

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Query(sort: [SortDescriptor(\Routine.sortIndex)]) private var routines: [Routine]
    @State private var selectedDay: Date = Date()
    @State private var showAddHabit = false
    @State private var ticker: Date = Date() // drives live timer text

    private let taglines = [
        "// discipline is a compile-time guarantee",
        "// ship small, ship daily",
        "// zero warnings, one habit at a time",
        "// consistency > intensity",
        "// refactor yourself, one commit a day",
    ]

    private var allHabits: [Habit] { routines.flatMap { $0.habits } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let dayIndex = Calendar.current.ordinality(of: .day, in: .year, for: selectedDay) ?? 1
                    CommentText(text: taglines[dayIndex % taglines.count])
                    dateRow
                    streakRow
                    WeekStrip(
                        week: selectedDay.weekDates(),
                        selected: selectedDay,
                        onSelect: { selectedDay = $0 },
                        habits: allHabits
                    )
                    routineList
                    Button {
                        showAddHabit = true
                    } label: {
                        CommentText(text: "+ add habit", size: 13)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(hex: theme.background))
        .sheet(isPresented: $showAddHabit) { AddHabitView() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { ticker = $0 }
    }

    private var header: some View {
        VStack(spacing: 10) {
            PromptHeader(command: "daily", accent: theme.habitsColor)
            Divider().overlay(Color(hex: theme.comment).opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var dateRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: theme.comment))
            Text(selectedDay.formatted(date: .complete, time: .omitted))
                .term(13)
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private var streakRow: some View {
        let streak = Streaks.overall(completions: allHabits.flatMap { $0.completions })
        return HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: "#FF9F45"))
            Text("\(streak)").term(13, .semibold).monospacedDigit()
            Text("*").term(13).foregroundStyle(Color(hex: theme.comment))
            Image(systemName: "shield")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: theme.comment))
            Text("0").term(13, .semibold).monospacedDigit()
            Spacer()
        }
    }

    @ViewBuilder
    private var routineList: some View {
        if routines.isEmpty {
            CommentText(text: "// no routines yet — tap + add habit")
        } else {
            ForEach(routines) { routine in
                RoutineSection(routine: routine, selectedDay: selectedDay, ticker: ticker)
            }
        }
    }
}

// MARK: - Collapsible routine section

struct RoutineSection: View {
    let routine: Routine
    let selectedDay: Date
    let ticker: Date
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.moveCompletedToBottom) private var moveBottom = false
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 6) {
                ForEach(sortedHabits) { habit in
                    HabitRow(habit: habit, day: selectedDay, ticker: ticker)
                }
            }
            .padding(.top, 2)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: routine.icon)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.habitsColor)
                Text(routine.name).term(14, .semibold).foregroundStyle(.white)
                CommentText(text: routine.subtitle)
                Spacer()
                Text("[\(done)/\(total)]")
                    .term(11, .semibold)
                    .foregroundStyle(done == total && total > 0 ? theme.habitsColor : Color(hex: "#6E6E73"))
                    .monospacedDigit()
            }
        }
        .tint(Color(hex: "#6E6E73"))
    }

    private var habitsForDay: [Habit] {
        routine.habits.filter { $0.scheduleDays.contains(Streaks.weekdayIndex(selectedDay)) }
    }
    private var sortedHabits: [Habit] {
        var list = habitsForDay.sorted { $0.sortIndex < $1.sortIndex }
        if moveBottom {
            list.sort { ($0.completion(on: selectedDay) != nil ? 1 : 0) < ($1.completion(on: selectedDay) != nil ? 1 : 0) }
        }
        return list
    }
    private var total: Int { habitsForDay.count }
    private var done: Int { habitsForDay.filter { $0.completion(on: selectedDay) != nil }.count }
}

// MARK: - Habit row

struct HabitRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.crossOutCompleted) private var crossOut = true
    let habit: Habit
    let day: Date
    let ticker: Date
    @State private var showEdit = false

    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDate(day, inSameDayAs: Date()) }
    private var completion: Completion? { habit.completion(on: day) }
    private var streak: Int { Streaks.habitStreak(habit) }

    var body: some View {
        HStack(spacing: 10) {
            Button { toggle() } label: {
                BracketCheckbox(checked: completion != nil, color: color)
            }
            .buttonStyle(.plain)

            Image(systemName: habit.icon)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(habit.name)
                    .term(13)
                    .foregroundStyle(.white)
                    .strikethrough(completion != nil && crossOut)
                if !habit.comment.isEmpty {
                    CommentText(text: habit.comment)
                }
            }

            Spacer(minLength: 8)

            // per-habit streak
            if streak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(hex: "#FF9F45"))
                    Text("\(streak)").term(11).monospacedDigit()
                }
            }

            statusMeta
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                showEdit = true
            } label: {
                Label("edit habit", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                delete()
            } label: {
                Label("delete habit", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEdit) {
            AddHabitView(habit: habit)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.name), \(completion != nil ? "completed" : "not completed")")
        .accessibilityHint("Double tap to toggle")
    }

    private func delete() {
        if habit.startedAt != nil {
            LiveActivityController.shared.stop(done: false)
        }
        for c in habit.completions { modelContext.delete(c) }
        modelContext.delete(habit)
        try? modelContext.save()
    }

    @ViewBuilder
    private var statusMeta: some View {
        if let c = completion {
            if isToday {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(hex: theme.comment))
                    Text(c.completedAt.formatted(date: .omitted, time: .shortened))
                        .term(10)
                        .foregroundStyle(Color(hex: theme.comment))
                }
            } else {
                Text("✓").term(11).foregroundStyle(color.opacity(0.6))
            }
        } else if habit.type == .timed, let started = habit.startedAt, isToday {
            // live timer: ⏱ 00:12:41 / 10min
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.habitsColor)
                Text(habit.formattedElapsed(since: started, now: ticker)).term(10, .semibold).monospacedDigit()
                Text("/").term(10).foregroundStyle(Color(hex: theme.comment))
                Text(habit.targetLabel.replacingOccurrences(of: "// ", with: "")).term(10).foregroundStyle(Color(hex: theme.comment))
            }
        }
    }

    private var color: Color { Color(hex: habit.color.hex) }

    private func toggle() {
        let doneDay = cal.startOfDay(for: day)
        if let existing = habit.completion(on: day) {
            modelContext.delete(existing)
            habit.completions.removeAll { $0 == existing }
            habit.startedAt = nil
            LiveActivityController.shared.stop(done: false)
        } else if habit.type == .timed, isToday {
            if habit.startedAt == nil {
                // start timer + Dynamic Island live activity
                habit.startedAt = Date()
                LiveActivityController.shared.start(habit: habit, target: habit.targetSeconds)
            } else {
                // stop timer → record elapsed as the completion value
                let elapsed = Date().timeIntervalSince(habit.startedAt!)
                habit.startedAt = nil
                LiveActivityController.shared.stop(done: true)
                let c = Completion(day: doneDay, completedAt: Date(), value: elapsed)
                c.habit = habit
                modelContext.insert(c)
            }
        } else {
            let c = Completion(day: doneDay, completedAt: Date(), value: 1)
            c.habit = habit
            modelContext.insert(c)
        }
        try? modelContext.save()
    }
}