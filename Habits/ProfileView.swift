import SwiftUI

/// Profile tab — appearance settings (§4.3.1). Achievements ship in v2 per PRD §10.
struct ProfileView: View {
    @Environment(\.theme) private var theme
    @AppStorage(SettingsKey.username) private var username = "user"
    @AppStorage(SettingsKey.themeId) private var themeId = TerminalTheme.all[0].id
    @AppStorage(SettingsKey.promptSymbol) private var promptSymbol = "$"
    @AppStorage(SettingsKey.textSize) private var textSize = 0
    @AppStorage(SettingsKey.crossOutCompleted) private var crossOut = true
    @AppStorage(SettingsKey.moveCompletedToBottom) private var moveBottom = false

    private static let symbols = ["$", "%", "#", ">"]

    /// [foreground, comment, habits-accent, stats-accent, profile-accent] per theme.
    private static func swatches(for t: TerminalTheme) -> [String] {
        switch t.id {
        case "dracula":
            return [t.foreground, t.comment, "#FFB86C", "#50FA7B", "#FF79C6"]
        case "solarized-dark":
            return [t.foreground, t.comment, "#B58900", "#859900", "#D33682"]
        default:
            return [t.foreground, t.comment, "#FFB454", "#4ADE80", "#FF6BD6"]
        }
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
                    CommentText(text: "// achievements & xp ship in v2")
                }
                .padding(16)
            }
        }
        .background(Color(hex: theme.background))
    }

    private var header: some View {
        VStack(spacing: 10) {
            PromptHeader(command: "appearance", accent: TabAccent.profile)
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
                Text("[✓]").term(13, .semibold).foregroundStyle(TabAccent.profile)
                Image(systemName: "figure.run")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(TabAccent.habits)
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
            ForEach(TerminalTheme.all) { t in
                Button {
                    themeId = t.id
                } label: {
                    HStack(spacing: 10) {
                        Text(themeId == t.id ? "[✓]" : "[ ]").term(13, .semibold)
                            .foregroundStyle(TabAccent.profile)
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
                            .foregroundStyle(promptSymbol == s ? TabAccent.profile : Color(hex: theme.comment))
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
                            .foregroundStyle(textSize == tier ? TabAccent.profile : Color(hex: theme.comment))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(textSize == tier ? TabAccent.profile : Color(hex: theme.comment).opacity(0.4), lineWidth: 0.5))
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
            .tint(TabAccent.profile)
            Toggle(isOn: $moveBottom) {
                Text("move completed to bottom").term(13).foregroundStyle(.white)
            }
            .tint(TabAccent.profile)
        }
    }
}
