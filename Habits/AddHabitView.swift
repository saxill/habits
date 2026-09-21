import SwiftUI
import SwiftData

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

    private static let iconChoices = [
        "figure.run", "figure.flexibility", "book", "brain.head.profile",
        "drop", "square.and.pencil", "moon.zzz", "iphone.slash",
        "fork.knife", "bicycle", "music.note", "laptopcomputer",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("name") {
                    TextField("habit name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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
                }
                Section("routine") {
                    Picker("routine", selection: $routineId) {
                        Text("none").tag(UUID?.none)
                        ForEach(routines) { r in
                            Text(r.name).tag(UUID?.some(r.id))
                        }
                    }
                }
            }
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
                                    h.startedAt = nil
                                    LiveActivityController.shared.stop(done: false)
                                }
                                h.type = type
                            }
                            if type == .timed { h.targetSeconds = TimeInterval(targetMinutes * 60) }
                            h.comment = comment.isEmpty ? "" : "// \(comment)"
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
                            if let rid = routineId, let r = routines.first(where: { $0.id == rid }) {
                                habit.routine = r
                                r.habits.append(habit)
                            }
                            modelContext.insert(habit)
                        }
                        try? modelContext.save()
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
            } else if routineId == nil {
                routineId = routines.first?.id
            }
        }
    }
}