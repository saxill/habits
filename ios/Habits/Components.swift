import SwiftUI
import UIKit

// Terminal building blocks used across all tabs (§3, §5.1).

struct BracketCheckbox: View {
    let checked: Bool
    var color: Color = .white

    var body: some View {
        Text(checked ? "[✓]" : "[ ]")
            .term(13, .semibold)
            .foregroundStyle(checked ? color : Color(hex: "#6E6E73"))
            .monospacedDigit()
            // The tap lands as a small pop rather than a silent swap: it is the most-tapped
            // control in the app, and the bracket is the only feedback that it took.
            .scaleEffect(checked ? 1 : 0.92)
            .animation(.spring(response: 0.26, dampingFraction: 0.55), value: checked)
    }
}

/// Tabs step sideways: a horizontal swipe moves one tab along the strip
/// (`habits → stats → profile`), the way a paged app behaves.
///
/// The gesture lives on the tab container rather than on each screen, so there is one
/// definition for all three. Two rules keep it from stealing drags that belong to something
/// else: the swipe has to be unambiguously horizontal (every screen here is a vertical
/// scroller, so a diagonal flick is a scroll), and a view that owns a sideways drag declares
/// itself with `.tabSwipeDeadZone()` — the stats chip bar scrolls the other way, and without
/// that opt-out a flick through the chips would change tab as well.
enum TabSwipe {
    /// How far sideways a drag has to travel before it counts as a tab change.
    static let threshold: CGFloat = 70
    /// ...and how much it has to beat its own vertical travel by.
    static let dominance: CGFloat = 2
}

struct TabSwipeDeadZones: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    /// Marks a view's frame as off-limits to the tab swipe.
    ///
    /// Global coordinates, because the swipe reads its start location in the global space too —
    /// the two have to be measured the same way to be comparable.
    func tabSwipeDeadZone() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: TabSwipeDeadZones.self, value: [geo.frame(in: .global)])
        })
    }
}

/// Which tab is on screen and which way the strip moved to reach it, so the arriving screen can
/// come in from the side you travelled instead of just appearing.
///
/// `TabView` swaps its children with no transition of its own, and the arriving page cannot
/// animate itself from `onChange` — a tab that has not been rendered yet has no previous value
/// to change from. So the phase is owned by the always-installed root and handed down.
final class TabTransitions: ObservableObject {
    static let shared = TabTransitions()

    static let duration: Double = 0.22
    /// How far the arriving page travels. Small on purpose: this is a redraw, not a carousel.
    static let drift: CGFloat = 22

    @Published private(set) var selected = 0
    @Published private(set) var direction: CGFloat = 1

    func arrive(at index: Int, from previous: Int) {
        direction = index > previous ? 1 : -1
        selected = index
    }
}

/// One tab's content. `phase` is 1 when settled and 0 on the frame the tab arrives; the root
/// resets it and animates it back, which is what puts the motion in the change.
struct TabPage<Content: View>: View {
    let index: Int
    let phase: Double
    let direction: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            // Never fully transparent: a tab that vanishes for a frame reads as a flicker
            // rather than a transition.
            .opacity(0.4 + 0.6 * phase)
            .offset(x: (1 - phase) * direction * TabTransitions.drift)
    }
}

/// Swipe-right-to-go-back for a pushed screen.
///
/// The system's own interactive pop only arms within about 20pt of the left edge. Every screen
/// here hides the navigation bar, so there is nothing at that edge to suggest a gesture lives
/// there — the swipe has to be found by accident, and starting a finger's width further in
/// does nothing at all. This takes the whole screen instead, which also matches the tab swipe
/// on either side of it.
private struct InteractiveBackSwipe: ViewModifier {
    let onBack: () -> Void

    /// Fixed distances rather than fractions of the width: measuring the screen needs a
    /// `GeometryReader`, which would stretch and top-align every screen it wraps.
    private let commitDistance: CGFloat = 110
    private let flickDistance: CGFloat = 240

    @State private var dragX: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: dragX)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onChanged { value in
                        let dx = value.translation.width
                        // Rightward and mostly horizontal — a vertical drag here is a scroll,
                        // and the same rule keeps this from fighting the tab swipe.
                        guard dx > 0, dx > abs(value.translation.height) else { return }
                        dragX = dx
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        let flicked = value.predictedEndTranslation.width > flickDistance
                        guard dx > 0, dx > abs(value.translation.height),
                              dx > commitDistance || flicked
                        else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                dragX = 0
                            }
                            return
                        }
                        // Leave the offset where it is: the pop animation takes over from
                        // here, so resetting first would show the screen jump back left
                        // before it slides out.
                        onBack()
                    }
            )
    }
}

extension View {
    func interactiveBackSwipe(onBack: @escaping () -> Void) -> some View {
        modifier(InteractiveBackSwipe(onBack: onBack))
    }
}

/// Ways out of the keyboard.
///
/// Every screen here hides the navigation bar (`.toolbar(.hidden, for: .navigationBar)`), and
/// that takes iOS's own "Done" button off the keyboard with it. In a `Form` it costs nothing —
/// Forms dismiss the keyboard when you drag. On a plain `ScrollView` it costs everything: no bar
/// button, and a plain `ScrollView` does *not* dismiss on drag, so a focused field leaves the
/// keyboard with no way off screen. That was a real bug on profile's username field, which could
/// only be escaped by force-quitting the app — and every text field in the app had it.
///
/// Three exits rather than one, because each is unreachable in some case: a screen too short to
/// scroll never gets a drag, and a key on the far side of the keyboard is easy to miss. They cost
/// nothing when the keyboard is down.
@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}

