import Foundation

/// Achievements + XP (PRD §4.3.2 — v2 scope per §10).
///
/// Every number on the achievements screen is *derived* from habit and completion history,
/// per §7's rule that derived state is never stored. So a tier is earned by arithmetic rather
/// than by a saved claim: un-checking a habit honestly un-earns what it paid for, and there is
/// no second source of truth to drift out of step. It also means the feature needs no schema
/// change and no backfill — existing installs light up from history they already have.
enum Achievements {

    // MARK: - Tier ladder (§4.3.2 "next tier name transition")

    /// A shell-privilege ladder rather than bronze/silver/gold: it escalates the way the app's
    /// own metaphor does, and `sudo → root` is a transition worth chasing.
    enum Tier: Int, CaseIterable, Identifiable {
        case sh, bash, zsh, sudo, root
        var id: Int { rawValue }
        var name: String { ["sh", "bash", "zsh", "sudo", "root"][rawValue] }
    }

    // MARK: - The four confirmed metrics (§4.3.2)

    enum Metric: String, CaseIterable, Identifiable {
        case completions, goalDays, dedication, routineRuns

        var id: String { rawValue }

        var label: String {
            switch self {
            case .completions: return "total completions"
            case .goalDays: return "goal days"
            case .dedication: return "dedication"
            case .routineRuns: return "routine runner"
            }
        }

        var comment: String {
            switch self {
            case .completions: return "// lifetime habit check-offs"
            case .goalDays: return "// days the full daily goal was hit"
            case .dedication: return "// most completions on a single habit"
            case .routineRuns: return "// routines fully completed"
            }
        }

        /// Value required to reach each tier — ascending, one per `Tier`.
        var thresholds: [Int] {
            switch self {
            case .completions: return [10, 50, 150, 400, 1000]
            case .goalDays: return [1, 5, 20, 60, 180]
            case .dedication: return [7, 25, 75, 200, 500]
            case .routineRuns: return [1, 10, 30, 90, 250]
            }
        }

        /// XP paid for *reaching* each tier. Weighted by difficulty, not linearly — a tier is
        /// meant to feel like a bigger prize the deeper it sits.
        var rewards: [Int] {
            switch self {
            case .completions: return [25, 60, 150, 400, 1000]
            case .goalDays: return [30, 75, 200, 500, 1200]
            case .dedication: return [40, 90, 220, 550, 1300]
            case .routineRuns: return [35, 80, 210, 520, 1250]
            }
        }
    }

    // MARK: - Facts

    /// Everything the screen needs, in one pass over the store.
    struct Facts {
        var completions = 0
        var goalDays = 0
        var bestOverallStreak = 0
        var bestPerfectRun = 0
        var firstCompletionDay: Date?
        var daysTracked = 0
        var hasEarlyCheckoff = false
        var hasLateCheckoff = false
        var hasTimedSession = false

        var dedication: Int = 0
        var routineRuns = 0
    }

    /// A habit's first tracked day: the earlier of its creation and its oldest completion.
    ///
    /// The older-completion case matters more than it looks — seeded demo history backfills
    /// completions onto habits created *today*, and treating `createdAt` as the start would
    /// hide every goal day already in the store. Stats needs the same boundary for its
    /// denominators, so this is deliberately not private.
    static func firstTrackedDay(_ habit: Habit) -> Date {
        let created = habit.createdAt.startOfDay()
        guard let oldest = habit.completions.map({ $0.day.startOfDay() }).min() else { return created }
        return min(created, oldest)
    }

    /// The day walk is bounded: nothing before the first tracked habit, nothing past 5 years.
    private static let walkLimitDays = 365 * 5

