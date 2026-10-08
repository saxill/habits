import SwiftUI
import SwiftData

/// Cross-tab navigation. Lives outside the view tree so a URL open (or the debug commands that
/// drive it) can push a screen the same way a tap would.
///
/// Path-based rather than `navigationDestination(isPresented:)`: a flag set to true *before* the
/// stack exists is unreliable, whereas a path holding a value pushes as soon as the stack
/// appears — which is exactly the deep-link case (a launch, or a future "milestone unlocked"
/// notification, arriving before profile has ever been rendered).
final class NavRouter: ObservableObject {
    static let shared = NavRouter()

    enum Destination: Hashable { case achievements }

    @Published var path: [Destination] = []

    func openAchievements() { path = [.achievements] }
}

/// `$ achievements` — the tiers, milestones and XP total (§4.3.2).
///
/// Profile is the settings tab, so this pushes from it and keeps the same terminal chrome:
/// the bar is hidden on both screens in favour of a `[← back]` row, which is the app's own
/// idiom rather than a system nav bar in the middle of a shell.
struct AchievementsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]

    /// The snapshot walks day-by-day history, so it's derived once per render rather than
    /// per row — the walk itself indexes completions up front (see `Achievements.facts`).
    private var snapshot: Achievements.Snapshot {
        Achievements.Snapshot(habits: habits)
    }

    var body: some View {
        let snap = snapshot
        VStack(spacing: 0) {
            header(level: snap.level.xp)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LevelCard(level: snap.level)
                    tierSection(snap.metrics)
                    milestoneSection(snap)
                    CommentText(text: "// derived from your completion history")
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(hex: theme.background))
        .toolbar(.hidden, for: .navigationBar)
        // Works from anywhere on the screen, which is what makes it findable: the system's own
        // pop gesture only arms within ~20pt of the left edge, and with the bar hidden there is
        // nothing there saying so.
        .interactiveBackSwipe { dismiss() }
    }

    private func header(level: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Text("back").term(11)
                    }
                    .foregroundStyle(Color(hex: theme.comment))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("back to profile")
                Spacer()
                XPChip()
            }
            PromptHeader(command: "achievements", accent: theme.profileColor)
            Divider().overlay(Color(hex: theme.comment).opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func tierSection(_ metrics: [Achievements.MetricProgress]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CommentText(text: "// tier progress", size: 11)
            ForEach(metrics) { m in
                MetricCard(progress: m)
            }
        }
    }

    private func milestoneSection(_ snap: Achievements.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                CommentText(text: "// milestones", size: 11)
                Spacer()
                // `verbatim`: Text's localized interpolation would render "+1,000" with a
                // grouping separator, and a shell prints numbers without one.
                Text(verbatim: "\(snap.earnedMilestones)/\(snap.milestones.count)")
                    .term(11, .semibold)
                    .foregroundStyle(theme.profileColor)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(snap.milestones) { m in
                    MilestoneRow(state: m)
                }
            }
        }
    }
}

// MARK: - Shared bits

/// `[lvl 4] 412xp` — the global XP total, in the profile header and here.
struct XPChip: View {
    @Environment(\.theme) private var theme
    @Query(sort: [SortDescriptor(\Habit.createdAt)]) private var habits: [Habit]

    var body: some View {
        let level = Achievements.Snapshot(habits: habits).level
        HStack(spacing: 5) {
            Text(verbatim: "[lvl \(level.level)]")
                .term(11, .semibold)
                .foregroundStyle(theme.profileColor)
            Text(verbatim: "\(level.xp)xp")
                .term(11)
                .foregroundStyle(Color(hex: theme.comment))
                .monospacedDigit()
        }
    }
}

/// Thin fill bar, matching the stats screen's completion bar.
struct TermBar: View {
    @Environment(\.theme) private var theme
    let fraction: Double
    let accent: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: theme.comment).opacity(0.25))
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Level card

private struct LevelCard: View {
    @Environment(\.theme) private var theme
    let level: Achievements.LevelInfo

