package com.sahilchanna.habits

import com.sahilchanna.habits.model.Achievements
import com.sahilchanna.habits.model.HabitType
import com.sahilchanna.habits.model.HabitsClock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Achievements, tiers and the XP ladder — all derived, so all checkable against a fixed history. */
class AchievementsTest {

    private val clock: HabitsClock = T.clock("2026-03-10T12:00:00Z")
    private val today = T.day("2026-03-10")

    @Test
    fun `the tier ladder is a shell-privilege escalation`() {
        assertEquals(
            listOf("sh", "bash", "zsh", "sudo", "root"),
            Achievements.Tier.all.map { it.tierName },
        )
        assertNull(Achievements.Tier.at(5))
    }

    @Test
    fun `each metric has one threshold and one reward per tier`() {
        for (metric in Achievements.Metric.entries) {
            assertEquals(Achievements.Tier.all.size, metric.thresholds.size)
            assertEquals(Achievements.Tier.all.size, metric.rewards.size)
            // Ascending, or the walk that picks the next tier would pick the wrong one.
            assertTrue(metric.thresholds.zipWithNext().all { (a, b) -> a < b })
        }
    }

    @Test
    fun `progress stops at the highest tier reached`() {
        val p = Achievements.progress(Achievements.Metric.COMPLETIONS, 10)
        assertEquals(listOf(Achievements.Tier.SH), p.earnedTiers)
        assertEquals(Achievements.Tier.BASH, p.nextTier)
        assertEquals(50, p.nextThreshold)
        // 25 is what `sh` already paid; the label shows what chasing `bash` is worth.
        assertEquals(25, p.xpEarned)
        assertEquals(60, p.nextReward)
        assertEquals("sh → bash", p.transition)
    }

    @Test
    fun `progress measured from zero, not from the last tier`() {
        // 30 of the 50 needed for bash: the bar and the label must agree.
        val p = Achievements.progress(Achievements.Metric.COMPLETIONS, 30)
        assertEquals(0.6, p.fraction, 0.0001)
    }

    @Test
    fun `a maxed metric is finished, not stuck at the last step`() {
        val p = Achievements.progress(Achievements.Metric.COMPLETIONS, 5000)
        assertTrue(p.isMaxed)
        assertNull(p.nextThreshold)
        assertEquals(1.0, p.fraction, 0.0001)
        assertEquals("root", p.transition)
        assertEquals(Achievements.Tier.all.size, p.earnedTiers.size)
    }

    @Test
    fun `zero progress still names the tier being chased`() {
        val p = Achievements.progress(Achievements.Metric.GOAL_DAYS, 0)
        assertTrue(p.earnedTiers.isEmpty())
        assertEquals(Achievements.Tier.SH, p.nextTier)
        // No earned tier yet, so the transition is just the destination.
        assertEquals("sh", p.transition)
        assertEquals(0.0, p.fraction, 0.0001)
    }

    @Test
    fun `the xp ladder is quadratic and starts at zero`() {
        assertEquals(0, Achievements.xpThreshold(1))
        assertEquals(75, Achievements.xpThreshold(2))
        assertEquals(300, Achievements.xpThreshold(3))
        assertEquals(675, Achievements.xpThreshold(4))
    }

    @Test
    fun `a level is the highest threshold it has passed`() {
        assertEquals(1, Achievements.level(0).level)
        assertEquals(1, Achievements.level(74).level)
        assertEquals(2, Achievements.level(75).level)
        assertEquals(2, Achievements.level(299).level)
        assertEquals(3, Achievements.level(300).level)
    }

    @Test
    fun `level progress is measured inside the level`() {
        val info = Achievements.level(150)
        assertEquals(2, info.level)
        assertEquals(75, info.xpAtLevelStart)
        assertEquals(300, info.xpForNextLevel)
        assertEquals(75, info.intoLevel)
        assertEquals(225, info.levelSpan)
        assertEquals(150, info.toNextLevel)
        assertEquals(75.0 / 225.0, info.fraction, 0.0001)
    }

    @Test
    fun `first tracked day is the older of creation and oldest completion`() {
        val habit = T.habit(createdAt = Instant.parse("2026-03-05T00:00:00Z"))
        assertEquals(T.day("2026-03-05"), Achievements.firstTrackedDay(habit, clock))
        // Seeded history backfills completions onto habits created today; the completion wins.
        T.done(habit, T.day("2026-02-20"))
        assertEquals(T.day("2026-02-20"), Achievements.firstTrackedDay(habit, clock))
    }

