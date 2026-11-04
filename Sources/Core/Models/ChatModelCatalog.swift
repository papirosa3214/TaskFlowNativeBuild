import Foundation

/// Описание модели для выбора: чем она отличается от соседних.
///
/// Тексты опираются на каталог Pi (`~/.pi/agent/models-store.json`): цена,
/// контекст, поддержка рассуждений и картинок. То, чего в каталоге нет, в
/// описании не выдумывается — оно собирается из семейства модели.
public struct ModelProfile: Equatable, Sendable {
    /// Класс модели по назначению.
    public enum Kind: String, Equatable, Sendable {
        /// Лёгкая и дешёвая: черновики, короткие ответы, рутина.
        case lightweight
        /// Средняя: повседневная работа с кодом и текстом.
        case balanced
        /// Продвинутая: сложные задачи, архитектура, разбор.
        case advanced
        /// Заточена под своё: код, быстрые ответы, широкий контекст.
        case specialized
    }

    public let kind: Kind
    /// Короткая строка под названием модели (для подсказок и a11y).
    public let summary: String

    public init(kind: Kind, summary: String) {
        self.kind = kind
        self.summary = summary
    }

    /// Ориентир стоимости: 1 — дёшево, 4 — дорого. В списке моделей рисуется
    /// столбиками (владелец 03.11.2026: вместо текста пояснения).
    public var costLevel: Int {
        switch kind {
        case .lightweight: 1
        case .specialized: 2
        case .balanced: 3
        case .advanced: 4
        }
    }

    public var costAccessibilityLabel: String {
        switch costLevel {
        case 1: "Стоимость: низкая"
        case 2: "Стоимость: ниже средней"
        case 3: "Стоимость: средняя"
        default: "Стоимость: высокая"
        }
    }
}

/// Каталог описаний моделей и порядок показа.
///
/// Модели приходят с сервера (`/api/roles/:role/models`); описания и
/// избранное живут на устройстве: это подсказка для выбора, а не часть
/// настройки роли.
public enum ChatModelCatalog {
    /// Explicit free variants advertised by Zen and OpenRouter. Subscription
    /// access and a local model do not imply a free cloud variant.
    public static func isFree(_ id: String) -> Bool {
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        switch parts[0] {
        case "opencode": return parts[1].hasSuffix("-free")
        case "openrouter": return parts[1].hasSuffix(":free")
        default: return false
        }
    }

