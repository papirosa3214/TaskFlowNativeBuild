import SwiftUI

// Живой ход роли в чате (владелец 27.09.2026, LOCK-229): пока роль отвечает,
// окно чата показывает то же, что окно сессии Claude Code, — текст ответа
// растёт по словам, между кусками текста идут шаги (что читает, что
// выполняет, что ищет). После ответа шаги остаются под сообщением свёрнутой
// строкой «7 шагов · 42 с».

/// Действие шага по имени инструмента с сервера. Сервер имя не
/// интерпретирует — подпись и значок целиком на клиенте. Существительные, а
/// не глаголы: одна и та же подпись годится и для идущего шага, и для
/// сделанного, и не зависит от рода роли.
enum RoleLiveStepKind {
    static func label(forTool tool: String) -> String {
        switch tool {
        case "read": return "Чтение"
        case "edit", "write": return "Правка"
        case "bash": return "Команда"
        case "grep", "glob", "find": return "Поиск"
        case "ls": return "Папка"
        default: return "Действие"
        }
    }

    static func symbol(forTool tool: String) -> String {
        switch tool {
        case "read": return "doc.text"
        case "edit", "write": return "pencil.line"
        case "bash": return "terminal"
        case "grep", "glob", "find": return "magnifyingglass"
        case "ls": return "folder"
        default: return "gearshape"
        }
    }
}

enum RoleLiveFormat {
    /// «1 шаг / 3 шага / 7 шагов».
    static func steps(_ count: Int) -> String {
        let mod100 = count % 100
        let word: String
        if mod100 >= 11 && mod100 <= 14 {
            word = "шагов"
        } else {
            switch count % 10 {
            case 1: word = "шаг"
            case 2, 3, 4: word = "шага"
            default: word = "шагов"
            }
        }
        return "\(count) \(word)"
    }

    /// «42 с», «3 мин 5 с», «12 мин».
    static func duration(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s) с" }
        let minutes = s / 60
        let rest = s % 60
        return rest == 0 ? "\(minutes) мин" : "\(minutes) мин \(rest) с"
    }
}

/// Строка шага: значок, действие, подпись (путь, команда, запрос).
struct RoleLiveStepRow: View {
    let step: RoleChatLiveStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            icon
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
            Text(RoleLiveStepKind.label(forTool: step.tool))
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
            if let detail = step.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.tfDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.status {
        case .running:
            Image(systemName: RoleLiveStepKind.symbol(forTool: step.tool))
                .foregroundStyle(Color.tfSub)
                .symbolEffect(.pulse, options: .repeating)
        case .done:
            Image(systemName: RoleLiveStepKind.symbol(forTool: step.tool))
                .foregroundStyle(Color.tfDim)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.tfOrange)
        }
    }

    private var accessibilityText: String {
        let status: String
        switch step.status {
        case .running: status = "идёт"
        case .done: status = "готово"
        case .error: status = "ошибка"
        }
        return [RoleLiveStepKind.label(forTool: step.tool), step.detail, status]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// Элементы хода по порядку: шаги строками, текст абзацами. В истории
/// промежуточный текст («сейчас проверю…») приглушён — главный ответ в
/// пузыре ниже.
struct RoleLiveItemsList: View {
    let items: [RoleChatLiveItem]
    var textColor: Color = .tfText

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            // Индекс, а не текст: текст растёт каждые 150 мс, и id по нему
            // пересоздавал бы строку на каждом кадре.
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .text(let text):
                    RoleReplyMarkdown(text: text, color: textColor)
                case .step(let step):
                    RoleLiveStepRow(step: step)
                }
            }
        }
    }
}

/// Идущий ход: шаги и растущий текст прямо по фону ленты, без карточки —
/// как ответ роли в 1:1-чате (LOCK-230); внизу — сколько уже идёт.
struct RoleLiveTurnBubble: View {
    let turn: RoleChatLiveTurn

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            RoleLiveItemsList(items: turn.items)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(footer(now: context.date))
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(now: Date) -> String {
        let steps = turn.items.filter(\.isStep).count
        var parts = ["Работает"]
        if let start = turn.startDate {
            parts.append(RoleLiveFormat.duration(seconds: Int(now.timeIntervalSince(start))))
        }
        if steps > 0 { parts.append(RoleLiveFormat.steps(steps)) }
        return parts.joined(separator: " · ")
    }
}

/// Шаги под готовым ответом — свёрнуты в «7 шагов · 42 с», тап раскрывает.
struct RoleStepsDisclosure: View {
    let steps: RoleChatSteps
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            RoleLiveItemsList(items: steps.items, textColor: .tfSub)
                .padding(.top, TFSpacing.xs)
        } label: {
            Text(summary)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
        }
    }

    private var summary: String {
        "\(RoleLiveFormat.steps(steps.stepCount)) · "
            + RoleLiveFormat.duration(seconds: steps.durationMs / 1000)
    }
}
