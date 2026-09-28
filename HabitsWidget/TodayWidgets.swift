import WidgetKit
import SwiftUI

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: HabitsSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: HabitsSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: HabitsSnapshot.load() ?? .placeholder)
        // The app reloads timelines on every change; this is the day-rollover backstop.
        let midnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

// MARK: - Shared bits

private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}

private extension HabitsSnapshot {
    var ratio: Double { totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount) }
    var remaining: [SnapshotHabit] { flatHabits.filter { !$0.done } }
    /// The snapshot is what the app last published — which after midnight is yesterday's
    /// day until the app runs again. Yesterday's rows must not be tappable: a tap would
    /// toggle *yesterday*, so a stale widget only reports and waits.
    var isStale: Bool { !Calendar.current.isDate(day, inSameDayAs: Date()) }
}

private func widgetTimerLabel(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    guard total > 0 else { return "--:--" }
    return total >= 3600
        ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        : String(format: "%d:%02d", total / 60, total % 60)
}

/// Terminal-styled row: `[✓] read`. The tappable form wraps it in a `ToggleHabitIntent`
/// button (iOS 17 interactive widget) — handled inside the extension.
private struct WidgetHabitLine: View {
    let habit: SnapshotHabit

    var body: some View {
        HStack(spacing: 4) {
            Text(habit.done ? "[✓]" : "[ ]")
                .font(mono(10, .semibold))
                .foregroundStyle(.primary)
            Text(habit.name)
                .font(mono(10))
                .foregroundStyle(.primary)
                .strikethrough(habit.done, color: .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    static func tappable(_ habit: SnapshotHabit, day: Date, interactive: Bool) -> some View {
        let row = WidgetHabitLine(habit: habit)
        if interactive {
            return AnyView(Button(intent: ToggleHabitIntent(habitId: habit.id, day: day, done: !habit.done)) {
                row
            }
            .buttonStyle(.plain))
        }
        return AnyView(row)
    }
}

// MARK: - Home screen widgets

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    Color(hexString: entry.snapshot.background)
                }
                .widgetURL(URL(string: "habits://open"))
        }
        .configurationDisplayName("today")
        .description("// today's progress and streaks")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: HabitsSnapshot

    private var accent: Color { Color(hexString: snapshot.accent) }
    private var comment: Color { Color(hexString: snapshot.comment) }
    private var foreground: Color { Color(hexString: snapshot.foreground) }

