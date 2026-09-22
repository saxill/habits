#if DEBUG
import Foundation

/// Debug-only tracing that survives on-device inspection: writes to a plain file in the
/// app group (not UserDefaults, which the prefs daemon caches across processes).
enum HabitsDebugLog {
    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HabitsShared.appGroup)?
            .appendingPathComponent("debug.log")
    }

    static func append(_ message: String) {
        guard let url else { return }
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Remote test hooks. The Mac can drop a file into the app group with
    /// `xcrun devicectl device copy to … --destination cmd.start-timer`; a debug build
    /// acts on it at launch and removes it, so one file means one run. Returns the file's
    /// trimmed contents (empty string if the file was empty).
    static func consumeCommand(_ name: String) -> String? {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: HabitsShared.appGroup)
        else { return nil }
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: url)
        append("cmd: consumed \(name) (\(body.trimmingCharacters(in: .whitespacesAndNewlines)))")
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
