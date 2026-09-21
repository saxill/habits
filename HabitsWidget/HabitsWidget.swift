import WidgetKit
import SwiftUI
import ActivityKit

/// Widget bundle: single live-activity widget — the running timed habit
/// on the Dynamic Island + lock screen.
@main
struct HabitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimerLiveActivity()
    }
}

private extension Color {
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
}

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen / banner
            lockScreenView(context)
                .padding(15)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer").font(.system(size: 22)).foregroundStyle(Color(hexString: context.attributes.colorHex))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        if context.state.showName {
                            Text(context.attributes.habitName)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        if context.state.showProgress {
                            ProgressView(
                                timerInterval: context.state.startDate
                                    ... (context.state.startDate + context.state.targetSeconds),
                                countsDown: false
                            )
                            .tint(Color(hexString: context.attributes.colorHex))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsedText(context)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hexString: context.attributes.colorHex))
                        .monospacedDigit()
                        .frame(maxWidth: 72)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                elapsedText(context)
                    .font(.system(size: 12, design: .monospaced))
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer")
            }
            .widgetURL(URL(string: "habits://open"))
        }
    }

    private func elapsedText(_ context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        if context.state.isDone {
            return AnyView(Text("done ✓"))
        } else if context.state.showTimer {
            return AnyView(Text(
                timerInterval: context.state.startDate...Date.distantFuture,
                countsDown: false
            ))
        } else {
            // timer hidden: show the target as static text instead
            let total = Int(context.state.targetSeconds)
            let text = total >= 3600
                ? String(format: "/%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
                : String(format: "/%02d:%02d", total / 60, total % 60)
            return AnyView(Text(text))
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<TimerActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer").font(.system(size: 24)).foregroundStyle(Color(hexString: context.attributes.colorHex))
            VStack(alignment: .leading, spacing: 4) {
                if context.state.showName {
                    Text(context.attributes.habitName)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                if context.state.showProgress {
                    ProgressView(
                        timerInterval: context.state.startDate
                            ... (context.state.startDate + context.state.targetSeconds),
                        countsDown: false
                    )
                    .tint(Color(hexString: context.attributes.colorHex))
                }
            }
            Spacer()
            elapsedText(context)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color(hexString: context.attributes.colorHex))
        }
    }
}