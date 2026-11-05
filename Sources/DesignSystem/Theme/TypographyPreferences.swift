import Foundation

enum TypographyContext: String, CaseIterable, Identifiable {
    case app
    case chat

    var id: String { rawValue }
}

enum TypographyPreferences {
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
