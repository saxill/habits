import SwiftUI
import SwiftData

/// Root: tab bar habits / stats / profile (§6), theme + font-scale injected app-wide.
struct RootView: View {
    @ObservedObject private var store = ThemeStore.shared
    @AppStorage(SettingsKey.themeId) private var themeId = TerminalTheme.builtin()[0].id
    @AppStorage(SettingsKey.textSize) private var textSize = 0
    @State private var tab = 0
    /// Frames that own a horizontal drag of their own — see `TabSwipeDeadZones`.
    @State private var swipeDeadZones: [CGRect] = []
    /// 1 when the current tab has settled, 0 on the frame a new one arrives. Owned here rather
    /// than by each page: this view is always installed, so it always sees the change.
    @State private var arrivePhase: Double = 1
    @State private var arriveDirection: CGFloat = 1
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
#if DEBUG
    @Query(sort: [SortDescriptor(\Habit.createdAt)]) private var debugHabits: [Habit]
    /// Held so the tab bench keeps stepping; a released timer would stop after the first tick.
    @State private var benchTimer: Timer?
    @State private var benchForward = true
#endif

    var body: some View {
        TabView(selection: tabSelection) {
            TabPage(index: 0, phase: arrivePhase, direction: arriveDirection) {
                HabitsView()
            }
            .tabItem { Label("habits", systemImage: "checklist") }.tag(0)
            TabPage(index: 1, phase: arrivePhase, direction: arriveDirection) {
                StatsView()
            }
            .tabItem { Label("stats", systemImage: "chart.bar") }.tag(1)
            TabPage(index: 2, phase: arrivePhase, direction: arriveDirection) {
                ProfileView()
            }
            .tabItem { Label("profile", systemImage: "person.crop.circle") }.tag(2)
        }
        .tint(activeTheme.habitsColor)
        .environment(\.theme, activeTheme)
        .environment(\.fontScale, TextScale.multiplier(for: textSize))
        // Simultaneous rather than plain: the tabs are all scroll views, and a
        // default-priority drag on an ancestor loses the touch to them outright.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onEnded { value in
                    // A pushed screen owns its own sideways gesture, and the tab strip is not
                    // what the user is looking at while it is up.
                    guard NavRouter.shared.path.isEmpty,
                          !swipeDeadZones.contains(where: { $0.contains(value.startLocation) })
                    else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > TabSwipe.threshold,
                          abs(dx) > abs(dy) * TabSwipe.dominance
                    else { return }
                    step(dx < 0 ? 1 : -1)
                }
        )
        .onPreferenceChange(TabSwipeDeadZones.self) { swipeDeadZones = $0 }
        .onOpenURL { url in
            // widget taps land on the habits tab
            if url.host == "open" { select(0) }
            // simctl driving hooks (debug builds only)
            #if DEBUG
            switch url.host {
            case "tab-stats": select(1)
            case "tab-profile": select(2)
            case "tab-habits": select(0)
            case "screen-achievements":
                select(2)
                NavRouter.shared.openAchievements()
            case "start-timer": debugStartTimer()
            default: break
            }
            #endif
        }
        .onAppear {
            #if DEBUG
            // A cold launch never *changes* scenePhase, so the activation hook below doesn't
            // fire and a staged command would sit unread until the app was backgrounded and
            // brought back. Consuming here too means one launch is one run.
            runDebugCommands()
            let env = ProcessInfo.processInfo.environment
            if env["DEBUG_TAB"] == "stats" { select(1) }
            if env["DEBUG_TAB"] == "profile" { select(2) }
            // A launched-app hook rather than a staged file: XCUITest hands the app its
            // environment at launch, which is the only way a UI test can reach a pushed screen.
            if env["DEBUG_SCREEN"] == "achievements" {
                select(2)
                NavRouter.shared.openAchievements()
            }
            if env["DEBUG_AUTO_TIMER"] == "1" {
                if let h = runningTimedHabits().first, h.startedAt == nil {
                    h.startTimer()
                    try? modelContext.save()
                }
            }
            // Steps the tabs on a slow timer, from inside the app.
            //
            // This exists because the transition could not be measured any other way: driving
            // the same change from a XCUITest swipe keeps the main thread saturated while the
            // touch is delivered, and a state write made there is committed late enough that
            // SwiftUI can drop it — the app then never draws the start of the entrance, and the
            // measurement says "no animation" whether or not one exists in a human's hands.
            // An app-driven timer has an idle main thread, so it measures the real thing.
            if env["DEBUG_TAB_BENCH"] == "1" {
                benchTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
                    // Bounces 0→1→2→1→0 rather than wrapping, so every step is a real
                    // one-tab move and the clamp is never what is being measured.
                    Task { @MainActor in
                        if tab >= 2 { benchForward = false }
                        if tab <= 0 { benchForward = true }
                        step(benchForward ? 1 : -1)
                    }
                }
            }
            #endif
            // Live activities are process-bound: re-attach for any timer that survived a relaunch.
            for h in runningTimedHabits() where h.startedAt != nil {
                LiveActivityController.shared.start(habit: h, target: h.targetSeconds)
            }
            SnapshotPublisher.publish(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            // keep the shared widget snapshot current across launches/foregrounds
            if phase == .active || phase == .background {
                #if DEBUG
                // On activation, not just first appear: devicectl can't cold-launch a
                // running app, so a foreground is how a staged command gets picked up.
                if phase == .active { runDebugCommands() }
                #endif
                // The habit reminders are scheduled a week at a time rather than as repeating
                // triggers, so the window is rolled forward every time the app comes up — this
                // is what keeps a reminder set today still arriving next week.
                if phase == .active {
                    HabitReminders.sync()
                    WaterReminders.sync()
                }
                SnapshotPublisher.publish(context: modelContext)
            }
        }
    }

    /// Every write to the selected tab goes through here, so the direction of the transition is
    /// decided in one place — the swipe, the bar, a URL and a debug hook all land on it.
    ///
    /// The reset is made part of the *same* transaction as the switch on purpose: setting the
    /// phase afterwards from `onChange` looks equivalent and is not, because the arriving tab has
    /// no previous value for `onChange` to fire against.
    ///
    /// Not yet verified on screen, and worth saying plainly. A frame-by-frame luminance scan of a
    /// screen recording never found a dimmed frame — and a mutation check (the phase applied vs
    /// neutered) showed `TabView` produces the same multi-frame ramp either way, so the scan
    /// cannot tell this entrance apart from the container's own switch. Until something can, this
    /// is code that compiles and reads correctly, not an effect anyone has seen.
    private var tabSelection: Binding<Int> {
        Binding(get: { tab }, set: { select($0) })
    }

    private func select(_ index: Int) {
        guard index != tab else { return }
        arriveDirection = index > tab ? 1 : -1
        arrivePhase = 0
        tab = index
        // The frame above draws the arriving page at the start of its entrance; this animates it
        // from there. Two frames of daylight, not a runloop hop: `DispatchQueue.main.async`
        // still lands before the next draw, which commits both states in one render and drops
        // the start of the entrance.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.easeOut(duration: TabTransitions.duration)) { arrivePhase = 1 }
        }
    }

    /// One tab along the strip. Clamped rather than wrapped: the tabs are a left-to-right
    /// list, so swiping past the first or last one should do nothing, not jump to the far end.
    /// (And not select a tab that does not exist — `select` takes any index it is given.)
    private func step(_ delta: Int) {
        let next = tab + delta
        guard (0..<3).contains(next) else { return }
        select(next)
    }

