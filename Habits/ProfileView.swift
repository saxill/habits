import SwiftUI
import SwiftData
import UIKit

/// Profile tab — appearance settings (§4.3.1) + the `$ achievements` screen (§4.3.2).
struct ProfileView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var store = ThemeStore.shared
    @ObservedObject private var lac = LiveActivityController.shared
    @ObservedObject private var router = NavRouter.shared
    @AppStorage(SettingsKey.username) private var username = "user"
    @AppStorage(SettingsKey.themeId) private var themeId = TerminalTheme.builtin()[0].id
    @AppStorage(SettingsKey.promptSymbol) private var promptSymbol = "$"
    @AppStorage(SettingsKey.textSize) private var textSize = 0
    @AppStorage(SettingsKey.crossOutCompleted) private var crossOut = true
    @AppStorage(SettingsKey.moveCompletedToBottom) private var moveBottom = false
    @AppStorage(SettingsKey.liveActivitiesEnabled) private var laEnabled = true
    @AppStorage(SettingsKey.laShowTimer) private var laShowTimer = true
    @AppStorage(SettingsKey.laShowProgress) private var laShowProgress = true
    @AppStorage(SettingsKey.laShowName) private var laShowName = true
    @AppStorage(SettingsKey.laCountDown) private var laCountDown = true
    @AppStorage(SettingsKey.waterRemindersEnabled) private var waterEnabled = false
    @AppStorage(SettingsKey.waterStartHour) private var waterStartHour = 9
    @AppStorage(SettingsKey.waterEndHour) private var waterEndHour = 21
    @AppStorage(SettingsKey.waterInterval) private var waterInterval = 120
    @State private var waterPermission = "not asked"
    @State private var waterPending = 0
    @State private var habitPending = 0
    /// Glasses logged today, and whether there is a water habit at all — read once per refresh
    /// rather than fetched inside the view body, which would hit the store on every redraw.
    @State private var glassesToday = 0
    @State private var hasWaterHabit = false
    @State private var editingTheme: TerminalTheme?
    /// Reset state: whether the control is armed, and the receipt from the last reset — kept so
    /// the undo chip has something to put back. `undoToken` retires that receipt when its minute
    /// is up, without a second reset having its undo cut short by the first one's timer.
    @State private var armedReset = false
    @State private var lastReset: [DayReset.Dropped] = []
    @State private var undoToken = 0
    @State private var todayDone = 0
    @State private var todayTotal = 0
    /// Which text field, if any, the keyboard belongs to. Held so the screen can give the
    /// keyboard up deliberately — on save, on submit, and on leaving the tab, where a keyboard
    /// left standing would cover whichever screen came next.
    @FocusState private var typing: Bool

    private static let symbols = ["$", "%", "#", ">"]

    /// [foreground, comment, habits-accent, stats-accent, profile-accent].
    private static func swatches(for t: TerminalTheme) -> [String] {
        [t.foreground, t.comment, t.habitsAccent, t.statsAccent, t.profileAccent]
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        previewCard
                        progressSection
                        // Water reminders sit second, above the cosmetic settings. They were
                        // eighth, behind theme/prompt/text/completed, which put them below the
                        // fold on a phone — a feature you have to hunt for reads as a feature
                        // that isn't there.
                        waterSection
                        identitySection
                        themeSection
                        promptSection
                        textSection
                        completedSection
                        // Last of the settings, and after the display preferences on purpose:
                        // it is the one control here that destroys data, and it should not be
                        // what a thumb finds while reaching for "cross out completed".
                        todaySection
                        liveActivitySection
                    }
                    .padding(16)
                }
                .dismissesKeyboardOnDrag()
                .dismissesKeyboardOnTap()
            }
            .dismissesKeyboardOnTap()
            .keyboardDoneButton()
            .background(Color(hex: theme.background))
            // Read the real permission and schedule count on arrival. Without this the line
            // reads "not asked · 0 scheduled" until something is tapped, which is a wrong answer
            // rather than a stale one — the reminders may well be armed and arriving.
            .task {
                await refreshWaterStatus()
                refreshTodayCounts()
            }
            // Leaving the tab drops the keyboard, so it does not stand over whatever comes next.
            .onDisappear { typing = false }
            // The nav bar would put iOS chrome in the middle of a shell; profile and
            // achievements both keep the terminal header instead.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NavRouter.Destination.self) { destination in
                switch destination {
                case .achievements: AchievementsView()
                }
            }
        }
        .sheet(item: $editingTheme) { t in
            ThemeEditorView(theme: t)
        }
        .onChange(of: themeId) { _, _ in republish() }
    }

    /// Entry point to the achievements screen — profile is the settings tab, so it pushes
    /// from here rather than taking a fourth tab of its own. Labelled like every other block
    /// so the scroll reads as one list of sections rather than one loose row.
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// progress", size: 11)
            NavigationLink(value: NavRouter.Destination.achievements) {
                HStack(spacing: 8) {
                    Image(systemName: "trophy")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.profileColor)
                    Text("achievements & xp").term(13).foregroundStyle(.white)
                    Spacer()
                    Text("$ achievements")
                        .term(11)
                        .foregroundStyle(Color(hex: theme.comment))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: theme.comment))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens achievements and XP")
        }
    }

    /// Widgets mirror the active theme, so push a fresh snapshot whenever it changes.
    private func republish() {
        SnapshotPublisher.publish(context: modelContext)
    }

    private var header: some View {
        VStack(spacing: 10) {
            PromptHeader(command: "appearance", accent: theme.profileColor,
                         trailing: AnyView(XPChip()))
            Divider().overlay(Color(hex: theme.comment).opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // Live preview of a habit row reflecting current settings. The accents matter: a real row
    // paints its checkbox *and* its icon with the habit's own colour, so the preview would be
    // lying about the checkbox if it used the profile accent here.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            CommentText(text: "// preview", size: 11)
            HStack(spacing: 10) {
                Text("[✓]").term(13, .semibold).foregroundStyle(theme.habitsColor)
                Image(systemName: "figure.run")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.habitsColor)
                Text("morning run")
                    .term(13)
                    .foregroundStyle(.white)
                    .strikethrough(crossOut)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(hex: "#FF9F45"))
                    Text("7").term(11).monospacedDigit()
                }
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            CommentText(text: "// identity", size: 11)
            HStack {
                TextField("username", text: $username)
                    .term(13)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { typing = false }
                    .onChange(of: username) { _, v in
                        if v.count > 15 { username = String(v.prefix(15)) }
                    }
                Text(verbatim: "\(username.count)/15")
                    .term(11)
                    .foregroundStyle(Color(hex: theme.comment))
                    .monospacedDigit()
                    .accessibilityLabel("\(username.count) of 15 characters")
            }
            .padding(.vertical, 6)
            Divider().overlay(Color(hex: theme.comment).opacity(0.3))
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// theme", size: 11)
            ForEach(store.all) { t in
                HStack(spacing: 10) {
                    Button {
                        themeId = t.id
                        republish()
                    } label: {
                        HStack(spacing: 10) {
                            Text(themeId == t.id ? "[✓]" : "[ ]").term(13, .semibold)
                                .foregroundStyle(theme.profileColor)
                            Text(t.name).term(13).foregroundStyle(.white)
                            Spacer()
                            // ANSI-style swatch dots
                            HStack(spacing: 3) {
                                ForEach(Self.swatches(for: t), id: \.self) { hex in
                                    Circle().fill(Color(hex: hex)).frame(width: 9, height: 9)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // edit / copy / delete controls
                    Button {
                        editingTheme = t.isCustom ? t : ThemeStore.duplicate(t)
                    } label: {
                        Image(systemName: t.isCustom ? "slider.horizontal.3" : "doc.on.doc")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.profileColor.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.isCustom ? "edit theme" : "duplicate theme")

                    if t.isCustom {
                        Button {
                            if themeId == t.id { themeId = TerminalTheme.builtin()[0].id }
                            store.delete(t)
                            republish()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(hex: "#FF6B6B").opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("delete theme")
                    }
                }
            }
            Button {
                let fresh = ThemeStore.duplicate(store.byId(themeId))
                store.upsert(fresh)
                editingTheme = fresh
            } label: {
                CommentText(text: "+ new theme from current", size: 12)
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// prompt symbol", size: 11)
            HStack(spacing: 14) {
                ForEach(Self.symbols, id: \.self) { s in
                    Button {
                        promptSymbol = s
                    } label: {
                        Text(promptSymbol == s ? "[\(s)]" : "[ ]")
                            .term(13, .semibold)
                            .foregroundStyle(promptSymbol == s ? theme.profileColor : Color(hex: theme.comment))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// text", size: 11)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { tier in
                    Button {
                        textSize = tier
                    } label: {
                        Text(["default", "larger", "largest"][tier])
                            .term(12, textSize == tier ? .bold : .regular)
                            .foregroundStyle(textSize == tier ? theme.profileColor : Color(hex: theme.comment))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(textSize == tier ? theme.profileColor : Color(hex: theme.comment).opacity(0.4), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            CommentText(text: "// font: SF Mono (system)", size: 11)
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// completed habits", size: 11)
            switchRow("cross out completed", isOn: $crossOut)
            switchRow("move completed to bottom", isOn: $moveBottom)
        }
    }

    /// Clearing today — the one destructive control in the app.
    ///
    /// Two taps and a receipt: the first arms it and says how much is about to go, the second
    /// does it, and an `undo` chip stands for a minute afterwards. Reset is what you want when you
    /// have mis-tapped something — which is exactly the moment a control with no way back is
    /// worst, so this one always has one.
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// today", size: 11)

            HStack(spacing: 8) {
                Text(verbatim: "\(todayDone)/\(todayTotal) done")
                    .term(12)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: theme.comment))
                if armedReset {
                    // Says what it will clear rather than "confirm?": the count is the one piece
                    // of information that makes the second tap a decision instead of a reflex.
                    chip(label: todayDone == 0 ? "nothing to clear" : "clear \(todayDone)",
                         selected: true) {
                        lastReset = DayReset.resetToday(context: modelContext)
                        armedReset = false
                        refreshTodayCounts()
                        expireUndo(after: 60)
                        Task { await refreshWaterStatus() }
                    }
                    .disabled(todayDone == 0)
                    chip(label: "cancel", selected: false) { armedReset = false }
                } else {
                    chip(label: "reset today", selected: false) { armedReset = true }
                }
                Spacer()
            }

            if !lastReset.isEmpty {
                HStack(spacing: 8) {
                    Text(verbatim: "cleared \(lastReset.count)")
                        .term(10)
                        .foregroundStyle(Color(hex: theme.comment))
                    chip(label: "undo", selected: false) {
                        DayReset.restoreAll(lastReset, context: modelContext)
                        lastReset = []
                        refreshTodayCounts()
                        Task { await refreshWaterStatus() }
                    }
                    Spacer()
                }
            }

            CommentText(text: "// wipes today's ticks and the water tally; today then counts as a missed day for streaks", size: 11)
        }
    }

    /// Drops the receipt after it has stood long enough to be useful.
    ///
    /// Timed rather than left standing: it restores a whole *day*, and a chip that lingers all
    /// evening invites putting back a day that has moved on.
    private func expireUndo(after seconds: Double) {
        undoToken += 1
        let token = undoToken
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            // Only the reset that armed this timer may retire the receipt — a second reset while
            // the first chip was standing would otherwise have its own undo wiped early.
            if token == undoToken { lastReset = [] }
        }
    }

    /// "3/5 done" for the reset row, counted over the habits *scheduled* today — the same set the
    /// daily tab shows, so the number matches what a reset will actually clear.
    private func refreshTodayCounts() {
        let habits = (try? modelContext.fetch(FetchDescriptor<Habit>())) ?? []
        let weekday = Streaks.weekdayIndex(Date())
        let due = habits.filter { $0.scheduleDays.contains(weekday) }
        todayTotal = due.count
        todayDone = due.filter { $0.completion(on: Date()) != nil }.count
    }

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// water reminders", size: 11)

            // Logging is not the same thing as being reminded, so this sits above the reminder
            // settings and works whether or not they are switched on — and it duplicates the `[+]`
            // on the water habit row itself, which is where people look for it first.
            if hasWaterHabit {
                HStack(spacing: 8) {
                    Text(verbatim: "\(glassesToday)/\(WaterReminders.goal) glasses today")
                        .term(12)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: theme.comment))
                    chip(label: "+ glass", selected: false) {
                        WaterReminders.logGlass()
                        // The day's own count moves too — the first glass is what makes the day
                        // count as done, so leaving the reset row stale would understate it.
                        refreshTodayCounts()
                        Task { await refreshWaterStatus() }
                    }
                    Spacer()
                }
            }

            switchRow("remind me to drink water", isOn: $waterEnabled)
                .onChange(of: waterEnabled) { _, on in
                if on {
                    Task {
                        let granted = await WaterReminders.requestAuthorization()
                        waterPermission = granted ? "allowed" : "BLOCKED"
                        if !granted {
                            // nothing to schedule without permission — undo the toggle
                            waterEnabled = false
                        }
                        // Scheduled *here*, not left to the next launch. Enabling used to ask
                        // for permission, update the status line and schedule nothing at all —
                        // the reminders only appeared after the app was relaunched, so the
                        // switch looked like it had done nothing.
                        WaterReminders.sync()
                        await refreshWaterStatus()
                    }
                } else {
                    WaterReminders.sync()
                    Task { await refreshWaterStatus() }
                }
            }

            if waterEnabled {
                HStack(spacing: 8) {
                    Text("every").term(12).foregroundStyle(Color(hex: theme.comment))
                    ForEach(WaterReminders.intervalChoices, id: \.self) { minutes in
                        chip(label: minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m",
                             selected: waterInterval == minutes) {
                            waterInterval = minutes
                            WaterReminders.sync()
                            Task { await refreshWaterStatus() }
                        }
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("window").term(12).foregroundStyle(Color(hex: theme.comment))
                    ForEach(WaterReminders.windowPresets, id: \.label) { preset in
                        chip(label: preset.label,
                             selected: waterStartHour == preset.start && waterEndHour == preset.end) {
                            waterStartHour = preset.start
                            waterEndHour = preset.end
                            WaterReminders.sync()
                            Task { await refreshWaterStatus() }
                        }
                    }
                    Spacer()
                }
                Text("system: \(waterPermission) · \(waterPending) water · \(habitPending) habit scheduled today")
                    .term(10)
                    .foregroundStyle(Color(hex: theme.comment))
                HStack(spacing: 8) {
                    chip(label: "test", selected: false) {
                        HabitReminders.fireTest()
                    }
                    Text("// fires one in 5s")
                        .term(10)
                        .foregroundStyle(Color(hex: theme.comment))
                    Spacer()
                }
                if waterPermission == "BLOCKED" {
                    // iOS asks once. After a denial nothing in this app can re-enable it, so the
                    // only honest thing is to say so and open the one screen that can.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("notifications are off — open settings")
                            .term(11)
                            .foregroundStyle(theme.profileColor)
                    }
                    .buttonStyle(.plain)
                }
                CommentText(text: "// long-press a notification to log a glass without opening the app, or long-press the habit row", size: 11)
            }
        }
    }

    /// A settings switch in the app's own idiom — `[✓]`/`[ ]`, the same control the theme and
    /// prompt-symbol rows already use — instead of a system `Toggle`.
    ///
    /// The whole row is the tap target (a bare `[✓]` is a 24pt box, well under the 44pt
    /// minimum), and the label dims when off so the state is legible without squinting at
    /// brackets. Callers keep chaining `.onChange(of:)` on the result, because that closure has
    /// to fire for changes that don't come from a tap — the water toggle re-enables itself when
    /// permission is denied, and that write has to run the sync path too.
    private func switchRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            // Animated here rather than inside each caller: this is also what makes the
            // settings a switch reveals slide open instead of appearing.
            withAnimation(.easeInOut(duration: 0.22)) { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 10) {
                BracketCheckbox(checked: isOn.wrappedValue, color: theme.profileColor)
                Text(label)
                    .term(13)
                    .foregroundStyle(isOn.wrappedValue ? .white : Color(hex: theme.comment))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.wrappedValue ? "on" : "off")
        .accessibilityAddTraits(.isButton)
    }

    /// Small bordered terminal chip, shared by the interval and window rows.
    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .term(12, selected ? .bold : .regular)
                .foregroundStyle(selected ? theme.profileColor : Color(hex: theme.comment))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(selected ? theme.profileColor : Color(hex: theme.comment).opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func refreshWaterStatus() async {
        let status = await WaterReminders.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral: waterPermission = "allowed"
        case .denied: waterPermission = "BLOCKED"
        default: waterPermission = "not asked"
        }
        waterPending = await WaterReminders.pendingCount()
        habitPending = await HabitReminders.pendingCount()
        let habit = WaterReminders.currentWaterHabit()
        hasWaterHabit = habit != nil
        glassesToday = WaterReminders.glasses(for: habit)
    }

    private var liveActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// live activities", size: 11)
            switchRow("enable live activities", isOn: $laEnabled)
                .onChange(of: laEnabled) { _, on in
                    if !on { LiveActivityController.shared.stop(done: false) }
                }
            if laEnabled {
                switchRow("show elapsed timer", isOn: $laShowTimer)
                switchRow("show progress bar", isOn: $laShowProgress)
                switchRow("show habit name", isOn: $laShowName)
                switchRow("count down to target", isOn: $laCountDown)
                // on-device diagnosis: system permission + what the controller last did
                Text("system: \(lac.systemEnabled ? "allowed" : "BLOCKED") · running: \(lac.runningCount) · last: \(lac.lastEvent)")
                    .term(10)
                    .foregroundStyle(Color(hex: theme.comment))
                    .onAppear { lac.objectWillChange.send() }
                CommentText(text: "// rendered on the dynamic island & lock screen", size: 11)
            }
        }
    }
}

