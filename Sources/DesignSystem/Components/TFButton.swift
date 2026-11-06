import SwiftUI

// Кнопки (владелец 06.11.2026, скрин «Повторить»): все кнопки — маленькие
// красные системные капсулы по размеру подписи, как действие пустого
// состояния (`TFEmptyState`): `.borderedProminent` + красный. Раньше была
// полноширинная плашка 48 pt с тёмно-красным градиентом и кромкой.
//
// Вид у всех вариантов один; вариант оставлен в API, чтобы не трогать 74
// места вызова, и пригодится, если владелец захочет различать вторичные.
public enum TFButtonVariant {
    case primary
    case secondary
    case outline
}

/// Кнопка-капсула по размеру подписи. Иконка опциональна — используется,
/// например, в «Завершить задачу» (check) / «Открыть заново» (sync).
public struct TFButton: View {
    let title: String
    let icon: String?
    let variant: TFButtonVariant
    let isEnabled: Bool
    let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        variant: TFButtonVariant = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        // Неактивная — красная, но бледнее (владелец 06.11.2026: «Сохранить
        // серая»). Системный `.disabled` красит капсулу в серый, поэтому
        // нажатие отключается иначе.
        Button(action: { if isEnabled { action() } }) {
            // Надпись — через `.tfText`, чтобы подчинялась «Настройки → Шрифт»
            // (владелец 06.11.2026: «любой текст должен реагировать на ручки»).
            Group {
                if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
            }
            .tfText(.body)
            .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .tint(.tfRed)
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(isEnabled)
        .accessibilityValue(isEnabled ? "" : "Недоступно")
    }
}

/// Кнопка-иконка (`background: transparent`, зона 44×44, иконка 18px) — шапка экрана,
/// действия в бейджах/строках. Отклик `tap-scale`.
///
/// 14.09.2026, a11y-аудит: `label` — ОБЯЗАТЕЛЬНЫЙ параметр, а не опция.
/// Кнопка без текста внутри нечего читать VoiceOver'у и нечем озвучить
/// Voice Control'у; раньше подпись нужно было вешать снаружи через
/// `.accessibilityLabel(...)`, и все три места вызова её просто забыли.
/// Теперь компилятор не даст создать безымянную иконочную кнопку.
public struct TFIconButton: View {
    let icon: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    public init(_ icon: String, label: String, size: CGFloat = TFIconSize.sm, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .tfTypeFont(size: size, weight: .regular)
                .foregroundStyle(Color.tfText)
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(TFTapScaleStyle())
        .accessibilityLabel(label)
    }
}

/// `tap-scale`: scale(0.94) мгновенно на нажатие, без анимации на отпускание —
/// снимается «щелчком», не плавным возвратом (спека §4 «Кнопки»).
public struct TFTapScaleStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// `tap-row`: подсветка фона строки списка/карточки при нажатии.
public struct TFTapRowStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.04) : .clear)
    }
}

/// `tap-fade`: полноширинные CTA/текстовые ссылки — просадка непрозрачности, не масштаба.
public struct TFTapFadeStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

#Preview("Кнопки") {
    VStack(spacing: TFSpacing.md) {
        TFButton("Завершить задачу", icon: "checkmark", variant: .primary) {}
        TFButton("Открыть задачу заново", icon: "arrow.triangle.2.circlepath", variant: .secondary) {}
        TFButton("Отмена", variant: .outline) {}
        TFButton("Недоступно", variant: .primary, isEnabled: false) {}
        HStack {
            TFIconButton("line.3.horizontal.decrease", label: "Фильтры") {}
            TFIconButton("ellipsis", label: "Ещё") {}
        }
    }
    .padding()
    .background(Color.tfBackground)
}