    /// Порядок избранного: сначала помеченные владельцем, потом остальные по
    /// алфавиту. Владелец 29.10.2026: «добавь там звёздочки, чтобы я мог
    /// выбирать потом, чтобы были отображены в первую очередь избранные».
    public static func ordered(_ models: [RoleModelOption], favorites: Set<String>) -> [RoleModelOption] {
        models.sorted { lhs, rhs in
            let leftFavorite = favorites.contains(lhs.id)
            let rightFavorite = favorites.contains(rhs.id)
            if leftFavorite != rightFavorite { return leftFavorite }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// Описание модели по её id (`провайдер/модель`).
    ///
    /// Сначала — точная запись, потом — семейство по имени: у моделей много
    /// версий (`claude-opus-5`, `claude-opus-5-5`, `claude-opus-4-8`), а
    /// характер у них один. Модели без описания — обычный баланс.
    public static func profile(for id: String) -> ModelProfile {
        if let exact = exactProfiles[id] { return exact }
        return familyProfile(for: id) ?? ModelProfile(kind: .balanced, summary: "Модель провайдера: общий выбор для повседневных задач.")
    }

    /// Есть ли у модели своё описание (а не общее на все модели семейства).
    public static func hasProfile(for id: String) -> Bool {
        exactProfiles[id] != nil
    }

    /// Точные записи: модели, про которые сказано отдельно.
    private static let exactProfiles: [String: ModelProfile] = [
        "anthropic/claude-opus-5": ModelProfile(kind: .advanced, summary: "Самая продвинутая в линейке: сложные задачи, архитектура, разбор чужого кода."),
        "anthropic/claude-opus-5-5": ModelProfile(kind: .advanced, summary: "Самая продвинутая в линейке: сложные задачи, архитектура, разбор чужого кода."),
        "anthropic/claude-opus-4-5": ModelProfile(kind: .advanced, summary: "Продвинутая модель для сложных задач и архитектуры."),
        "anthropic/claude-opus-4-6": ModelProfile(kind: .advanced, summary: "Продвинутая модель для сложных задач и архитектуры."),
        "anthropic/claude-opus-4-7": ModelProfile(kind: .advanced, summary: "Продвинутая модель для сложных задач и архитектуры."),
        "anthropic/claude-opus-4-8": ModelProfile(kind: .advanced, summary: "Продвинутая модель для сложных задач и архитектуры."),
        "anthropic/claude-sonnet-5": ModelProfile(kind: .balanced, summary: "Баланс скорости и качества: повседневная работа с кодом и текстом."),
        "anthropic/claude-sonnet-5-5": ModelProfile(kind: .balanced, summary: "Баланс скорости и качества: повседневная работа с кодом и текстом."),
        "anthropic/claude-sonnet-4-5": ModelProfile(kind: .balanced, summary: "Баланс скорости и качества: повседневная работа с кодом и текстом."),
        "anthropic/claude-sonnet-4-6": ModelProfile(kind: .balanced, summary: "Баланс скорости и качества: повседневная работа с кодом и текстом."),
        "anthropic/claude-haiku-5-5": ModelProfile(kind: .lightweight, summary: "Быстрая и дешёвая: короткие ответы, черновики, рутина."),
        "anthropic/claude-haiku-4-5": ModelProfile(kind: .lightweight, summary: "Быстрая и дешёвая: короткие ответы, черновики, рутина."),
        "anthropic/claude-fable-5": ModelProfile(kind: .advanced, summary: "Тяжёлые рассуждения и самый большой расход: точечные сложные задачи."),
        "anthropic/claude-fable-5-1": ModelProfile(kind: .advanced, summary: "Тяжёлые рассуждения и самый большой расход: точечные сложные задачи."),
        "openai-codex/gpt-5.6-sol": ModelProfile(kind: .balanced, summary: "Дороже terra: сложный код, разбор, повседневные задачи."),
        "openai-codex/gpt-5.6-terra": ModelProfile(kind: .balanced, summary: "Дешевле sol в полтора раза: код, разбор, повседневные задачи."),
        "openai-codex/gpt-5.6-luna": ModelProfile(kind: .lightweight, summary: "Дешёвая и быстрая: короткие ответы и черновики."),
        "openai-codex/gpt-6-sol": ModelProfile(kind: .balanced, summary: "Средняя по цене: код, разбор, повседневные задачи."),
        "openai-codex/gpt-6.1-sol": ModelProfile(kind: .balanced, summary: "Средняя по цене, больше контекста: код, разбор, повседневные задачи."),
        "openai-codex/gpt-6-luna": ModelProfile(kind: .lightweight, summary: "Дешёвая и быстрая: короткие ответы и черновики."),
        "openai-codex/gpt-6-astra": ModelProfile(kind: .advanced, summary: "Самая продвинутая и самая дорогая: сложные задачи и архитектура."),
        "openai-codex/gpt-5.5": ModelProfile(kind: .advanced, summary: "Продвинутая модель: сложные задачи, архитектура, разбор."),
        "openai-codex/gpt-5.3-codex-spark": ModelProfile(kind: .specialized, summary: "Заточена под код: правки, рефакторинг, разбор репозитория."),
        "minimax/MiniMax-M3": ModelProfile(kind: .balanced, summary: "Дешёвая с большим контекстом: длинные документы и объёмная рутина."),
        "minimax/MiniMax-M2.7": ModelProfile(kind: .lightweight, summary: "Дешёвая и быстрая: черновики, короткие ответы, рутина."),
        "kimi-coding/k3": ModelProfile(kind: .specialized, summary: "Заточена под код: длинный контекст репозитория и правки."),
        "kimi-coding/kimi-for-coding": ModelProfile(kind: .specialized, summary: "Заточена под код: длинный контекст репозитория и правки."),
        "opencode/deepseek-v4-pro": ModelProfile(kind: .balanced, summary: "Средняя по цене: код, разбор, повседневные задачи."),
        "opencode/deepseek-v4-flash": ModelProfile(kind: .lightweight, summary: "Быстрая и дешёвая: короткие ответы и черновики."),
        "opencode/gemini-3.1-pro": ModelProfile(kind: .advanced, summary: "Продвинутая модель с очень широким контекстом."),
        "opencode/gemini-3.5-flash": ModelProfile(kind: .lightweight, summary: "Быстрая и дешёвая с широким контекстом."),
        "opencode/glm-5.2": ModelProfile(kind: .balanced, summary: "Средняя по цене: код, разбор, повседневные задачи."),
        "opencode/glm-5.3-flash": ModelProfile(kind: .lightweight, summary: "Быстрая и дешёвая: короткие ответы и черновики.")
    ]

    /// Характер по имени модели: версий много, а характер один.
    private static func familyProfile(for id: String) -> ModelProfile? {
        let model = id.split(separator: "/").last.map(String.init) ?? id
        let name = model.lowercased()
        if name.contains("codex") || name.contains("coding") || name.contains("code") {
            return ModelProfile(kind: .specialized, summary: "Заточена под код: правки, рефакторинг, разбор репозитория.")
        }
        if name.contains("opus") {
            return ModelProfile(kind: .advanced, summary: "Продвинутая модель для сложных задач и архитектуры.")
        }
        if name.contains("fable") {
            return ModelProfile(kind: .advanced, summary: "Тяжёлые рассуждения и большой расход: точечные сложные задачи.")
        }
        if name.contains("sonnet") {
            return ModelProfile(kind: .balanced, summary: "Баланс скорости и качества: повседневная работа с кодом и текстом.")
        }
        if name.contains("haiku") {
            return ModelProfile(kind: .lightweight, summary: "Быстрая и дешёвая: короткие ответы, черновики, рутина.")
        }
        if name.contains("flash") || name.contains("lite") || name.contains("nano") || name.contains("mini") {
            return ModelProfile(kind: .lightweight, summary: "Быстрая и дешёвая: короткие ответы и черновики.")
        }
        if name.contains("pro") || name.contains("max") || name.contains("ultra") {
            return ModelProfile(kind: .advanced, summary: "Продвинутая модель для сложных задач.")
        }
        return nil
    }
}

/// Избранные модели владельца — звёздочки в списке выбора.
///
/// Хранятся на устройстве: это подсказка для выбора, а не настройка роли.
@MainActor
@Observable
public final class ChatModelFavorites {
    public static let storageKey = "taskflow_chat_model_favorites"

    private(set) public var ids: Set<String>

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
        ids = Set(stored)
    }

    public func isFavorite(_ id: String) -> Bool { ids.contains(id) }

    public func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        defaults.set(Array(ids).sorted(), forKey: Self.storageKey)
    }
}