#if DEBUG
    /// Test hooks driven by files dropped into the app group — `devicectl` doesn't deliver
    /// environment variables to the app, but it can write into the shared container.
    private func runDebugCommands() {
        // Wipes one day's completions — every tick, every timed value and every glass tally — so a
        // day can be started over. Body is an optional `yyyy-MM-dd`; empty means today.
        //
        // The same code the profile screen's reset button runs, so a day cleared from here and a
        // day cleared by a thumb cannot drift apart. Each dropped completion goes to the log
        // before it goes, so the day can be put back by hand either way.
        if let raw = HabitsDebugLog.consumeCommand("cmd.reset-day") {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            let day = raw.isEmpty ? Date() : (formatter.date(from: raw) ?? Date())
            let dropped = DayReset.reset(day: day, context: modelContext)
            HabitsDebugLog.append("dbg: reset \(dropped.count) completions")
            SnapshotPublisher.publish(context: modelContext)
            HabitReminders.sync()
            WaterReminders.sync()
        }
        // Pushes the achievements screen without a finger on the tab bar. Also the only way to
        // exercise the pushed screen's own render path on-device.
        if HabitsDebugLog.consumeCommand("cmd.open-achievements") != nil {
            select(2)
            NavRouter.shared.openAchievements()
            HabitsDebugLog.append("dbg: opening achievements")
        }
        if let raw = HabitsDebugLog.consumeCommand("cmd.start-timer") {
            debugStartTimer(named: raw.isEmpty ? nil : raw)
        }
        if let raw = HabitsDebugLog.consumeCommand("cmd.toggle"), let id = UUID(uuidString: raw) {
            PendingToggleQueue.set(habitId: id, day: Calendar.current.startOfDay(for: Date()), done: true)
        }
        if let raw = HabitsDebugLog.consumeCommand("cmd.toggle-off"), let id = UUID(uuidString: raw) {
            PendingToggleQueue.set(habitId: id, day: Calendar.current.startOfDay(for: Date()), done: false)
        }
        // Invokes the live activity's real ✓ intent in this process, so the test exercises the
        // button's own code path rather than a hand-rolled replay of it — an earlier replay
        // published before ending, which let the orphan sweep eat the completion card and made
        // a working button look broken.
        if HabitsDebugLog.consumeCommand("cmd.simulate-log-button") != nil {
            if let habit = runningTimedHabits().first(where: { $0.startedAt != nil }) {
                Task { _ = try? await LogTimerIntent(habitId: habit.id.uuidString).perform() }
            }
        }
        // Same for the pause key; takes an optional habit name so a second running timer can
        // be driven too. The pause intent is what the real key runs.
        if let raw = HabitsDebugLog.consumeCommand("cmd.simulate-pause") {
            let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
            let paused = parts.first != "off"
            let named = parts.count > 1 ? parts[1] : nil
            let target = runningTimedHabits().first {
                $0.startedAt != nil && (named == nil || $0.name == named)
            }
            if let habit = target {
                let id = habit.id.uuidString
                Task { _ = try? await PauseTimerIntent(habitId: id, paused: paused).perform() }
            }
        }
        // Discards a running timer without logging it — the lock screen's ✕ key, run through the
        // real intent so the queue, the activity teardown and the write-through all match a tap.
        // Body is a habit name, or empty for the first running timed habit.
        if let raw = HabitsDebugLog.consumeCommand("cmd.stop-timer") {
            let picked: Habit? = raw.isEmpty
                ? runningTimedHabits().first { $0.startedAt != nil }
                : debugHabits.first { $0.name == raw }
            if let habit = picked, habit.startedAt != nil {
                let id = habit.id.uuidString
                HabitsDebugLog.append("dbg: discarding timer for \(habit.name)")
                Task { _ = try? await DiscardTimerIntent(habitId: id).perform() }
            } else {
                HabitsDebugLog.append("dbg: no running timer to discard (want \(raw.isEmpty ? "any" : raw))")
            }
        }
        // Renames a habit, to prove the activity picks up display changes mid-timer — the
        // attributes are frozen at start, so this only works via the state copy.
        // Body is "new name" (first running timed habit) or "old|new" to match by name,
        // running or not — the latter so a test rename can be undone.
        if let raw = HabitsDebugLog.consumeCommand("cmd.rename-timer") {
            let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
            let picked: Habit? = parts.count > 1
                ? debugHabits.first { $0.name == parts[0] }
                : runningTimedHabits().first { $0.startedAt != nil }
            if let habit = picked {
                let newName = parts.count > 1 ? parts[1] : (raw.isEmpty ? habit.name + "*" : raw)
                let oldName = habit.name
                habit.name = newName
                try? modelContext.save()
                SnapshotPublisher.publish(context: modelContext)
                HabitsDebugLog.append("dbg: renamed \(oldName) -> \(habit.name)")
            }
        }
    }