    static func facts(habits: [Habit], today: Date = Date(), calendar: Calendar = .current) -> Facts {
        var f = Facts()
        let allCompletions = habits.flatMap { $0.completions }
        f.completions = allCompletions.count
        f.dedication = habits.map { $0.completions.count }.max() ?? 0

        f.hasEarlyCheckoff = allCompletions.contains { calendar.component(.hour, from: $0.completedAt) < 7 }
        f.hasLateCheckoff = allCompletions.contains { calendar.component(.hour, from: $0.completedAt) >= 23 }
        // A timed habit records real elapsed seconds as its value; a check-off records exactly 1.
        //
        // Scoped to timed habits deliberately: water is a check-off that keeps a *glass tally* in
        // the same field, so an unscoped `value > 1` would hand out "ran a timed session" to
        // anyone who logged five glasses — no timer anywhere in sight.
        f.hasTimedSession = allCompletions.contains { $0.value > 1 && $0.habit?.type == .timed }

        f.bestOverallStreak = Streaks.bestOverall(completions: allCompletions, calendar: calendar)

        guard !habits.isEmpty else { return f }
        if let first = allCompletions.map({ $0.day.startOfDay() }).min() {
            f.firstCompletionDay = first
            f.daysTracked = max(0, calendar.dateComponents([.day], from: first, to: today.startOfDay()).day ?? 0)
        }

        // One pass over history: goal days and routine runs both need "was every scheduled
        // habit done that day?", so they share the walk rather than each recomputing it.
        //
        // Completed days are indexed up front rather than asked per day per habit: `completion(on:)`
        // is a linear scan, and calling it inside the day walk makes the whole thing quadratic in
        // history length — this keeps the walk cheap enough to run on every render.
        var doneDays: [UUID: Set<Date>] = [:]
        doneDays.reserveCapacity(habits.count)
        for h in habits {
            doneDays[h.id] = Set(h.completions.map { $0.day.startOfDay(calendar: calendar) })
        }
        func isDone(_ habit: Habit, _ day: Date) -> Bool {
            doneDays[habit.id]?.contains(day) ?? false
        }

        let trackingStart = habits.map(firstTrackedDay).min() ?? today.startOfDay()
        let start = max(trackingStart, calendar.date(byAdding: .day, value: -walkLimitDays, to: today)!)
        let routines = distinctRoutines(of: habits)

        var run = 0
        var day = start
        while day <= today.startOfDay() {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day)! }
            let weekday = calendar.component(.weekday, from: day)
            // A habit only counts for days at or after it was first tracked.
            let scheduled = habits.filter {
                firstTrackedDay($0) <= day && $0.scheduleDays.contains(weekday)
            }
            // A day with nothing scheduled is a rest day: it neither extends nor breaks a
            // perfect run, so the run only counts days the user actually had work to do.
            guard !scheduled.isEmpty else { continue }

            if scheduled.allSatisfy({ isDone($0, day) }) {
                f.goalDays += 1
                run += 1
                f.bestPerfectRun = max(f.bestPerfectRun, run)
            } else {
                run = 0
            }

