import SwiftUI
import SwiftData
import UIKit

/// Create/edit a habit: name, SF Symbol icon, color, type (check-off/timed), target, routine.
/// Pass `habit` to edit an existing one in place; nil creates a new habit.
struct AddHabitView: View {
    var habit: Habit? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.sortIndex)]) private var routines: [Routine]

    @State private var name = ""
    @State private var icon = "circle"
    @State private var color: HabitColor = .cyan
    @State private var type: HabitType = .checkbox
    @State private var targetMinutes = 10
    @State private var comment = ""
    @State private var routineId: UUID?
    @State private var loaded = false
    /// Reminder time, as minutes from midnight — the unit the model stores. Kept as a `Date`
    /// here only so the picker can bind to it; the conversion happens at the edges.
    @State private var reminderOn = false
    @State private var reminderTime = AddHabitView.defaultReminderTime()
    @State private var permissionBlocked = false

    private static let iconChoices = [
        "figure.run", "figure.flexibility", "book", "brain.head.profile",
        "drop", "square.and.pencil", "moon.zzz", "iphone.slash",
        "fork.knife", "bicycle", "music.note", "laptopcomputer",
    ]

    /// 08:00 — a morning nudge is the common case, and a sensible thing to find already set when
    /// the reminder is first switched on.
    private static func defaultReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// Minutes from midnight, the unit the model stores.
    private var reminderMinutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        return (c.hour ?? 8) * 60 + (c.minute ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("name") {
                    TextField("habit name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                Section("icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(Self.iconChoices, id: \.self) { i in
                            Button {
                                icon = i
                            } label: {
                                Image(systemName: i)
                                    .font(.system(size: 16, design: .monospaced))
                                    .frame(width: 40, height: 36)
                                    .foregroundStyle(icon == i ? theme.habitsColor : .secondary)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(icon == i ? theme.habitsColor.opacity(0.15) : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("color") {
                    HStack(spacing: 12) {
                        ForEach(HabitColor.allCases) { c in
                            Button {
                                color = c
                            } label: {
                                Circle()
                                    .fill(Color(hex: c.hex))
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(.white, lineWidth: color == c ? 1.5 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("type") {
                    TermSegmentBar(
                        options: HabitType.allCases.map { (id: $0.rawValue, label: $0.label) },
                        selection: type.rawValue,
                        accent: theme.habitsColor
                    ) { selectedId in
                        type = HabitType(rawValue: selectedId) ?? .checkbox
                    }
                    if type == .timed {
                        Stepper("target: \(targetMinutes) min", value: $targetMinutes, in: 1...480, step: 5)
                            .monospacedDigit()
                    }
                }
                Section("comment (optional)") {
                    TextField("// e.g. after waking up", text: $comment)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                Section("routine") {
                    Picker("routine", selection: $routineId) {
                        Text("none").tag(UUID?.none)
                        ForEach(routines) { r in
                            Text(r.name).tag(UUID?.some(r.id))
                        }
                    }
                }
                Section("reminder") {
                    Toggle("remind me", isOn: $reminderOn)
                    if reminderOn {
                        DatePicker("at", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        Text("fires on the days this habit is scheduled")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if permissionBlocked {
                            // A toggle that silently flips back is the worst version of this
                            // screen: the setting looks broken and there is nowhere to go. The
                            // permission is gone for good until it is changed in Settings, and
                            // iOS will not ask twice, so say that and offer the way there.
                            Button("notifications are off — open settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(habit == nil ? "new habit" : "edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(habit == nil ? "add" : "save") {
                        if let h = habit {
                            h.name = name.isEmpty ? "untitled" : name
                            h.icon = icon
                            h.color = color
                            if h.type != type {
                                // demoting to checkbox ends any running timer
                                if type == .checkbox {
                                    h.clearTimer()
                                    LiveActivityController.shared.stop(habitId: h.id, done: false)
                                }
                                h.type = type
                            }
                            if type == .timed { h.targetSeconds = TimeInterval(targetMinutes * 60) }
                            h.comment = comment.isEmpty ? "" : "// \(comment)"
                            h.reminderMinutesFromMidnight = reminderOn ? reminderMinutes : nil
                            let newRoutine = routineId.flatMap { rid in routines.first { $0.id == rid } }
                            if h.routine?.id != newRoutine?.id {
                                h.routine?.habits.removeAll { $0.id == h.id }
                                h.routine = newRoutine
                                newRoutine?.habits.append(h)
                            }
                        } else {
                            let habit = Habit(
                                name: name.isEmpty ? "untitled" : name,
                                icon: icon, color: color, type: type,
                                comment: comment.isEmpty ? "" : "// \(comment)"
                            )
                            if type == .timed { habit.targetSeconds = TimeInterval(targetMinutes * 60) }
                            habit.reminderMinutesFromMidnight = reminderOn ? reminderMinutes : nil
                            if let rid = routineId, let r = routines.first(where: { $0.id == rid }) {
                                habit.routine = r
                                r.habits.append(habit)
                            }
                            modelContext.insert(habit)
                        }
                        try? modelContext.save()
                        // Rebuilds the schedule from what was just saved, so editing a time
                        // replaces the old notification instead of adding a second one.
                        HabitReminders.sync()
                        SnapshotPublisher.publish(context: modelContext)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let h = habit {
                name = h.name
                icon = h.icon
                color = h.color
                type = h.type
                targetMinutes = max(1, Int(h.targetSeconds) / 60)
                comment = h.comment.replacingOccurrences(of: "// ", with: "")
                routineId = h.routine?.id
                if let minutes = h.reminderMinutesFromMidnight {
                    reminderOn = true
                    reminderTime = Calendar.current.date(
                        bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                    ) ?? Self.defaultReminderTime()
                }
            } else if routineId == nil {
                routineId = routines.first?.id
            }
        }
        .onChange(of: reminderOn) { _, on in
            guard on else { return }
            // Asked for here rather than at launch: the reminder screen is the only place the
            // request makes sense, and a prompt with no context behind it is the one people
            // reflexively deny — which iOS then never asks again.
            Task {
                let granted = await WaterReminders.requestAuthorization()
                if !granted {
                    let status = await WaterReminders.authorizationStatus()
                    // Denied outright, or dismissed? A dismissal can be asked about again later,
                    // so only a real denial is a dead end worth pointing at Settings.
                    reminderOn = !(status == .denied)
                    permissionBlocked = status == .denied
                }
            }
        }
    }
}