// MARK: - Theme color editor

struct ThemeEditorView: View {
    @Environment(\.theme) private var activeTheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ThemeStore.shared
    @State var theme: TerminalTheme
    private let isNew: Bool

    init(theme: TerminalTheme) {
        // Editing an unsaved duplicate: give it a stable identity only if it's new.
        _theme = State(initialValue: theme)
        isNew = theme.id.hasPrefix("custom-") && !ThemeStore.shared.all.contains { $0.id == theme.id }
    }

    private struct Row: Identifiable {
        let label: String
        let keyPath: WritableKeyPath<TerminalTheme, String>
        var id: String { label }
    }
    private let rows: [Row] = [
        Row(label: "background", keyPath: \.background),
        Row(label: "foreground", keyPath: \.foreground),
        Row(label: "comment", keyPath: \.comment),
        Row(label: "habits accent", keyPath: \.habitsAccent),
        Row(label: "stats accent", keyPath: \.statsAccent),
        Row(label: "profile accent", keyPath: \.profileAccent),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("name") {
                    TextField("theme name", text: $theme.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                Section("colors") {
                    ForEach(rows) { row in
                        colorRow(row)
                    }
                }
                // Live sample strip using the draft colors.
                Section {
                    HStack(spacing: 10) {
                        Text("[✓]").font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: theme.habitsAccent))
                        Image(systemName: "timer")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color(hex: theme.habitsAccent))
                        Text("morning run")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color(hex: theme.foreground))
                        CommentText(text: "// sample")
                        Spacer()
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color(hex: theme.habitsAccent))
                    }
                    .listRowBackground(Color(hex: theme.background))
                }
            }
            .keyboardDoneButton()
            .navigationTitle(isNew ? "new theme" : "edit theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        if theme.name.trimmingCharacters(in: .whitespaces).isEmpty { theme.name = "custom" }
                        store.upsert(theme)
                        if isNew {
                            // a freshly created theme becomes the active one immediately
                            UserDefaults.standard.set(theme.id, forKey: SettingsKey.themeId)
                        }
                        // edited colors reach the widgets too
                        SnapshotPublisher.publish(context: modelContext)
                        dismiss()
                    }
                }
            }
            .background(Color(hex: theme.background))
        }
    }

    private func colorRow(_ row: Row) -> some View {
        let colorBinding = Binding<Color>(
            get: { Color(hex: theme[keyPath: row.keyPath]) },
            set: { theme[keyPath: row.keyPath] = $0.hexString }
        )
        return HStack {
            Text(row.label).term(12).foregroundStyle(.primary)
            Spacer()
            Text(theme[keyPath: row.keyPath])
                .term(11)
                .foregroundStyle(.secondary)
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
        }
    }
}
