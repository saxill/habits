import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

/// Widget bundle: home-screen/lock-screen "today" widgets plus the running-timer
/// live activity on the Dynamic Island + lock screen.
@main
struct HabitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LockWidget()
        TimerLiveActivity()
    }
}

/// Widget-target color parsing: the app's `Color(hex:)` lives in the app target only.
extension Color {
    init(hexString: String) {
        var s = hexString
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    /// Terminal green / amber, shared by the live activity and the today widgets.
    static let habitsDone = Color(hexString: "#4ADE80")
    static let habitsOver = Color(hexString: "#FF9F45")
}

// MARK: - Timer live activity

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen / banner
            TimerLockScreenView(context: context)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .activityBackgroundTint(context.accent.opacity(context.state.isDone ? 0.20 : 0.13))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GlyphTile(icon: context.habitIcon,
                              accent: context.accent,
                              isDone: context.state.isDone,
                              size: 36)
                        .padding(.leading, 2)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        if context.state.showName {
                            Text(context.habitName)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        // Same `$` prompt idiom as the lock screen card, so the island and the
                        // lock screen read as one design rather than two.
                        Text(context.islandStatus)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(context.islandStatusColor)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        timerText(context)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(context.timerColor)
                        if !context.state.isDone {
                            Text(context.timerCaption)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: 88, alignment: .trailing)
                    .padding(.trailing, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 9) {
                        if !context.state.isDone, context.state.showProgress {
                            TimerProgress(context: context)
                        }
                        HStack(spacing: 8) {
                            if context.state.isDone {
                                // Mirrors the lock screen's completion card: green ✓ line in
                                // the centre, routine tally here, no buttons to press.
                                Text(context.completionContext)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                DayContext(context: context)
                            }
                            Spacer(minLength: 4)
                            if !context.state.isDone {
                                ActivityButtons(context: context)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            } compactLeading: {
                Image(systemName: context.stateGlyph)
                    .foregroundStyle(context.timerColor)
            } compactTrailing: {
                Group {
                    if context.state.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    } else {
                        timerText(context)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(context.timerColor)
                .frame(maxWidth: 56)
            } minimal: {
                // Only the live APIs (`Text`/`ProgressView` on a timerInterval) keep
                // updating on their own, and a bar is unreadable in a slot this small —
                // so the glyph carries both identity and state.
                Image(systemName: context.stateGlyph)
                    .foregroundStyle(context.timerColor)
            }
            .widgetURL(URL(string: "habits://open"))
            .keylineTint(context.accent)
        }
    }
}

// MARK: - Lock screen presentation

private struct TimerLockScreenView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        if context.state.isDone {
            TimerCompletedCard(context: context)
        } else {
            runningCard
        }
    }

    private var runningCard: some View {
        VStack(spacing: 10) {
            // Terminal prompt line — the app's own header idiom, and the one place with
            // room to say "paused" without displacing the timer.
            HStack(spacing: 6) {
                Text("$")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(context.accent)
                Text("habits$")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if context.isPaused {
                    HStack(spacing: 3) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("paused")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Color.habitsOver)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.habitsOver.opacity(0.18)))
                }
            }

            HStack(spacing: 12) {
                GlyphTile(icon: context.habitIcon,
                          accent: context.accent,
                          isDone: false,
                          size: 46)

                VStack(alignment: .leading, spacing: 4) {
                    if context.state.showName {
                        Text(context.habitName)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Text(context.statusLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    timerText(context)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(context.timerColor)
                    Text(context.timerCaption)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if context.state.showProgress { TimerProgress(context: context) }

            HStack(spacing: 8) {
                DayContext(context: context)
                Spacer(minLength: 4)
                ActivityButtons(context: context)
            }
        }
    }
}

/// Shown once the timer is logged — the payoff beat before the activity dismisses.
/// Uses the *actual* logged time, not the target, so ending a 90m timer at 12m says 12m.
private struct TimerCompletedCard: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text("complete")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.habitsDone))

            Text("\(context.habitName) — \(context.loggedLabel)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(context.completionContext)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Interactive controls

/// ⏸/▶ pauses, ✓ logs, ✕ discards — all handled in the app's process by
/// `PauseTimerIntent` / `LogTimerIntent` / `DiscardTimerIntent` (LiveActivityIntent,
/// not plain AppIntent: a plain one runs in the widget extension, where
/// `Activity<T>.activities` is empty and the write silently goes nowhere).
private struct ActivityButtons: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        HStack(spacing: 8) {
            // ✓ is filled and the others are outlined: logging is the action the user is
            // working toward, and three identically-weighted keys hide that.
            ActivityButton(symbol: context.isPaused ? "play.fill" : "pause.fill",
                           tint: context.accent,
                           intent: PauseTimerIntent(habitId: context.attributes.habitId,
                                                    paused: !context.isPaused))
            ActivityButton(symbol: "checkmark", tint: context.accent, filled: true,
                           intent: LogTimerIntent(habitId: context.attributes.habitId))
            ActivityButton(symbol: "xmark", tint: .secondary,
                           intent: DiscardTimerIntent(habitId: context.attributes.habitId))
        }
    }
}

