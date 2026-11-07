import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let message): message
        }
    }
}

@main
struct TypographyPreferencesHostTests {
    static func main() throws {
        try migrationFillsOnlyMissingAppGroups()
        try migrationCopiesChatToneOnlyOnce()
        try appAndChatFacesStayIndependent()
        try groupFacesStayIndependentAndInherit()
        try structuredChatStylesUseChatGroups()
        try richChatRunsUseTheirOwnGroups()
        try thinkingRunsStayInThinkingGroup()
        print("PASS typography preferences")
    }

    private static func thinkingRunsStayInThinkingGroup() throws {
        for bold in [false, true] {
            for code in [false, true] {
                try expect(TypographyPreferences.chatRunGroup(base: "thinking", bold: bold, code: code) == "thinking", "thinking run escaped its font group")
            }
        }
    }

    private static func richChatRunsUseTheirOwnGroups() throws {
        try expect(TypographyPreferences.chatRunGroup(base: "body", bold: true, code: false) == "emphasis", "bold table text bypasses emphasis")
        try expect(TypographyPreferences.chatRunGroup(base: "body", bold: false, code: true) == "mono", "inline table code bypasses mono")
        try expect(TypographyPreferences.chatRunGroup(base: "body", bold: true, code: true) == "mono", "bold code must remain code")
        try expect(TypographyPreferences.chatRunGroup(base: "heading", bold: true, code: false) == "heading", "heading must retain its group")
        try expect(TypographyPreferences.chatRunGroup(base: "body", bold: false, code: false) == "body", "plain table text must retain body")
    }

    private static func structuredChatStylesUseChatGroups() throws {
        for style in ["titleLarge", "taskTitle", "title", "heatmapCount"] {
            try expect(TypographyPreferences.chatGroup(forTextStyle: style) == "heading", "heading bypasses chat settings: \(style)")
        }
        for style in ["input", "body", "listTitle", "row"] {
            try expect(TypographyPreferences.chatGroup(forTextStyle: style) == "body", "body bypasses chat settings: \(style)")
        }
        for style in ["action", "meta", "caption", "micro"] {
            try expect(TypographyPreferences.chatGroup(forTextStyle: style) == "meta", "metadata bypasses chat settings: \(style)")
        }
    }

    private static func migrationFillsOnlyMissingAppGroups() throws {
        let defaults = isolatedDefaults("groups")
        defaults.set("xlarge", forKey: TypographyPreferences.legacyGlobalScaleKey)
        defaults.set("small", forKey: TypographyPreferences.appScaleKey("heading"))

        TypographyPreferences.migrateIfNeeded(defaults)

        try expect(defaults.string(forKey: TypographyPreferences.appScaleKey("heading")) == "small",
                   "migration overwrote an existing group")
        for group in ["subheading", "body", "secondary", "tertiary"] {
            try expect(defaults.string(forKey: TypographyPreferences.appScaleKey(group)) == "xlarge",
                       "migration did not fill missing \(group) from legacy global scale")
        }
    }

    private static func migrationCopiesChatToneOnlyOnce() throws {
        let defaults = isolatedDefaults("tone")
        defaults.set("paper", forKey: TypographyPreferences.toneKey(for: .app))

        TypographyPreferences.migrateIfNeeded(defaults)
        try expect(defaults.string(forKey: TypographyPreferences.toneKey(for: .chat)) == "paper",
                   "first migration did not preserve the visible chat tone")

        defaults.set("cream", forKey: TypographyPreferences.toneKey(for: .app))
        TypographyPreferences.migrateIfNeeded(defaults)
        try expect(defaults.string(forKey: TypographyPreferences.toneKey(for: .chat)) == "paper",
                   "later app tone change leaked into chat")
    }

    private static func appAndChatFacesStayIndependent() throws {
        let defaults = isolatedDefaults("faces")
        defaults.set("onest", forKey: TypographyPreferences.faceKey(for: .app))
        defaults.set("golos", forKey: TypographyPreferences.faceKey(for: .chat))

        try expect(defaults.string(forKey: TypographyPreferences.faceKey(for: .app)) == "onest",
                   "app face key resolved to the chat value")
        try expect(defaults.string(forKey: TypographyPreferences.faceKey(for: .chat)) == "golos",
                   "chat face key resolved to the app value")
        try expect(TypographyPreferences.faceKey(for: .app) != TypographyPreferences.faceKey(for: .chat),
                   "app and chat face keys are identical")
    }

    private static func groupFacesStayIndependentAndInherit() throws {
        let defaults = isolatedDefaults("group-faces")
        defaults.set("onest", forKey: TypographyPreferences.faceKey(for: .app))
        defaults.set("golos", forKey: TypographyPreferences.faceKey(for: .chat))
        try expect(TypographyPreferences.faceRaw(for: .app, group: "heading", defaults: defaults) == "onest", "unset app group lost legacy face")
        TypographyPreferences.saveFaceRaw("lora", for: .app, group: "heading", defaults: defaults)
        TypographyPreferences.saveFaceRaw("mono", for: .chat, group: "body", defaults: defaults)
        try expect(TypographyPreferences.faceRaw(for: .app, group: "heading", defaults: defaults) == "lora", "heading face not saved")
        try expect(TypographyPreferences.faceRaw(for: .app, group: "body", defaults: defaults) == "onest", "heading change leaked into body")
        try expect(TypographyPreferences.faceRaw(for: .chat, group: "body", defaults: defaults) == "mono", "chat body face not saved")
        try expect(TypographyPreferences.faceRaw(for: .chat, group: "heading", defaults: defaults) == "golos", "app face leaked into chat")
        try expect(TypographyPreferences.faceRaw(for: .chat, group: "mono", defaults: defaults) == "system", "legacy code font changed unexpectedly")
        TypographyPreferences.saveFaceRaw("onest", for: .chat, group: "mono", defaults: defaults)
        try expect(TypographyPreferences.faceRaw(for: .chat, group: "mono", defaults: defaults) == "onest", "code group cannot select its own face")
        try expect(defaults.string(forKey: TypographyPreferences.faceKey(for: .app)) == "onest", "group save overwrote global face")
        TypographyPreferences.saveFaceRaw(nil, for: .app, group: "heading", defaults: defaults)
        try expect(TypographyPreferences.faceRaw(for: .app, group: "heading", defaults: defaults) == "onest", "inherit reset failed")
    }

    private static func isolatedDefaults(_ suffix: String) -> UserDefaults {
        let suite = "TaskFlow.TypographyPreferencesTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure.mismatch(message) }
    }
}