extension View {
    /// Drag to dismiss — the affordance people reach for first.
    ///
    /// `.immediately`, not `.interactively`: interactive tracks the finger and only lets go once
    /// you have dragged far enough, so an ordinary scroll flick leaves the keyboard standing. It
    /// was measurably not an exit — the first version of this failed its own test. The point of
    /// the drag here is that it always works, not that it feels supple.
    func dismissesKeyboardOnDrag() -> some View {
        scrollDismissesKeyboard(.immediately)
    }

    /// Tap anywhere that is not a control to dismiss. Simultaneous, so it cannot swallow a tap
    /// some chip or row underneath was waiting for.
    func dismissesKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }

    /// A key above the keyboard, in the app's own voice. Needs a `NavigationStack`.
    ///
    /// Deliberately *not* labelled "done": `.submitLabel(.done)` already puts "done" on the
    /// Return key, so two controls would share one name and neither could be addressed on its
    /// own — which is how this was caught, by a test that could not tell them apart.
    func keyboardDoneButton(_ label: String = "[done]") -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(label) { hideKeyboard() }
                    .font(.system(size: 13, design: .monospaced))
            }
        }
    }
}

struct CommentText: View {

    @Environment(\.theme) private var theme
    let text: String
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .term(size)
            .foregroundStyle(Color(hex: theme.comment))
    }
}

/// Screen header in prompt form: `user[pro]@init.Habits $ daily`
struct PromptHeader: View {
    @AppStorage(SettingsKey.username) private var username = "user"
    @AppStorage(SettingsKey.promptSymbol) private var symbol = "$"
    let command: String
    let accent: Color
    var trailing: AnyView? = nil

    var body: some View {
        // A `trailing` slot competes for the same line, and a 15-char username plus a long
        // command can already fill it — so never let the prompt wrap. When the full prompt
        // won't fit (the larger text sizes, the profile's level badge) it drops the host,
        // like a shell with a short PS1, instead of truncating to "init.H…".
        ViewThatFits(in: .horizontal) {
            line(host: true)
            line(host: false)
        }
    }

    private func line(host: Bool) -> some View {
        HStack(spacing: 0) {
            Text(host ? "\(username)[pro]@init.Habits " : "\(username) ")
                .term(14, .semibold)
                .foregroundStyle(accent)
            Text(symbol + " ")
                .term(14, .semibold)
                .foregroundStyle(Color(hex: "#6E6E73"))
            Text(command)
                .term(14, .semibold)
                .foregroundStyle(.white)
                // The one thing every screen prints differently, so a UI test can say which
                // screen it is looking at without reading pixels.
                .accessibilityIdentifier("screen-command")
            Spacer(minLength: 4)
            trailing
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Mon–Sun week strip with per-day completion fill bars (§4.1).
struct WeekStrip: View {
    @Environment(\.theme) private var theme
    let week: [Date]
    let selected: Date
    let onSelect: (Date) -> Void
    let habits: [Habit]
    private let cal = Calendar.current

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(orderedDays.enumerated()), id: \.1) { i, day in
                dayColumn(index: i, day: day)
            }
        }
    }

    private var orderedDays: [Date] {
        // `week` is always a Monday-start week (see Date.weekDates).
        week
    }

    private func dayColumn(index: Int, day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let ratio = Streaks.dayRatio(day, habits: habits)
        let isPast = day < cal.startOfDay(for: Date())
        let isFuture = !isPast && !cal.isDateInToday(day)

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 4) {
                Text(Self.letters[index])
                    .term(10)
                    .foregroundStyle(isSelected ? theme.habitsColor : Color(hex: theme.comment))
                Text("\(cal.component(.day, from: day))")
                    .term(13, .semibold)
                    .foregroundStyle(
                        isSelected ? theme.habitsColor :
                        isFuture ? Color(hex: theme.comment) :
                        .white
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isToday && !isSelected ? theme.habitsColor.opacity(0.25) : .clear)
                    )
                    .padding(.horizontal, 6)
                // fill bar: hatched/empty = future, intensity = completion %
                RoundedRectangle(cornerRadius: 2)
                    .fill(ratio <= 0 ? Color(hex: theme.comment).opacity(0.3) : theme.habitsColor.opacity(ratio < 0 ? 0.2 : 0.35 + 0.65 * ratio))
                    .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Reusable terminal-style segmented control — plain buttons, no system Picker quirks.
struct TermSegmentBar: View {
    let options: [(id: String, label: String)]
    let selection: String
    let accent: Color
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.id) { option in
                let isSelected = option.id == selection
                Button {
                    onSelect(option.id)
                } label: {
                    Text(option.label)
                        .term(11, isSelected ? .bold : .regular)
                        .foregroundStyle(isSelected ? accent : Color(hex: "#6E6E73"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isSelected ? accent.opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        // The pill and the label weight settle rather than snap, so a range change reads as
        // the bar moving rather than the screen redrawing.
        .animation(.easeOut(duration: 0.18), value: selection)
    }
}

extension EnvironmentValues {
    var theme: TerminalTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = TerminalTheme.builtin()[0]
}

extension Date {
    /// Monday-start week containing self.
    func weekDates(calendar: Calendar = .current) -> [Date] {
        let wd = calendar.component(.weekday, from: self)
        let offset = (wd + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: self))!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
}