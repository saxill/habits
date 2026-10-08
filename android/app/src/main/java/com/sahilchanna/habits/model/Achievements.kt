package com.sahilchanna.habits.model

import com.sahilchanna.habits.data.Habit
import com.sahilchanna.habits.data.Routine
import java.time.LocalDate

/**
 * Achievements + XP (PRD §4.3.2 — v2 scope per §10).
 *
 * Every number on the achievements screen is *derived* from habit and completion history, per
 * §7's rule that derived state is never stored. So a tier is earned by arithmetic rather than by
 * a saved claim: un-checking a habit honestly un-earns what it paid for, and there is no second
 * source of truth to drift out of step.
 */
object Achievements {

    // MARK: - Tier ladder

    /**
     * A shell-privilege ladder rather than bronze/silver/gold: it escalates the way the app's own
     * metaphor does, and `sudo → root` is a transition worth chasing.
     */
    enum class Tier(val tierName: String) {
        SH("sh"), BASH("bash"), ZSH("zsh"), SUDO("sudo"), ROOT("root");

        val index: Int get() = ordinal

        companion object {
            val all: List<Tier> = entries.toList()
            fun at(index: Int): Tier? = entries.getOrNull(index)
        }
    }

    // MARK: - The four confirmed metrics

    enum class Metric(val raw: String, val label: String, val comment: String) {
        COMPLETIONS("completions", "total completions", "// lifetime habit check-offs"),
        GOAL_DAYS("goalDays", "goal days", "// days the full daily goal was hit"),
        DEDICATION("dedication", "dedication", "// most completions on a single habit"),
        ROUTINE_RUNS("routineRuns", "routine runner", "// routines fully completed");

        /** Value required to reach each tier — ascending, one per `Tier`. */
        val thresholds: List<Int>
            get() = when (this) {
                COMPLETIONS -> listOf(10, 50, 150, 400, 1000)
                GOAL_DAYS -> listOf(1, 5, 20, 60, 180)
                DEDICATION -> listOf(7, 25, 75, 200, 500)
                ROUTINE_RUNS -> listOf(1, 10, 30, 90, 250)
            }

        /**
         * XP paid for *reaching* each tier. Weighted by difficulty, not linearly — a tier is meant
         * to feel like a bigger prize the deeper it sits.
         */
        val rewards: List<Int>
            get() = when (this) {
                COMPLETIONS -> listOf(25, 60, 150, 400, 1000)
                GOAL_DAYS -> listOf(30, 75, 200, 500, 1200)
                DEDICATION -> listOf(40, 90, 220, 550, 1300)
                ROUTINE_RUNS -> listOf(35, 80, 210, 520, 1250)
            }
    }

    // MARK: - Facts

    /** Everything the screen needs, in one pass over the store. */
    data class Facts(
        val completions: Int = 0,
        val goalDays: Int = 0,
        val bestOverallStreak: Int = 0,
        val bestPerfectRun: Int = 0,
        val firstCompletionDay: LocalDate? = null,
        val daysTracked: Int = 0,
        val hasEarlyCheckoff: Boolean = false,
        val hasLateCheckoff: Boolean = false,
        val hasTimedSession: Boolean = false,
        val dedication: Int = 0,
        val routineRuns: Int = 0,
    )

    /**
     * A habit's first tracked day: the earlier of its creation and its oldest completion.
     *
     * The older-completion case matters more than it looks — seeded demo history backfills
     * completions onto habits created *today*, and treating creation as the start would hide every
     * goal day already in the store. Stats needs the same boundary for its denominators, so this is
     * deliberately not private.
     */
    fun firstTrackedDay(habit: Habit, clock: HabitsClock = HabitsClock()): LocalDate {
        val created = clock.dayOf(habit.createdAt)
        val oldest = habit.completions.minOfOrNull { it.day } ?: return created
        return if (created <= oldest) created else oldest
    }

    /** The day walk is bounded: nothing before the first tracked habit, nothing past 5 years. */
    private const val WALK_LIMIT_DAYS = 365L * 5

