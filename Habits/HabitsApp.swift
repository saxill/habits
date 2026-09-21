import SwiftUI
import SwiftData

@main
struct HabitsApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Habit.self, Routine.self, Completion.self)
        Self.seedIfNeeded(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .preferredColorScheme(.dark)
        }
    }

    /// First-launch demo content so the app reads like the PRD screenshots immediately.
    private static func seedIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.seeded) else { return }
        defaults.set(true, forKey: SettingsKey.seeded)
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

        // Backfill 9 days of history so streaks, the week strip and stats are alive on first open.
        let cal = Calendar.current
        var rng = SystemRandomNumberGenerator()
        let all = [stretch, noPhone, water, focus, read, journal, noScreens]
        for back in 1...9 {
            let day = cal.date(byAdding: .day, value: -back, to: Date())!
            for h in all {
                if Bool.random(using: &rng) || back < 3 {
                    let at = cal.date(bySettingHour: 8 + Int(rng.next() % 12), minute: Int(rng.next() % 60), second: 0, of: day)!
                    let c = Completion(day: day, completedAt: at, value: h.type == .timed ? h.targetSeconds : 1)
                    c.habit = h
                    ctx.insert(c)
                }
            }
        }
        try? ctx.save()
    }
}