#endif

    /// Timed habits currently in the store (used for live-activity re-attach).
    private func runningTimedHabits() -> [Habit] {
        let all = (try? modelContext.fetch(FetchDescriptor<Habit>())) ?? []
        return all.filter { $0.type == .timed }
    }

    /// Active theme: resolves from the store on every render, so color edits apply live.
    private var activeTheme: TerminalTheme {
        store.byId(themeId)
    }

#if DEBUG
    /// Starts a timer on a timed habit that isn't already running, optionally by name.
    /// Reports what it did to the app-group log — an unlogged no-op here is indistinguishable
    /// from a bug in the thing being tested.
    private func debugStartTimer(named name: String? = nil) {
        let idle = debugHabits.filter { $0.type == .timed && $0.startedAt == nil }
        let picked = name.flatMap { n in idle.first { $0.name == n } } ?? idle.first
        guard let h = picked else {
            HabitsDebugLog.append("dbg: no idle timed habit to start (want \(name ?? "any"))")
            return
        }
        h.startTimer()
        LiveActivityController.shared.start(habit: h, target: h.targetSeconds)
        try? modelContext.save()
        HabitsDebugLog.append("dbg: started timer for \(h.name)")
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
        HStack(spacing: 8) {
            // The row content is one combined accessibility element; the glass button sits
            // outside it. Nesting a button inside the combine is what would make it
            // unreachable by VoiceOver, so the boundary moves rather than the button.
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

                // A reminder set on this habit. Shown whether or not the day is done, because it is
                // reporting a setting rather than a state — and shown as the time, not just a bell,
                // since a bell alone leaves "when?" to be found by opening the habit.
                if let minutes = habit.reminderMinutesFromMidnight {
                    HStack(spacing: 2) {
                        Image(systemName: "bell")
                            .font(.system(size: 9, design: .monospaced))
                        Text(String(format: "%02d:%02d", minutes / 60, minutes % 60)).term(10)
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color(hex: theme.comment))
                }

                // Water is measured in glasses, not a tick, so the row reports the tally beside
                // the streak. The `[+]` that changes it is outside this combined element, below.
                if WaterReminders.isWaterHabit(habit) {
                    Text(verbatim: "\(Int(completion?.value ?? 0))/\(WaterReminders.goal)")
                        .term(10)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: theme.comment))
                }

                statusMeta
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint("Double tap to toggle")

            if WaterReminders.isWaterHabit(habit) { logGlassButton }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if WaterReminders.isWaterHabit(habit) {
                Button {
                    WaterReminders.logGlass(habitId: habit.id, day: day)
                } label: {
                    Label("log a glass", systemImage: "drop.fill")
                }
            }
            if habit.startedAt != nil {
                Button {
                    togglePause()
                } label: {
                    Label(habit.isPaused ? "resume timer" : "pause timer",
                          systemImage: habit.isPaused ? "play.fill" : "pause.fill")
                }
            }
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
    }

    /// Logs a glass without opening anything. Its own button, outside the row's combined
    /// accessibility element, so it stays reachable — the same action is on the context menu too.
    private var logGlassButton: some View {
        Button {
            WaterReminders.logGlass(habitId: habit.id, day: day)
        } label: {
            Text("[+]")
                .term(12, .semibold)
                .foregroundStyle(color)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("log a glass of water")
    }

    /// The reminder and the glass tally are included because they are the two things on the row a
    /// screen reader cannot reach otherwise: everything else is reachable by swiping to the habit
    /// itself. The tally especially — the row's own text is merged into this one label, so a
    /// tally left out here is a tally nobody hears.
    private var accessibilityDescription: String {
        var parts = [habit.name, completion != nil ? "completed" : "not completed"]
        if WaterReminders.isWaterHabit(habit) {
            parts.append("\(Int(completion?.value ?? 0)) of \(WaterReminders.goal) glasses")
        }
        if let minutes = habit.reminderMinutesFromMidnight {
            parts.append(String(format: "reminder %02d:%02d", minutes / 60, minutes % 60))
        }
        return parts.joined(separator: ", ")
    }

    private func delete() {
        if habit.startedAt != nil {
            LiveActivityController.shared.stop(habitId: habit.id, done: false)
        }
        for c in habit.completions { modelContext.delete(c) }
        modelContext.delete(habit)
        try? modelContext.save()
        // A deleted habit must stop buzzing. Its requests carry the id, so they can be pulled
        // without disturbing anyone else's schedule.
        HabitReminders.cancel(habitId: habit.id)
        SnapshotPublisher.publish(context: modelContext)
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
        } else if habit.type == .timed, habit.startedAt != nil, isToday {
            // live timer: ⏱ 00:12:41 / 10min — or a paused marker
            HStack(spacing: 3) {
                Image(systemName: habit.isPaused ? "pause.fill" : "timer")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(habit.isPaused ? Color(hex: theme.comment) : theme.habitsColor)
                Text(habit.formattedElapsed(now: ticker)).term(10, .semibold).monospacedDigit()
                Text("/").term(10).foregroundStyle(Color(hex: theme.comment))
                Text(habit.targetLabel.replacingOccurrences(of: "// ", with: "")).term(10).foregroundStyle(Color(hex: theme.comment))
                if habit.isPaused {
                    Text("paused").term(10).foregroundStyle(Color(hex: theme.comment))
                }
            }
        }
    }

    private var color: Color { Color(hex: habit.color.hex) }

    private func toggle() {
        // The whole mutation is animated, not just the checkbox: the strike-through, the
        // streak count beside it, and — when "move completed to bottom" is on — the row's jump
        // down the list all come off this one change, and they should read as one movement.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            mutate()
        }
        try? modelContext.save()
        SnapshotPublisher.publish(context: modelContext)
        // Ticking a habit off should silence its reminder for today, and un-ticking it should
        // bring it back — the scheduler drops occurrences for days already completed, so it
        // needs to be told. Cheap: a handful of local requests.
        HabitReminders.sync()
        WaterReminders.sync()
    }

    private func mutate() {
        let doneDay = cal.startOfDay(for: day)
        if let existing = habit.completion(on: day) {
            modelContext.delete(existing)
            habit.completions.removeAll { $0 == existing }
            habit.clearTimer()
            LiveActivityController.shared.stop(habitId: habit.id, done: false)
        } else if habit.type == .timed, isToday {
            if habit.startedAt == nil {
                // start timer + Dynamic Island live activity
                habit.startTimer()
                LiveActivityController.shared.start(habit: habit, target: habit.targetSeconds)
            } else {
                // stop timer → record elapsed as the completion value (pauses excluded)
                let elapsed = habit.elapsedSeconds()
                habit.clearTimer()
                LiveActivityController.shared.stop(habitId: habit.id, done: true)
                let c = Completion(day: doneDay, completedAt: Date(), value: elapsed)
                c.habit = habit
                modelContext.insert(c)
            }
        } else {
            let c = Completion(day: doneDay, completedAt: Date(), value: 1)
            c.habit = habit
            modelContext.insert(c)
        }
    }

    /// Pause/resume the running timer, mirroring the live activity's own key.
    private func togglePause() {
        guard habit.startedAt != nil else { return }
        habit.togglePause()
        try? modelContext.save()
        SnapshotPublisher.publish(context: modelContext)
    }
}