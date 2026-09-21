import Foundation
import SwiftData

enum HabitType: String, CaseIterable, Identifiable {
    case checkbox
    case timed
    var id: String { rawValue }

    var label: String {
        switch self {
        case .checkbox: return "check-off"
        case .timed: return "timed"
        }
    }
}

enum HabitColor: String, CaseIterable, Identifiable {
    case cyan, blue, purple, red, green, amber
    var id: String { rawValue }
    var hex: String {
        switch self {
        case .cyan: return "#00D7C3"
        case .blue: return "#5AA7FF"
        case .purple: return "#C084FC"
        case .red: return "#FF6B6B"
        case .green: return "#4ADE80"
        case .amber: return "#FFB454"
        }
    }
}

@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    var subtitle: String = ""   // comment-style: "// after waking up"
    var icon: String = "sun.max"
    var sortIndex: Int = 0
    var habits: [Habit] = []

    init(name: String, subtitle: String, icon: String, sortIndex: Int) {
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.sortIndex = sortIndex
    }
}

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "circle"
    var colorRaw: String = HabitColor.cyan.rawValue
    var typeRaw: String = HabitType.checkbox.rawValue
    /// Comment-style subtitle, e.g. "// 10 min"
    var comment: String = ""
    /// Timed habits: target in seconds.
    var targetSeconds: TimeInterval = 0
    /// Comma-joined weekday indexes (1=Sun … 7=Sat) the habit is scheduled.
    var scheduleRaw: String = "1,2,3,4,5,6,7"
    var reminderMinutesFromMidnight: Int? = nil
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    /// Running timer for timed habits (nil = not running).
    var startedAt: Date? = nil
    @Relationship(inverse: \Completion.habit) var completions: [Completion] = []
    var routine: Routine? = nil

    var type: HabitType {
        get { HabitType(rawValue: typeRaw) ?? .checkbox }
        set { typeRaw = newValue.rawValue }
    }
    var color: HabitColor {
        get { HabitColor(rawValue: colorRaw) ?? .cyan }
        set { colorRaw = newValue.rawValue }
    }
    var scheduleDays: Set<Int> {
        get { Set(scheduleRaw.split(separator: ",").compactMap { Int($0) }) }
        set { scheduleRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    var targetLabel: String {
        guard type == .timed, targetSeconds > 0 else { return comment }
        let m = Int(targetSeconds) / 60
        if m >= 60 {
            let h = m / 60, r = m % 60
            return r == 0 ? "\(h)h" : "\(h)h\(r)min"
        }
        return "\(m) min"
    }

    /// Today's completion, if any.
    func completion(on day: Date, calendar: Calendar = .current) -> Completion? {
        completions.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    func formattedElapsed(since start: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    init(name: String, icon: String, color: HabitColor, type: HabitType,
         comment: String = "", targetSeconds: TimeInterval = 0) {
        self.name = name
        self.icon = icon
        self.colorRaw = color.rawValue
        self.typeRaw = type.rawValue
        self.comment = comment
        self.targetSeconds = targetSeconds
    }
}

@Model
final class Completion {
    var id: UUID = UUID()
    var day: Date = Date()          // normalized to start-of-day
    var completedAt: Date = Date()  // wall-clock timestamp
    /// checkbox: 1; timed: elapsed seconds.
    var value: Double = 1
    var sourceRaw: String = "manual"
    var habit: Habit? = nil

    var source: String {
        get { sourceRaw }
        set { sourceRaw = newValue }
    }

    init(day: Date, completedAt: Date, value: Double) {
        self.day = day.startOfDay()
        self.completedAt = completedAt
        self.value = value
    }
}

extension Date {
    func startOfDay(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: self)
    }
}