/// Terminal-key styled button: squared corners, tinted fill, hairline border. `filled`
/// inverts it into the solid primary form.
private struct ActivityButton: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 13
    var filled: Bool = false
    let intent: any AppIntent

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(filled ? .black : tint)
                .frame(width: size * 2.6, height: size * 2.1)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(filled ? 1 : 0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(tint.opacity(filled ? 0 : 0.42), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

/// The habit's glyph on an accent tile — the activity's visual anchor.
private struct GlyphTile: View {
    let icon: String
    let accent: Color
    var isDone: Bool = false
    var size: CGFloat = 44

    private var tint: Color { isDone ? .habitsDone : accent }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(tint.opacity(0.18))
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
            Image(systemName: isDone ? "checkmark" : icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// Progress toward the target. `ProgressView(timerInterval:)` is animated by the system
/// for the life of the activity — a plain bar drawn from `Date()` would freeze between
/// activity updates, which is most of the timer's runtime.
///
/// While paused that reasoning inverts: the bar must *stop*, so a static
/// `ProgressView(value:)` fed a pause-frozen fraction is the correct choice here.
private struct TimerProgress: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        if context.state.targetSeconds > 0 {
            if context.isPaused {
                ProgressView(value: context.fractionAtPause)
                    .progressViewStyle(.linear)
                    .tint(context.timerColor)
            } else {
                // Both labels are explicitly empty: the default `currentValueLabel` for a
                // timer progress view is a date label, which would duplicate the big timer.
                ProgressView(
                    timerInterval: context.state.startDate...(context.state.startDate + context.state.targetSeconds),
                    countsDown: false
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(context.timerColor)
            }
        }
    }
}

/// `3 of 5 today  🔥 12` — today's progress at the moment the app last published.
private struct DayContext: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        if context.state.totalToday > 0 {
            HStack(spacing: 7) {
                Text("\(context.state.doneToday) of \(context.state.totalToday) today")
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if context.state.streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.habitsOver)
                        Text("\(context.state.streak)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .lineLimit(1)
        }
    }
}

/// Auto-updating timer text: countdown (or count-up), the static target when the timer
/// display is switched off, and a terminal-style done state.
///
/// Paused has to be a plain `Text` — `Text(timerInterval:)` is driven by the system clock
/// and cannot be stopped, so it would keep counting down while the timer was suspended.
@ViewBuilder
private func timerText(_ context: ActivityViewContext<TimerActivityAttributes>) -> some View {
    let state = context.state
    if state.isDone {
        Text("done ✓")
    } else if context.isPaused {
        Text(targetLabel(context.remainingAtPause))
    } else if !state.showTimer {
        Text(targetLabel(state.targetSeconds))
    } else if context.isOverdue {
        // Past the target: a closed-range countdown would freeze at 00:00, so switch to
        // counting total elapsed instead — the number keeps moving.
        Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
    } else if state.countDown {
        // closed range counts down and settles at 00:00
        Text(timerInterval: state.startDate...(state.startDate + max(state.targetSeconds, 1)), countsDown: true)
    } else {
        Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
    }
}

private func targetLabel(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    guard total > 0 else { return "--:--" }
    return total >= 3600
        ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        : String(format: "%d:%02d", total / 60, total % 60)
}

private extension ActivityViewContext where Attributes == TimerActivityAttributes {
    // Display fields prefer the refreshed values in `state` and fall back to the attributes
    // captured when the activity started — `attributes` can't be changed for the life of an
    // activity, so the state copy is what lets a rename or recolor show up mid-timer.
    var habitName: String { state.liveName ?? attributes.habitName }
    var habitIcon: String { state.liveIcon ?? attributes.habitIcon }
    var routineName: String { state.liveRoutineName ?? attributes.routineName }

    /// The habit's accent colour.
    var accent: Color { Color(hexString: state.liveColorHex ?? attributes.colorHex) }

    var isPaused: Bool { state.pausedAt != nil }

    /// Time actually spent on the timer — pauses excluded. While paused this is pinned to
    /// the pause instant, so anything derived from it stays frozen until the timer resumes.
    var elapsedSeconds: TimeInterval {
        max(0, (state.pausedAt ?? Date()).timeIntervalSince(state.startDate) - state.pausedSeconds)
    }

    /// Fraction of the target completed, frozen while paused. Clamped for `ProgressView`.
    var fractionAtPause: Double {
        guard state.targetSeconds > 0 else { return 0 }
        return min(1, max(0, elapsedSeconds / state.targetSeconds))
    }

    /// Countdown value while paused — the remaining time as of the pause instant.
    var remainingAtPause: TimeInterval {
        max(0, state.targetSeconds - elapsedSeconds)
    }

    /// Past the target but not yet logged. Measured on *timer* time, not wall-clock, so it
    /// does not flip to overdue while the timer is sitting paused.
    var isOverdue: Bool {
        guard !state.isDone, state.targetSeconds > 0 else { return false }
        return elapsedSeconds >= state.targetSeconds
    }

    /// Accent normally; amber once the target has passed, green when finished.
    var timerColor: Color {
        if state.isDone { return .habitsDone }
        return isOverdue ? .habitsOver : accent
    }

    /// `target 2:01:00` — under the habit name.
    var statusLine: String {
        state.targetSeconds > 0 ? "target " + targetLabel(state.targetSeconds) : "no target set"
    }

    /// What the big number is counting.
    var timerCaption: String {
        if state.isDone { return "logged" }
        if isPaused { return overTargetAtPause ? "paused · over target" : "paused" }
        // How far past the target, rather than just that it's past — the big number is
        // already counting total elapsed, so this names the gap.
        if isOverdue { return "+" + targetLabel(elapsedSeconds - state.targetSeconds) + " over" }
        return state.countDown ? "remaining" : "elapsed"
    }

    private var overTargetAtPause: Bool {
        isPaused && state.targetSeconds > 0 && elapsedSeconds >= state.targetSeconds
    }

    /// The island's status line, carrying the same `$` prompt the lock screen uses.
    var islandStatus: String {
        if state.isDone { return "✓ " + loggedLabel + " logged" }
        if isPaused { return "$ paused" }
        return "$ " + statusLine
    }

    var islandStatusColor: Color {
        if state.isDone { return .habitsDone }
        return isPaused ? .habitsOver : .secondary
    }

    /// Glyph for the compact/minimal slots, where there's no room for a word: state
    /// replaces identity as soon as there's something more important to say.
    var stateGlyph: String {
        if state.isDone { return "checkmark" }
        return isPaused ? "pause.fill" : attributes.habitIcon
    }

    /// `12m logged` — the real elapsed time at log, not the target.
    var loggedLabel: String {
        guard let logged = state.loggedSeconds else { return targetLabel(state.targetSeconds) }
        let minutes = Int((logged / 60).rounded())
        return minutes >= 60 ? targetLabel(logged) : "\(minutes)m"
    }

    /// `// routine: Deep Work [4/4]` when the habit belongs to a routine, else today's count.
    var completionContext: String {
        let tally = "\(state.doneToday)/\(state.totalToday)"
        return routineName.isEmpty
            ? "// \(tally) today"
            : "// routine: \(routineName) [\(tally)]"
    }
}