    @Test
    fun `facts count completions, goal days and the best perfect run`() {
        val habit = T.habit(createdAt = Instant.parse("2026-03-05T00:00:00Z"))
        T.done(habit, T.day("2026-03-05"))
        T.done(habit, T.day("2026-03-06"))
        // 03-07 missed.
        T.done(habit, T.day("2026-03-08"))
        val facts = Achievements.facts(listOf(habit), today, clock)
        assertEquals(3, facts.completions)
        // 03-05, 03-06 and 03-08 were all perfect days; 03-07 broke the run.
        assertEquals(3, facts.goalDays)
        assertEquals(2, facts.bestPerfectRun)
        assertEquals(2, facts.bestOverallStreak)
    }

    @Test
    fun `a rest day neither extends nor breaks a perfect run`() {
        // A Monday-only habit: only Mondays have anything scheduled, so Tuesdays are rest days.
        val mondayOnly = T.habit(
            createdAt = Instant.parse("2026-03-02T00:00:00Z"),
            scheduleDays = setOf(2),
        )
        // 2026-03-02 and 2026-03-09 are Mondays, both done. The week between them must not break it.
        T.done(mondayOnly, T.day("2026-03-02"))
        T.done(mondayOnly, T.day("2026-03-09"))
        val facts = Achievements.facts(listOf(mondayOnly), today, clock)
        assertEquals(2, facts.goalDays)
        assertEquals(2, facts.bestPerfectRun)
    }

    @Test
    fun `routine runs count a routine with every scheduled habit done`() {
        val routine = T.routine(id = "r", habits = emptyList())
        val a = T.habit(id = "a", createdAt = Instant.parse("2026-03-09T00:00:00Z"), routine = routine)
        val b = T.habit(id = "b", createdAt = Instant.parse("2026-03-09T00:00:00Z"), routine = routine)
        // The routine has to actually hold its habits: the run count asks whether everything *in*
        // the routine was done that day, so an empty routine would count zero by definition.
        routine.habits.addAll(listOf(a, b))
        T.done(a, today)
        T.done(b, today)
        val facts = Achievements.facts(listOf(a, b), today, clock)
        assertEquals(1, facts.routineRuns)
    }

    @Test
    fun `a timed value hands out uptime, a glass tally does not`() {
        val checkoff = T.habit(id = "water", icon = "drop", type = HabitType.CHECKBOX)
        T.done(checkoff, today, value = 5.0)
        val facts = Achievements.facts(listOf(checkoff), today, clock)
        // Five glasses is not a timed session.
        assertFalse(facts.hasTimedSession)

        val timed = T.habit(id = "stretch", type = HabitType.TIMED)
        T.done(timed, today, value = 612.0)
        val timedFacts = Achievements.facts(listOf(timed), today, clock)
        assertTrue(timedFacts.hasTimedSession)
    }

    @Test
    fun `early and late checkoffs are read from the wall clock`() {
        val habit = T.habit(id = "h")
        T.done(habit, T.day("2026-03-09"), at = Instant.parse("2026-03-09T05:30:00Z"))
        T.done(habit, T.day("2026-03-10"), at = Instant.parse("2026-03-10T23:45:00Z"))
        val facts = Achievements.facts(listOf(habit), today, clock)
        assertTrue(facts.hasEarlyCheckoff)
        assertTrue(facts.hasLateCheckoff)
    }

    @Test
    fun `the snapshot folds metrics and milestones into one xp total`() {
        val habit = T.habit(id = "h", createdAt = Instant.parse("2026-03-09T00:00:00Z"))
        T.done(habit, today)
        val snap = Achievements.Snapshot(listOf(habit), today, clock)
        assertTrue(snap.xp > 0)
        assertTrue(snap.earnedMilestones >= 1)
        // hello world (25) + perfect day (50) at least, plus nothing from the tiers at 1 completion.
        assertTrue(snap.xp >= 75)
        assertEquals(snap.milestones.count { it.earned }, snap.earnedMilestones)
    }

    @Test
    fun `an empty store earns nothing`() {
        val snap = Achievements.Snapshot(emptyList(), today, clock)
        assertEquals(0, snap.xp)
        assertEquals(0, snap.earnedMilestones)
        assertEquals(1, snap.level.level)
    }

    @Test
    fun `milestones are stable and named in the terminal's voice`() {
        val states = Achievements.milestoneStates(Achievements.Facts())
        assertEquals(10, states.size)
        assertTrue(states.none { it.earned })
        assertTrue(states.all { it.comment.startsWith("//") })
        // Ids are unique, or a list would drop rows.
        assertEquals(states.size, states.map { it.id }.distinct().size)
    }
}