    fun facts(habits: List<Habit>, today: LocalDate, clock: HabitsClock): Facts {
        val allCompletions = habits.flatMap { it.completions }
        val hasEarly = allCompletions.any { clock.hourOf(it.completedAt) < 7 }
        val hasLate = allCompletions.any { clock.hourOf(it.completedAt) >= 23 }
        // A timed habit records real elapsed seconds as its value; a check-off records exactly 1.
        //
        // Scoped to timed habits deliberately: water is a check-off that keeps a *glass tally* in
        // the same field, so an unscoped `value > 1` would hand out "ran a timed session" to anyone
        // who logged five glasses — no timer anywhere in sight.
        val hasTimed = allCompletions.any { it.value > 1 && it.habit?.type == HabitType.TIMED }

        val firstDay = allCompletions.minOfOrNull { it.day }

        val base = Facts(
            completions = allCompletions.size,
            dedication = habits.maxOfOrNull { it.completions.size } ?: 0,
            hasEarlyCheckoff = hasEarly,
            hasLateCheckoff = hasLate,
            hasTimedSession = hasTimed,
            bestOverallStreak = Streaks.bestOverall(allCompletions),
            firstCompletionDay = firstDay,
            daysTracked = if (firstDay == null) 0 else clock.daysBetween(firstDay, today).toInt().coerceAtLeast(0),
        )

        if (habits.isEmpty()) return base

        // One pass over history: goal days and routine runs both need "was every scheduled habit
        // done that day?", so they share the walk rather than each recomputing it.
        //
        // Completed days are indexed up front rather than asked per day per habit: `completion(day)`
        // is a linear scan, and calling it inside the day walk makes the whole thing quadratic in
        // history length — this keeps the walk cheap enough to run on every render.
        val doneDays: Map<String, Set<LocalDate>> = habits.associate { h -> h.id to h.completions.map { it.day }.toSet() }
        fun isDone(habit: Habit, day: LocalDate): Boolean = doneDays[habit.id]?.contains(day) == true

        val trackingStart = habits.minOf { firstTrackedDay(it, clock) }
        val start = maxOf(trackingStart, today.minusDays(WALK_LIMIT_DAYS))
        val routines = distinctRoutines(habits)

        var goalDays = 0
        var bestPerfectRun = 0
        var routineRuns = 0
        var run = 0
        var day = start
        while (day <= today) {
            val weekday = Streaks.weekdayIndex(day)
            // A habit only counts for days at or after it was first tracked.
            val scheduled = habits.filter {
                firstTrackedDay(it, clock) <= day && it.scheduleDays.contains(weekday)
            }
            // A day with nothing scheduled is a rest day: it neither extends nor breaks a perfect
            // run, so the run only counts days the user actually had work to do.
            if (scheduled.isNotEmpty()) {
                if (scheduled.all { isDone(it, day) }) {
                    goalDays += 1
                    run += 1
                    if (run > bestPerfectRun) bestPerfectRun = run
                } else {
                    run = 0
                }
            }

            for (routine in routines) {
                val due = routine.habits.filter {
                    firstTrackedDay(it, clock) <= day && it.scheduleDays.contains(weekday)
                }
                if (due.isNotEmpty() && due.all { isDone(it, day) }) routineRuns += 1
            }

            day = day.plusDays(1)
        }

        return base.copy(goalDays = goalDays, bestPerfectRun = bestPerfectRun, routineRuns = routineRuns)
    }

    private fun distinctRoutines(habits: List<Habit>): List<Routine> {
        val seen = mutableSetOf<String>()
        val out = mutableListOf<Routine>()
        for (h in habits) {
            val r = h.routine ?: continue
            if (seen.add(r.id)) out.add(r)
        }
        return out
    }

    // MARK: - Tier progress

    data class MetricProgress(
        val metric: Metric,
        val current: Int,
        val earnedTiers: List<Tier>,
        val nextTier: Tier?,
        val nextThreshold: Int?,
        val xpEarned: Int,
    ) {
        val isMaxed: Boolean get() = nextTier == null

        /** XP paid for reaching the tier being chased, for the `+150 xp` label. */
        val nextReward: Int? get() = nextTier?.let { metric.rewards[it.index] }

        /**
         * Progress toward the next tier, measured from zero — the number beside the bar is the
         * literal `current/threshold` §4.3.2 asks for, and the bar agrees with it rather than
         * quietly showing a tier-relative band.
         */
        val fraction: Double
            get() {
                val t = nextThreshold ?: return 1.0
                if (t <= 0) return 1.0
                return minOf(1.0, current.toDouble() / t.toDouble())
            }

        /** e.g. `bash → zsh`, or `root` once the ladder is finished. */
        val transition: String
            get() {
                val next = nextTier ?: return Tier.ROOT.tierName
                val last = earnedTiers.lastOrNull() ?: return next.tierName
                return "${last.tierName} → ${next.tierName}"
            }
    }

