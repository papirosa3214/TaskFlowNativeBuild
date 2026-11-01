import SwiftUI

// Бейджи/пилюли строки задачи — spec/DESIGN-TOKENS.md §4 «Строка задачи».
// Пилюля: px-2 py-0.5 (8px/2px), радиус `rounded` (4px, служебный — вне
// основной шкалы, самый мелкий элемент интерфейса), текст 11px (caption).
/// Пилюля — скруглённая капсула. Milestone 3, семейство F12.
///
/// Две формы, один компонент:
///
///   • **текстовая** — `TFPill("Срок", color: .tfRed)`: кегль `caption`,
///     горизонтальный отступ `sm`, вертикальный 2, фон — цвет с альфой
///     (или сплошной `solidBackground` — так сделан бейдж срока);
///   • **с содержимым** — `TFPill(surface: .tfCard2) { … }`: содержимое и его
///     отступы задаёт вызывающий, компонент даёт подложку и скругление.
///     Нужна там, где в капсуле не один текст: значок рядом с датой, счётчик
///     действий, плашка задачи в сетке часов.
///
/// Вторая форма добавлена 02.11.2026 (Milestone 3, фича
/// `m3-card-and-screen-background`): до неё такие капсулы собирались руками
/// (`.background(Color.tfCard2)` + свой `clipShape`) — подложка бралась мимо
/// канона. Вид при переходе не изменился: те же цвет, радиус и отступы.
public struct TFPill<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    /// Текст пилюли — `nil` у формы с произвольным содержимым.
    let text: String?
    let color: Color
    /// Доля альфы фона под текстом — приоритет/просрочка используют разные значения (15% против 26≈15%).
    let backgroundOpacity: Double
    /// Фон = `card` (срок), а не цвет + альфа — единственное исключение из общего правила пилюли.
    let solidBackground: Color?
    /// Скругление капсулы: `pill` по умолчанию, `capsule` — настоящая капсула.
    let shape: AnyShape

    /// Пилюля с текстом — основная форма.
    public init(_ text: String, color: Color, backgroundOpacity: Double = 0.15, solidBackground: Color? = nil) where Content == Text {
        self.content = Text(text)
        self.text = text
        self.color = color
        self.backgroundOpacity = backgroundOpacity
        self.solidBackground = solidBackground
        self.shape = AnyShape(RoundedRectangle(cornerRadius: TFRadius.pill))
    }

    /// Пилюля с произвольным содержимым: подложка и скругление — канон,
    /// содержимое и его отступы задаёт вызывающий.
    public init(surface: Color, radius: CGFloat = TFRadius.pill, capsule: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.text = nil
        self.color = .clear
        self.backgroundOpacity = 0
        self.solidBackground = surface
        self.shape = capsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: radius))
    }

    public var body: some View {
        if let text {
            Text(text)
                .tfText(.caption)
                .foregroundStyle(colorScheme == .light || solidBackground != nil ? Color.tfText : color)
                .padding(.horizontal, TFSpacing.sm)
                .padding(.vertical, 2)
                .background(solidBackground ?? color.opacity(backgroundOpacity))
                .clipShape(shape)
        } else {
            content
                .background(solidBackground ?? Color.clear)
                .clipShape(shape)
        }
    }
}

/// Приоритет — шевроны по возрастанию, цвет из таблицы `TaskPriority`.
/// Решение владельца 11.09.2026: флажок перестал обозначать приоритет и
/// переехал на флаг готовности (`TFReadyFlag`), а уровень теперь читается
/// количеством стрелок: срочный — четыре, высокий — три, средний — два,
/// низкий — одна. Низкий тоже рисуется: раньше P4 намеренно скрывали, но со
/// стрелками одна палочка уже несёт смысл и не шумит.
/// Стопкой по вертикали и сбоку от строки — слово владельца 11.09.2026: «раз
/// он высокий, чтобы всё вылазило». В ряд по горизонтали четыре шеврона
/// слипались в красный зигзаг и читались как волна, а не как уровень; стопка
/// же использует высоту строки, которой и так хватает.
public struct TFPriorityArrows: View {
    let priority: TaskPriority