            for routine in routines {
                let due = routine.habits.filter {
                    firstTrackedDay($0) <= day && $0.scheduleDays.contains(weekday)
                }
                guard !due.isEmpty, due.allSatisfy({ isDone($0, day) }) else { continue }
                f.routineRuns += 1
            }
        }
        return f
    }

    private static func distinctRoutines(of habits: [Habit]) -> [Routine] {
        var seen = Set<UUID>()
        var out: [Routine] = []
        for h in habits {
            // Dedupe by id rather than putting @Model objects in a Set.
            if let r = h.routine, seen.insert(r.id).inserted { out.append(r) }
        }
        return out
    }

    // MARK: - Tier progress

    struct MetricProgress: Identifiable {
        let metric: Metric
        let current: Int
        let earnedTiers: [Tier]
        let nextTier: Tier?
        let nextThreshold: Int?
        let xpEarned: Int

        var id: String { metric.rawValue }
        var isMaxed: Bool { nextTier == nil }

        /// XP paid for reaching the tier being chased, for the `+150 xp` label.
        var nextReward: Int? {
            guard let next = nextTier else { return nil }
            return metric.rewards[next.rawValue]
        }

        /// Progress toward the next tier, measured from zero — the number beside the bar is the
        /// literal `current/threshold` §4.3.2 asks for, and the bar agrees with it rather than
        /// quietly showing a tier-relative band.
        var fraction: Double {
            guard let t = nextThreshold, t > 0 else { return 1 }
            return min(1, Double(current) / Double(t))
        }

        /// e.g. `bash → zsh`, or `root` once the ladder is finished.
        var transition: String {
            guard let next = nextTier else { return Tier.root.name }
            guard let last = earnedTiers.last else { return next.name }
            return "\(last.name) → \(next.name)"
        }
    }

    static func progress(metric: Metric, current: Int) -> MetricProgress {
        let thresholds = metric.thresholds
        let rewards = metric.rewards
        var earned: [Tier] = []
        var xp = 0
        for tier in Tier.allCases where thresholds[tier.rawValue] <= current {
            earned.append(tier)
            xp += rewards[tier.rawValue]
        }
        let nextIndex = earned.count
        let next = nextIndex < Tier.allCases.count ? Tier(rawValue: nextIndex) : nil
        return MetricProgress(
            metric: metric,
            current: current,
            earnedTiers: earned,
            nextTier: next,
            nextThreshold: next.map { thresholds[$0.rawValue] },
            xpEarned: xp
        )
    }

    // MARK: - Milestones (§4.3.2 one-time flags — the PRD leaves the list open; this is it)

    struct MilestoneState: Identifiable {
        let id: String
        let name: String
        let comment: String
        let xp: Int
        let earned: Bool
    }

    private struct Milestone {
        let id: String
        let name: String
        let comment: String
        let xp: Int
        let test: (Facts) -> Bool
    }

    private static let milestones: [Milestone] = [
        Milestone(id: "hello-world", name: "hello world",
                  comment: "// check off your first habit", xp: 25,
                  test: { $0.completions > 0 }),
        Milestone(id: "perfect-day", name: "perfect day",
                  comment: "// every scheduled habit, one day", xp: 50,
                  test: { $0.goalDays >= 1 }),
        Milestone(id: "early-bird", name: "early bird",
                  comment: "// a check-off before 07:00", xp: 40,
                  test: { $0.hasEarlyCheckoff }),
        Milestone(id: "night-shift", name: "night shift",
                  comment: "// a check-off after 23:00", xp: 40,
                  test: { $0.hasLateCheckoff }),
        Milestone(id: "uptime", name: "uptime",
                  comment: "// log your first timed session", xp: 40,
                  test: { $0.hasTimedSession }),
        Milestone(id: "week-compiles", name: "week compiles",
                  comment: "// a 7-day streak", xp: 150,
                  test: { $0.bestOverallStreak >= 7 }),
        Milestone(id: "century", name: "century",
                  comment: "// 100 lifetime completions", xp: 200,
                  test: { $0.completions >= 100 }),
        Milestone(id: "perfect-week", name: "perfect week",
                  comment: "// 7 perfect days in a row", xp: 400,
                  test: { $0.bestPerfectRun >= 7 }),
        Milestone(id: "month-compiles", name: "month compiles",
                  comment: "// a 30-day streak", xp: 600,
                  test: { $0.bestOverallStreak >= 30 }),
        Milestone(id: "anniversary", name: "anniversary",
                  comment: "// 365 days tracked", xp: 1000,
                  test: { $0.daysTracked >= 365 }),
    ]

    static func milestoneStates(for facts: Facts) -> [MilestoneState] {
        milestones.map {
            MilestoneState(id: $0.id, name: $0.name, comment: $0.comment,
                           xp: $0.xp, earned: $0.test(facts))
        }
    }

    // MARK: - XP + levels

    /// Level 1 starts at 0; reaching level L needs this much XP in total. Quadratic so the
    /// early levels land within the first week of real use and the last ones are a long haul.
    static func xpThreshold(forLevel level: Int) -> Int {
        75 * max(0, level - 1) * max(0, level - 1)
    }

    struct LevelInfo {
        let level: Int
        let xp: Int
        let xpAtLevelStart: Int
        /// Cumulative XP needed for the next level. The ladder tops out in practice, so this is
        /// always a real target rather than an optional max-level sentinel.
        let xpForNextLevel: Int

        var intoLevel: Int { max(0, xp - xpAtLevelStart) }
        var levelSpan: Int { max(1, xpForNextLevel - xpAtLevelStart) }
        var fraction: Double { min(1, Double(intoLevel) / Double(levelSpan)) }
        var toNextLevel: Int { max(0, xpForNextLevel - xp) }
    }

    static func level(for xp: Int) -> LevelInfo {
        var level = 1
        while xpThreshold(forLevel: level + 1) <= xp { level += 1 }
        return LevelInfo(level: level, xp: xp,
                         xpAtLevelStart: xpThreshold(forLevel: level),
                         xpForNextLevel: xpThreshold(forLevel: level + 1))
    }

    // MARK: - Snapshot

    /// One derived bundle for the whole screen, so the view never recomputes history per row.
    struct Snapshot {
        let facts: Facts
        let metrics: [MetricProgress]
        let milestones: [MilestoneState]
        let xp: Int
        let level: LevelInfo

        var earnedMilestones: Int { milestones.filter(\.earned).count }

        init(habits: [Habit], today: Date = Date(), calendar: Calendar = .current) {
            let facts = Achievements.facts(habits: habits, today: today, calendar: calendar)
            let metrics = [
                Achievements.progress(metric: .completions, current: facts.completions),
                Achievements.progress(metric: .goalDays, current: facts.goalDays),
                Achievements.progress(metric: .dedication, current: facts.dedication),
                Achievements.progress(metric: .routineRuns, current: facts.routineRuns),
            ]
            let milestones = Achievements.milestoneStates(for: facts)
            let xp = metrics.reduce(0) { $0 + $1.xpEarned }
                + milestones.filter(\.earned).reduce(0) { $0 + $1.xp }

            self.facts = facts
            self.metrics = metrics
            self.milestones = milestones
            self.xp = xp
            self.level = Achievements.level(for: xp)
        }
    }
}
