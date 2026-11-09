import SwiftUI

/// Цвета и значки расхода на экране «Статистика».
///
/// Владелец 09.11.2026: «цвета не надо градацию красного делать — тут
/// абсолютно разные модели, их надо считывать гораздо четче; и значки
/// провайдеров проставь при названии модели».
///
/// Цвет закрепляется за ключом строки (модель или провайдер) и не меняется
/// при смене периода: иначе модель «переезжает» по цвету и путается. Палитра
/// взята из токенов дизайн-системы — своих hex здесь нет.
enum AIUsagePalette {
    /// Восемь различимых цветов: красный, оранжевый, жёлтый, зелёный,
    /// бирюзовый, синий, фиолетовый, розовый. Внутри одного оттенка нет
    /// двух моделей, пока цветов хватает; дальше — серые на добор.
    private static let colors: [Color] = [
        .tfRed, .tfOrange, .tfYellow, .tfGreen,
        .tfTeal, .tfBlue, .tfPurple, .tfPink,
        .tfCoral, .tfSub, .tfDim,
    ]

    /// Устойчивый индекс цвета по ключу: один и тот же ключ — один и тот же
    /// цвет в графике, легенде и списке.
    static func color(for key: String, order: [String]) -> Color {
        let index = order.firstIndex(of: key) ?? order.count
        return colors[index % colors.count]
    }

    /// Ассет с официальным знаком провайдера. `nil` — логотипа нет, рисуем
    /// инициалы: у неизвестного провайдера пустое место хуже букв.
    static func providerAsset(_ provider: String) -> String? {
        switch provider.lowercased() {
        case "anthropic", "claude": return "ProviderAnthropic"
        case "openai", "openai-codex": return "ProviderOpenAI"
        case "google", "google-ai", "googlegemini", "gemini": return "ProviderGoogleGemini"
        case "deepseek", "opencode-go": return "ProviderDeepSeek"
        case "minimax": return "ProviderMiniMax"
        case "ollama": return "ProviderOllama"
        case "opencode": return "ProviderOpenCode"
        case "xai", "x-ai": return "ProviderXAI"
        default: return nil
        }
    }

    /// Двухбуквенная метка — только когда логотипа нет.
    static func providerInitials(_ provider: String) -> String {
        switch provider.lowercased() {
        case "omniroute": return "OR"
        case "local": return "LOC"
        default: return String(provider.prefix(2)).uppercased()
        }
    }

    /// Цвет значка провайдера: свой на каждого, чтобы по кружку было видно,
    /// чей это провайдер, а не только по подписи.
    static func providerColor(_ provider: String) -> Color {
        switch provider.lowercased() {
        case "anthropic": return .tfCoral
        case "openai": return .tfGreen
        case "google", "google-ai": return .tfOrange
        case "deepseek": return .tfBlue
        case "minimax": return .tfPink
        case "opencode": return .tfTeal
        case "ollama": return .tfPurple
        default: return .tfDim
        }
    }
}

/// Маленький круглый значок провайдера рядом с названием модели.
/// Приоритет: официальный логотип из бандла → инициалы в цвете провайдера.
struct AIUsageProviderBadge: View {
    let provider: String
    var size: CGFloat = 16

    var body: some View {
        if let asset = AIUsagePalette.providerAsset(provider) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .padding(size * 0.18)
                .frame(width: size, height: size)
                .background(Color.tfPaper, in: Circle())
                .accessibilityLabel(provider)
        } else {
            Text(AIUsagePalette.providerInitials(provider))
                .font(.system(size: size * 0.42, weight: .bold)) // design-system-guard: ignore — значок, не текст экрана
                .foregroundStyle(Color.tfPaper)
                .frame(width: size, height: size)
                .background(AIUsagePalette.providerColor(provider), in: Circle())
                .accessibilityLabel(provider)
        }
    }
}