    fun progress(metric: Metric, current: Int): MetricProgress {
        val thresholds = metric.thresholds
        val rewards = metric.rewards
        val earned = mutableListOf<Tier>()
        var xp = 0
        for (tier in Tier.all) {
            if (thresholds[tier.index] <= current) {
                earned.add(tier)
                xp += rewards[tier.index]
            }
        }
        val next = Tier.at(earned.size)
        return MetricProgress(
            metric = metric,
            current = current,
            earnedTiers = earned,
            nextTier = next,
            nextThreshold = next?.let { thresholds[it.index] },
            xpEarned = xp,
        )
    }

    // MARK: - Milestones

    data class MilestoneState(
        val id: String,
        val name: String,
        val comment: String,
        val xp: Int,
        val earned: Boolean,
    )

    private data class Milestone(
        val id: String,
        val name: String,
        val comment: String,
        val xp: Int,
        val test: (Facts) -> Boolean,
    )

    private val milestones = listOf(
        Milestone("hello-world", "hello world", "// check off your first habit", 25) { it.completions > 0 },
        Milestone("perfect-day", "perfect day", "// every scheduled habit, one day", 50) { it.goalDays >= 1 },
        Milestone("early-bird", "early bird", "// a check-off before 07:00", 40) { it.hasEarlyCheckoff },
        Milestone("night-shift", "night shift", "// a check-off after 23:00", 40) { it.hasLateCheckoff },
        Milestone("uptime", "uptime", "// log your first timed session", 40) { it.hasTimedSession },
        Milestone("week-compiles", "week compiles", "// a 7-day streak", 150) { it.bestOverallStreak >= 7 },
        Milestone("century", "century", "// 100 lifetime completions", 200) { it.completions >= 100 },
        Milestone("perfect-week", "perfect week", "// 7 perfect days in a row", 400) { it.bestPerfectRun >= 7 },
        Milestone("month-compiles", "month compiles", "// a 30-day streak", 600) { it.bestOverallStreak >= 30 },
        Milestone("anniversary", "anniversary", "// 365 days tracked", 1000) { it.daysTracked >= 365 },
    )

    fun milestoneStates(facts: Facts): List<MilestoneState> = milestones.map {
        MilestoneState(it.id, it.name, it.comment, it.xp, it.test(facts))
    }

    // MARK: - XP + levels

    /**
     * Level 1 starts at 0; reaching level L needs this much XP in total. Quadratic so the early
     * levels land within the first week of real use and the last ones are a long haul.
     */
    fun xpThreshold(level: Int): Int = 75 * maxOf(0, level - 1) * maxOf(0, level - 1)

    data class LevelInfo(
        val level: Int,
        val xp: Int,
        val xpAtLevelStart: Int,
        val xpForNextLevel: Int,
    ) {
        val intoLevel: Int get() = maxOf(0, xp - xpAtLevelStart)
        val levelSpan: Int get() = maxOf(1, xpForNextLevel - xpAtLevelStart)
        val fraction: Double get() = minOf(1.0, intoLevel.toDouble() / levelSpan.toDouble())
        val toNextLevel: Int get() = maxOf(0, xpForNextLevel - xp)
    }

    fun level(xp: Int): LevelInfo {
        var level = 1
        while (xpThreshold(level + 1) <= xp) level += 1
        return LevelInfo(level, xp, xpThreshold(level), xpThreshold(level + 1))
    }

    // MARK: - Snapshot

    /** One derived bundle for the whole screen, so the view never recomputes history per row. */
    class Snapshot(habits: List<Habit>, today: LocalDate, clock: HabitsClock) {
        val facts: Facts = facts(habits, today, clock)
        val metrics: List<MetricProgress> = listOf(
            progress(Metric.COMPLETIONS, facts.completions),
            progress(Metric.GOAL_DAYS, facts.goalDays),
            progress(Metric.DEDICATION, facts.dedication),
            progress(Metric.ROUTINE_RUNS, facts.routineRuns),
        )
        val milestones: List<MilestoneState> = milestoneStates(facts)
        val xp: Int = metrics.sumOf { it.xpEarned } + milestones.filter { it.earned }.sumOf { it.xp }
        val level: LevelInfo = level(xp)

        val earnedMilestones: Int get() = milestones.count { it.earned }
    }
}