    public init(_ priority: TaskPriority) {
        self.priority = priority
    }

    /// Срочный — самый заметный знак, дальше по убыванию.
    private var count: Int {
        switch priority {
        case .urgent: 4
        case .high: 3
        case .medium: 2
        case .low: 1
        }
    }

    public var body: some View {
        VStack(spacing: -3) {
            ForEach(0..<count, id: \.self) { _ in
                Image(systemName: "chevron.up")
                    .tfTypeFont(size: 10, weight: .bold)
            }
        }
        .foregroundStyle(priority.color)
        .accessibilityLabel("Приоритет: \(priority.label)")
    }
}

/// Метка (label) — пилюля, фон = цвет метки + альфа `26`(hex)≈15%, как в спеке.
public struct TFLabelPill: View {
    let title: String
    let color: Color

    public init(_ title: String, color: Color) {
        self.title = title
        self.color = color
    }

    public var body: some View {
        TFPill(title, color: color, backgroundOpacity: 0.15)
    }
}

/// «Просрочено» — фиксированная пилюля `red`/15%, текст тот же цвет.
public struct TFOverduePill: View {
    public init() {}
    public var body: some View {
        TFPill("Просрочено", color: .tfRed, backgroundOpacity: 0.15)
    }
}

/// Срок (дата/время) — фон `card` (не альфа акцента), текст `sub`.
public struct TFDuePill: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .tfText(.caption)
            .foregroundStyle(Color.tfSub)
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, 2)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
    }
}

/// Срок в строке задачи. Сегодня — зелёная пилюля со значком календаря,
/// просрочено — красная со значком календаря, остальное — прежний серый бейдж.
public struct TFDueChip: View {
    let plain: String
    let relative: String
    let days: Int
    let overdueText: String
    let highlight: Bool
    let forceOverdue: Bool

    public init(plain: String, relative: String, days: Int, overdueText: String,
                highlight: Bool = true, forceOverdue: Bool = false) {
        self.plain = plain
        self.relative = relative
        self.days = days
        self.overdueText = overdueText
        self.highlight = highlight
        self.forceOverdue = forceOverdue
    }

    private var tone: Color? {
        guard highlight else { return nil }
        if forceOverdue || days < 0 { return .tfRed }
        if days == 0 { return .tfGreen }
        return nil
    }

    public var body: some View {
        if let tone {
            HStack(spacing: 3) {
                Image(systemName: "calendar").imageScale(.small)
                Text(tone == .tfRed ? overdueText : "\(plain) · \(relative)")
            }
            .tfText(.caption)
            .foregroundStyle(tone)
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, 2)
            .background(tone.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
        } else {
            HStack(spacing: 3) {
                Text(plain)
                Text("· \(relative)")
                    .foregroundStyle(days <= 3 ? Color.tfOrange : Color.tfDim)
            }
            .tfText(.caption)
            .foregroundStyle(Color.tfSub)
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, 2)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
        }
    }
}

/// Тег раздела «Second Brain» и подобные акцентные плашки на карточках
/// (`overview.png` — «SECOND BRAIN» на карточке «Сводка недели») — та же
/// геометрия пилюли, но фон/текст берутся снаружи, а не выводятся из токена.
public struct TFAccentTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let color: Color

    public init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .tfText(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(colorScheme == .light ? Color.tfText : color)
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
    }
}

#Preview("Бейджи") {
    VStack(alignment: .leading, spacing: TFSpacing.md) {
        HStack(spacing: TFSpacing.sm) {
            TFPriorityArrows(.urgent)
            TFPriorityArrows(.high)
            TFPriorityArrows(.medium)
            TFPriorityArrows(.low)
        }
        HStack(spacing: TFSpacing.sm) {
            TFOverduePill()
            TFDuePill("Завтра, 14:00")
            TFLabelPill("Важно", color: .tfRed)
            TFLabelPill("UX/UI", color: .tfPurple)
        }
        TFAccentTag("SECOND BRAIN", color: .tfPink)
    }
    .padding()
    .background(Color.tfBackground)
}