    var body: some View {
        if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(">").font(mono(10, .bold)).foregroundStyle(accent)
                Text(snapshot.isStale ? "yesterday" : "today").font(mono(10)).foregroundStyle(comment)
                Spacer(minLength: 0)
                if snapshot.streak > 0 {
                    Image(systemName: "flame.fill").font(.system(size: 9))
                        .foregroundStyle(Color(hexString: "#FF9F45"))
                    Text("\(snapshot.streak)").font(mono(10, .semibold)).foregroundStyle(foreground)
                }
            }
            Text("[\(snapshot.doneCount)/\(snapshot.totalCount)]")
                .font(mono(30, .bold))
                .foregroundStyle(snapshot.doneCount == snapshot.totalCount && snapshot.totalCount > 0
                                 ? Color(hexString: "#4ADE80") : accent)
                .minimumScaleFactor(0.6)
            // progress bar drawn in characters, terminal-style
            Text(bar)
                .font(mono(11, .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            if let run = snapshot.running {
                HStack(spacing: 3) {
                    Image(systemName: "timer").font(.system(size: 9)).foregroundStyle(accent)
                    Text(run.name).font(mono(9)).foregroundStyle(comment).lineLimit(1)
                    // Pauses don't count toward the elapsed time. Paused has to be a static
                    // label: Text(timerInterval:) is driven by the wall clock and cannot stop.
                    if let pausedAt = run.pausedAt {
                        Text(widgetTimerLabel(max(0, pausedAt.timeIntervalSince(run.startedAt) - run.pausedSeconds)))
                            .font(mono(9, .semibold)).foregroundStyle(foreground)
                    } else {
                        Text(timerInterval: run.startedAt.addingTimeInterval(run.pausedSeconds)...Date.distantFuture,
                             countsDown: false)
                            .font(mono(9, .semibold)).foregroundStyle(foreground)
                            .multilineTextAlignment(.leading)
                    }
                }
            } else {
                Text("// \(snapshot.remaining.count) left")
                    .font(mono(9)).foregroundStyle(comment).lineLimit(1)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text(">").font(mono(10, .bold)).foregroundStyle(accent)
                    Text(snapshot.isStale ? "yesterday" : "today").font(mono(10)).foregroundStyle(comment)
                }
                Text("[\(snapshot.doneCount)/\(snapshot.totalCount)]")
                    .font(mono(26, .bold))
                    .foregroundStyle(snapshot.doneCount == snapshot.totalCount && snapshot.totalCount > 0
                                     ? Color(hexString: "#4ADE80") : accent)
                    .minimumScaleFactor(0.6)
                Text(bar).font(mono(10, .semibold)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                if snapshot.streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 9))
                            .foregroundStyle(Color(hexString: "#FF9F45"))
                        Text("\(snapshot.streak)d").font(mono(10, .semibold)).foregroundStyle(foreground)
                    }
                }
            }
            .frame(maxWidth: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(displayed) { habit in
                    WidgetHabitLine.tappable(habit, day: snapshot.day, interactive: !snapshot.isStale)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    /// Remaining first, then whatever's left — max four lines.
    private var displayed: [SnapshotHabit] {
        let remaining = snapshot.remaining
        let shown = remaining.isEmpty ? snapshot.flatHabits : remaining
        return Array(shown.prefix(4))
    }

    /// `▓▓▓▓░░░░` — one cell per habit, filled when done.
    private var bar: String {
        guard snapshot.totalCount > 0 else { return "// no habits today" }
        let cells = min(snapshot.totalCount, 10)
        let filled = Int((snapshot.ratio * Double(cells)).rounded())
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: max(0, cells - filled))
    }
}

// MARK: - Lock screen widgets

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockWidget", provider: SnapshotProvider()) { entry in
            LockWidgetView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "habits://open"))
        }
        .configurationDisplayName("today")
        .description("// today's progress on the lock screen")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: HabitsSnapshot

    var body: some View {
        content
            // iOS 17 requires every widget to adopt containerBackground; without it the
            // system renders "Please adopt containerBackground API" in place of the widget.
            .containerBackground(for: .widget) {
                if family == .accessoryCircular {
                    AccessoryWidgetBackground()
                } else {
                    // rectangular/inline get their material from the system
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: inline
        }
    }

    private var circular: some View {
        Gauge(value: snapshot.ratio) {
            Text("habits").font(mono(8))
        } currentValueLabel: {
            Text("\(snapshot.doneCount)/\(snapshot.totalCount)")
                .font(mono(13, .bold))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(">").font(mono(11, .bold))
                Text(snapshot.isStale ? "yesterday" : "today").font(mono(11))
                Text("[\(snapshot.doneCount)/\(snapshot.totalCount)]").font(mono(11, .semibold))
                if snapshot.streak > 0 {
                    Image(systemName: "flame.fill").font(.system(size: 9))
                    Text("\(snapshot.streak)").font(mono(11, .semibold))
                }
            }
            ForEach(Array(nextUp.prefix(2))) { habit in
                WidgetHabitLine.tappable(habit, day: snapshot.day, interactive: !snapshot.isStale)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nextUp: [SnapshotHabit] {
        let remaining = snapshot.remaining
        return remaining.isEmpty ? Array(snapshot.flatHabits.suffix(2)) : remaining
    }

    private var inline: some View {
        // Accessory inline renders a single line of text — keep it terminal-brief.
        Text("habits [\(snapshot.doneCount)/\(snapshot.totalCount)]" + (snapshot.streak > 0 ? " · \(snapshot.streak)d" : ""))
    }
}