    /// The bar fills on arrival rather than sitting full — the one moment the screen has to
    /// show the number meaning something.
    @State private var shown: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(verbatim: "[lvl \(level.level)]")
                    .term(20, .bold)
                    .foregroundStyle(theme.profileColor)
                Spacer()
                Text(verbatim: "\(level.xp) xp")
                    .term(13, .semibold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            TermBar(fraction: shown, accent: theme.profileColor)
            HStack(spacing: 0) {
                Text(verbatim: "\(level.intoLevel)/\(level.levelSpan) xp")
                    .term(11)
                    .foregroundStyle(Color(hex: theme.comment))
                    .monospacedDigit()
                Spacer()
                Text(verbatim: "\(level.toNextLevel) to lvl \(level.level + 1)")
                    .term(11)
                    .foregroundStyle(Color(hex: theme.comment))
                    .monospacedDigit()
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.profileColor.opacity(0.45), lineWidth: 0.5))
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { shown = level.fraction } }
        .onChange(of: level.fraction) { _, target in
            withAnimation(.easeOut(duration: 0.5)) { shown = target }
        }
    }
}

// MARK: - One metric's tier ladder

private struct MetricCard: View {
    @Environment(\.theme) private var theme
    let progress: Achievements.MetricProgress

    private var accent: Color { theme.profileColor }

    /// Same fill-on-arrival as the level bar, staggered a little so the four cards do not all
    /// snap at once.
    @State private var shown: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(progress.metric.label)
                    .term(13)
                    .foregroundStyle(.white)
                Spacer()
                Text(verbatim: "\(progress.current)")
                    .term(15, .bold)
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }
            CommentText(text: progress.metric.comment, size: 11)
            TermBar(fraction: shown, accent: accent)
            tierLadder
            HStack(spacing: 0) {
                Text(progress.transition)
                    .term(11, .semibold)
                    .foregroundStyle(progress.isMaxed ? accent : Color(hex: theme.foreground))
                Spacer()
                Text(targetLabel)
                    .term(11)
                    .foregroundStyle(Color(hex: theme.comment))
                    .monospacedDigit()
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.06)) { shown = progress.fraction }
        }
        .onChange(of: progress.fraction) { _, target in
            withAnimation(.easeOut(duration: 0.5)) { shown = target }
        }
    }

    /// `63/150 · +150 xp`, or the tally once the ladder is finished.
    private var targetLabel: String {
        guard let threshold = progress.nextThreshold, let reward = progress.nextReward else {
            return "maxed · \(progress.xpEarned)xp"
        }
        return "\(progress.current)/\(threshold) · +\(reward) xp"
    }

    private var tierLadder: some View {
        HStack(spacing: 4) {
            ForEach(Achievements.Tier.allCases) { tier in
                let earned = progress.earnedTiers.contains(tier)
                let isNext = progress.nextTier == tier
                Text(earned ? "✓\(tier.name)" : tier.name)
                    .term(10, earned ? .semibold : .regular)
                    .foregroundStyle(
                        earned ? accent
                        : isNext ? Color(hex: theme.foreground)
                        : Color(hex: theme.comment)
                    )
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(earned ? accent.opacity(0.16) : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                earned ? accent.opacity(0.5)
                                : isNext ? Color(hex: theme.comment).opacity(0.7)
                                : Color(hex: theme.comment).opacity(0.25),
                                lineWidth: 0.5
                            )
                    )
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("tier: \(progress.transition)")
    }
}

// MARK: - Milestone row

private struct MilestoneRow: View {
    @Environment(\.theme) private var theme
    let state: Achievements.MilestoneState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(state.earned ? "[✓]" : "[ ]")
                .term(12, .semibold)
                .foregroundStyle(state.earned ? theme.profileColor : Color(hex: theme.comment))
            VStack(alignment: .leading, spacing: 1) {
                Text(state.name)
                    .term(12, state.earned ? .semibold : .regular)
                    .foregroundStyle(state.earned ? .white : Color(hex: theme.comment))
                CommentText(text: state.comment, size: 10)
            }
            Spacer(minLength: 8)
            Text(verbatim: "+\(state.xp)")
                .term(11, .semibold)
                .foregroundStyle(
                    state.earned ? theme.profileColor : Color(hex: theme.comment).opacity(0.7)
                )
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.name), \(state.earned ? "earned" : "locked")")
    }
}
