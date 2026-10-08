import Foundation

/// When a live activity is ended on purpose — the ✓/✕ buttons or the app's stop — the app
/// wants its dismissal policy to play out (a finished timer lingers on "done ✓"). But the
/// next snapshot publish sees no running timer and would sweep it as an orphan, re-ending
/// it with `.immediate` and eating that confirmation. This short window says "the end you
/// are about to see was deliberate; leave it alone".
///
/// It lives in `Shared/` because the button intents run in the app's process and need to
/// stamp the same value the sweep reads.
enum LiveActivityGrace {
    /// How long a finished timer's completion card stays up before dismissing itself.
    /// Shared so the lock screen's ✓ and the app's own stop leave the card up equally long —
    /// they used to differ (20s vs 30s), which made the same card behave two ways.
    static let doneLinger: TimeInterval = 25

    /// Slack on top of `doneLinger` before the sweep is allowed again, so the dismissal has
    /// certainly finished by the time the next publish starts tidying up.
    static let doneGrace: TimeInterval = doneLinger + 20
    static let discardGrace: TimeInterval = 15

    private static var suppressedUntil: Date = .distantPast

    static func suppressSweep(for seconds: TimeInterval) {
        suppressedUntil = Date().addingTimeInterval(seconds)
    }

    /// False while a deliberate dismissal is still playing out.
    static var sweepAllowed: Bool { Date() >= suppressedUntil }
}
