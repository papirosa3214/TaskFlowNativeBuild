import Foundation

enum TypographyContext: String, CaseIterable, Identifiable {
    case app
    case chat

    var id: String { rawValue }
}

enum TypographyPreferences {
    static func chatRunGroup(base: String, bold: Bool, code: Bool) -> String {
        if code { return "mono" }
        if bold && base == "body" { return "emphasis" }
        return base
    }

    /// Семантические стили общих компонентов внутри ленты читают шкалу чата.
    static func chatGroup(forTextStyle style: String) -> String {
        switch style {
        case "titleLarge", "taskTitle", "title", "heatmapCount": "heading"
        case "action", "meta", "caption", "micro": "meta"
        default: "body"
        }
    }

    static let legacyGlobalScaleKey = "taskflow_text_scale"
    private static let migrationKey = "taskflow_typography_contexts_migrated_v1"

    static func toneKey(for context: TypographyContext) -> String {
        switch context {
        case .app: "taskflow_text_tone"
        case .chat: "taskflow_chat_text_tone"
        }
    }

    static func faceKey(for context: TypographyContext) -> String {
        switch context {
        case .app: "taskflow_type_face"
        case .chat: "taskflow_chat_type_face"
        }
    }

    static func faceRaw(for context: TypographyContext, group: String? = nil, defaults: UserDefaults = .standard) -> String? {
        let key = faceKey(for: context)
        if let group, let value = defaults.string(forKey: key + "_" + group) { return value }
        // До индивидуальной настройки код оставался системным моноширинным.
        if context == .chat && group == "mono" { return "system" }
        return defaults.string(forKey: key)
    }

    static func saveFaceRaw(_ value: String?, for context: TypographyContext, group: String, defaults: UserDefaults = .standard) {
        let key = faceKey(for: context) + "_" + group
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    static func appScaleKey(_ group: String) -> String {
        "taskflow_type_\(group)"
    }

    static func chatScaleKey(_ group: String) -> String {
        "taskflow_chat_type_\(group)"
    }

    static func migrateIfNeeded(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationKey) else { return }

        if let legacyScale = defaults.string(forKey: legacyGlobalScaleKey) {
            for group in ["heading", "subheading", "body", "secondary", "tertiary"] {
                let key = appScaleKey(group)
                if defaults.object(forKey: key) == nil {
                    defaults.set(legacyScale, forKey: key)
                }
            }
        }

        let chatToneKey = toneKey(for: .chat)
        if defaults.object(forKey: chatToneKey) == nil,
           let appTone = defaults.string(forKey: toneKey(for: .app)) {
            defaults.set(appTone, forKey: chatToneKey)
        }

        defaults.set(true, forKey: migrationKey)
    }
}
