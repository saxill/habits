import SwiftUI

/// Profile tab — appearance settings (§4.3.1). Achievements ship in v2 per PRD §10.
struct ProfileView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var store = ThemeStore.shared
    @AppStorage(SettingsKey.username) private var username = "user"
    @AppStorage(SettingsKey.themeId) private var themeId = TerminalTheme.builtin()[0].id
    @AppStorage(SettingsKey.promptSymbol) private var promptSymbol = "$"
    @AppStorage(SettingsKey.textSize) private var textSize = 0
    @AppStorage(SettingsKey.crossOutCompleted) private var crossOut = true
    @AppStorage(SettingsKey.moveCompletedToBottom) private var moveBottom = false
    @AppStorage(SettingsKey.liveActivitiesEnabled) private var laEnabled = true
    @AppStorage(SettingsKey.laShowTimer) private var laShowTimer = true
    @AppStorage(SettingsKey.laShowProgress) private var laShowProgress = true
    @AppStorage(SettingsKey.laShowName) private var laShowName = true
    @State private var editingTheme: TerminalTheme?

    private static let symbols = ["$", "%", "#", ">"]

    /// [foreground, comment, habits-accent, stats-accent, profile-accent].
    private static func swatches(for t: TerminalTheme) -> [String] {
        [t.foreground, t.comment, t.habitsAccent, t.statsAccent, t.profileAccent]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewCard
                    identitySection
                    themeSection
                    promptSection
                    textSection
                    completedSection
                    liveActivitySection
                    CommentText(text: "// achievements & xp ship in v2")
                }
                .padding(16)
            }
        }
        .background(Color(hex: theme.background))
        .sheet(item: $editingTheme) { t in
            ThemeEditorView(theme: t)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            PromptHeader(command: "appearance", accent: theme.profileColor)
            Divider().overlay(Color(hex: theme.comment).opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // Live preview of a habit row reflecting current settings.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            CommentText(text: "// preview", size: 11)
            HStack(spacing: 10) {
                Text("[✓]").term(13, .semibold).foregroundStyle(theme.profileColor)
                Image(systemName: "figure.run")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.habitsColor)
                Text("morning run")
                    .term(13)
                    .foregroundStyle(.white)
                    .strikethrough(crossOut)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(hex: "#FF9F45"))
                    Text("7").term(11).monospacedDigit()
                }
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: theme.comment).opacity(0.3), lineWidth: 0.5))
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            CommentText(text: "// identity", size: 11)
            HStack {
                TextField("username", text: $username)
                    .term(13)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: username) { _, v in
                        if v.count > 15 { username = String(v.prefix(15)) }
                    }
                Text("\(username.count)/15")
                    .term(11)
                    .foregroundStyle(Color(hex: theme.comment))
            }
            .padding(.vertical, 6)
            Divider().overlay(Color(hex: theme.comment).opacity(0.3))
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// theme", size: 11)
            ForEach(store.all) { t in
                HStack(spacing: 10) {
                    Button {
                        themeId = t.id
                    } label: {
                        HStack(spacing: 10) {
                            Text(themeId == t.id ? "[✓]" : "[ ]").term(13, .semibold)
                                .foregroundStyle(theme.profileColor)
                            Text(t.name).term(13).foregroundStyle(.white)
                            Spacer()
                            // ANSI-style swatch dots
                            HStack(spacing: 3) {
                                ForEach(Self.swatches(for: t), id: \.self) { hex in
                                    Circle().fill(Color(hex: hex)).frame(width: 9, height: 9)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // edit / copy / delete controls
                    Button {
                        editingTheme = t.isCustom ? t : ThemeStore.duplicate(t)
                    } label: {
                        Image(systemName: t.isCustom ? "slider.horizontal.3" : "doc.on.doc")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.profileColor.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.isCustom ? "edit theme" : "duplicate theme")

                    if t.isCustom {
                        Button {
                            if themeId == t.id { themeId = TerminalTheme.builtin()[0].id }
                            store.delete(t)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(hex: "#FF6B6B").opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("delete theme")
                    }
                }
            }
            Button {
                let fresh = ThemeStore.duplicate(store.byId(themeId))
                store.upsert(fresh)
                editingTheme = fresh
            } label: {
                CommentText(text: "+ new theme from current", size: 12)
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// prompt symbol", size: 11)
            HStack(spacing: 14) {
                ForEach(Self.symbols, id: \.self) { s in
                    Button {
                        promptSymbol = s
                    } label: {
                        Text(promptSymbol == s ? "[\(s)]" : "[ ]")
                            .term(13, .semibold)
                            .foregroundStyle(promptSymbol == s ? theme.profileColor : Color(hex: theme.comment))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// text", size: 11)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { tier in
                    Button {
                        textSize = tier
                    } label: {
                        Text(["default", "larger", "largest"][tier])
                            .term(12, textSize == tier ? .bold : .regular)
                            .foregroundStyle(textSize == tier ? theme.profileColor : Color(hex: theme.comment))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(textSize == tier ? theme.profileColor : Color(hex: theme.comment).opacity(0.4), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            CommentText(text: "// font: SF Mono (system)", size: 11)
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// completed habits", size: 11)
            Toggle(isOn: $crossOut) {
                Text("cross out completed").term(13).foregroundStyle(.white)
            }
            .tint(theme.profileColor)
            Toggle(isOn: $moveBottom) {
                Text("move completed to bottom").term(13).foregroundStyle(.white)
            }
            .tint(theme.profileColor)
        }
    }

    private var liveActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentText(text: "// live activities", size: 11)
            Toggle(isOn: $laEnabled) {
                Text("enable live activities").term(13).foregroundStyle(.white)
            }
            .tint(theme.profileColor)
            .onChange(of: laEnabled) { _, on in
                if !on { LiveActivityController.shared.stop(done: false) }
            }
            if laEnabled {
                Toggle(isOn: $laShowTimer) {
                    Text("show elapsed timer").term(13).foregroundStyle(.white)
                }
                .tint(theme.profileColor)
                Toggle(isOn: $laShowProgress) {
                    Text("show progress bar").term(13).foregroundStyle(.white)
                }
                .tint(theme.profileColor)
                Toggle(isOn: $laShowName) {
                    Text("show habit name").term(13).foregroundStyle(.white)
                }
                .tint(theme.profileColor)
                CommentText(text: "// rendered on the dynamic island & lock screen", size: 11)
            }
        }
    }
}

// MARK: - Theme color editor

struct ThemeEditorView: View {
    @Environment(\.theme) private var activeTheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ThemeStore.shared
    @State var theme: TerminalTheme
    private let isNew: Bool

    init(theme: TerminalTheme) {
        // Editing an unsaved duplicate: give it a stable identity only if it's new.
        _theme = State(initialValue: theme)
        isNew = theme.id.hasPrefix("custom-") && !ThemeStore.shared.all.contains { $0.id == theme.id }
    }

    private struct Row: Identifiable {
        let label: String
        let keyPath: WritableKeyPath<TerminalTheme, String>
        var id: String { label }
    }
    private let rows: [Row] = [
        Row(label: "background", keyPath: \.background),
        Row(label: "foreground", keyPath: \.foreground),
        Row(label: "comment", keyPath: \.comment),
        Row(label: "habits accent", keyPath: \.habitsAccent),
        Row(label: "stats accent", keyPath: \.statsAccent),
        Row(label: "profile accent", keyPath: \.profileAccent),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("name") {
                    TextField("theme name", text: $theme.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("colors") {
                    ForEach(rows) { row in
                        colorRow(row)
                    }
                }
                // Live sample strip using the draft colors.
                Section {
                    HStack(spacing: 10) {
                        Text("[✓]").font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: theme.habitsAccent))
                        Image(systemName: "timer")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color(hex: theme.habitsAccent))
                        Text("morning run")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color(hex: theme.foreground))
                        CommentText(text: "// sample")
                        Spacer()
                        Text("🔥").font(.system(size: 12))
                    }
                    .listRowBackground(Color(hex: theme.background))
                }
            }
            .navigationTitle(isNew ? "new theme" : "edit theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        if theme.name.trimmingCharacters(in: .whitespaces).isEmpty { theme.name = "custom" }
                        store.upsert(theme)
                        dismiss()
                    }
                }
            }
            .background(Color(hex: theme.background))
        }
    }

    private func colorRow(_ row: Row) -> some View {
        let binding = Binding<String>(
            get: { theme[keyPath: row.keyPath] },
            set: { theme[keyPath: row.keyPath] = $0 }
        )
        let colorBinding = Binding<Color>(
            get: { Color(hex: theme[keyPath: row.keyPath]) },
            set: { theme[keyPath: row.keyPath] = $0.hexString }
        )
        return HStack {
            Text(row.label).term(12).foregroundStyle(.primary)
            Spacer()
            Text(theme[keyPath: row.keyPath])
                .term(11)
                .foregroundStyle(.secondary)
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
        }
    }
}
