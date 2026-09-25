import SwiftUI
import SwiftData

@main
struct HabitsApp: App {
    /// Reached by the notification delegate and the reminder scheduler, which run outside
    /// the SwiftUI view tree.
    static var sharedContainer: ModelContainer?

    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Habit.self, Routine.self, Completion.self)
        HabitsApp.sharedContainer = container
        Self.seedIfNeeded(container: container)
        // Installs seeded before 2026-09-25 carry nine days of made-up history.
        MainActor.assumeIsolated {
            if DemoHistory.removeIfNeeded(context: container.mainContext) > 0 {
                publishSharedSnapshot()
            }
        }
        NotificationRouter.shared.install()
        WaterReminders.sync()
        HabitReminders.sync()
        // A live activity's "log"/"discard" button runs in this process — let it write
        // through to the store immediately rather than waiting for the next foreground.
        // It must use the *same* context SwiftUI injected: a second ModelContext would
        // take the write, then the view's stale context would republish its old state and
        // undo it (the habit bounced back to "running").
        TimerIntentHooks.applyPending = {
            let publish = {
                MainActor.assumeIsolated { publishSharedSnapshot() }
            }
            if Thread.isMainThread {
                publish()
            } else {
                DispatchQueue.main.async(execute: publish)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .preferredColorScheme(.dark)
        }
    }

    /// First-launch starter routines and habits — no history: every tick in the app is one
    /// you made. (It used to backfill nine days of made-up completions; see DemoHistory.)
    private static func seedIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.seeded) else { return }
        defaults.set(true, forKey: SettingsKey.seeded)
        defaults.set(true, forKey: SettingsKey.demoHistoryRemoved)
        defaults.set("sahil", forKey: SettingsKey.username)

        let ctx = ModelContext(container)
        let morning = Routine(name: "Morning", subtitle: "// after waking up", icon: "sun.max", sortIndex: 0)
        let deep = Routine(name: "Deep Work", subtitle: "// 09:00 – 13:00", icon: "laptopcomputer", sortIndex: 1)
        let wind = Routine(name: "Wind Down", subtitle: "// before sleep", icon: "moon.stars", sortIndex: 2)

        let stretch = Habit(name: "stretch", icon: "figure.flexibility", color: .cyan, type: .timed, comment: "// 10 min", targetSeconds: 600)
        let noPhone = Habit(name: "no phone first hour", icon: "iphone.slash", color: .red, type: .checkbox, comment: "// before 08:00")
        let water = Habit(name: "drink water", icon: "drop", color: .blue, type: .checkbox, comment: "// 500ml")
        let focus = Habit(name: "focus block", icon: "brain.head.profile", color: .blue, type: .timed, comment: "// 1h", targetSeconds: 3600)
        let read = Habit(name: "read", icon: "book", color: .purple, type: .checkbox, comment: "// 20 pages")
        let journal = Habit(name: "journal", icon: "square.and.pencil", color: .amber, type: .checkbox, comment: "// 5 min")
        let noScreens = Habit(name: "no screens after 22", icon: "moon.zzz", color: .red, type: .checkbox, comment: "// wind-down rule")

        morning.habits = [stretch, noPhone, water]
        deep.habits = [focus, read]
        wind.habits = [noScreens, journal]
        [morning, deep, wind].forEach { ctx.insert($0) }
        [stretch, noPhone, water, focus, read, journal, noScreens].forEach {
            $0.routine = $0.routine ?? ($0 == focus || $0 == read ? deep : ($0 == noScreens || $0 == journal ? wind : morning))
            ctx.insert($0)
        }

        try? ctx.save()
    }
}

/// Publishes from the main context — the one SwiftUI's views read, so an intent's write and
/// the UI can't disagree about what happened.
@MainActor
private func publishSharedSnapshot() {
    guard let container = HabitsApp.sharedContainer else { return }
    SnapshotPublisher.publish(context: container.mainContext)
}