import SwiftUI

/// Строка «Автослияние» в секции «Итог» карточки (владелец 19.10.2026,
/// LOCK-MERGE-STATUS-20261019).
///
/// Перенос ветки роли в `main` делает сервер сам: слияние идёт во временной
/// копии, `main` двигается только после зелёных тестов, а откат предлагается
/// лишь после состоявшегося слияния. Владельцу здесь нужны два факта — что с
/// переносом и можно ли его вернуть.
///
/// Отдельная маленькая view, а не часть `TaskOutcomeContent`: у того
/// инициализатора много замыканий, и лишний аргумент доводил компилятор до
/// отказа собирать выражение в разумное время.
struct OutcomeMergeRow: View {
    let row: ApiMergeQueue.Row
    var onToast: (String) -> Void = { _ in }
    /// Перечитать очередь после отката. Загрузку делает экран карточки:
    /// `.task` внутри `if let row` здесь не срабатывал никогда — пока строки
    /// нет, нет и вида, на котором висит загрузка.
    var onChanged: () async -> Void = {}

    @State private var isRollingBack = false
    @Environment(\.openURL) private var openURL

    private let api = APIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: TFSpacing.sm) {
                Label {
                    Text("Автослияние: \(row.state.title)")
                        .foregroundStyle(Color.tfText)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(symbolTint)
                }
                .tfText(.action)
                .lineLimit(2)
                .accessibilityIdentifier("outcome-merge-state")
                Spacer(minLength: 0)
                // Через PR влитое откатывается на GitHub, не здесь.
                if row.state.canRollBack && row.prNumber == nil {
                    Button(isRollingBack ? "Откатываю…" : "Откатить") {
                        Task { await rollBack() }
                    }
                    .disabled(isRollingBack)
                    .accessibilityIdentifier("outcome-merge-rollback")
                }
            }
            if let number = row.prNumber {
                Button("PR #\(number) на GitHub") {
                    if let url = row.prURL { openURL(url) }
                }
                .tfText(.meta)
                .disabled(row.prURL == nil)
                .accessibilityIdentifier("outcome-merge-pr")
            }
            if let sha = row.shortSHA {
                Text("main \(sha)")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
            }
            if let reason = row.error, !reason.isEmpty {
                Text(reason)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(3)
            }
        }
    }

    /// Как значок PR в Claude и на GitHub: открыт — зелёный, влит —
    /// фиолетовый. Без PR — прежние значки состояния.
    private var symbol: String {
        if row.prNumber != nil, row.state == .merged { return "arrow.triangle.merge" }
        return row.state.symbol
    }

    private var symbolTint: Color {
        guard row.prNumber != nil else { return Color.tfText }
        switch row.state {
        case .prOpen: return Color.tfGreen
        case .merged: return Color.tfPurple
        default: return Color.tfText
        }
    }

    private func rollBack() async {
        guard !isRollingBack else { return }
        isRollingBack = true
        defer { isRollingBack = false }
        do {
            try await api.rollBackMerge(taskID: row.taskID)
            onToast("Слияние возвращено")
            await onChanged()
        } catch {
            onToast("Не удалось откатить")
        }
    }
}
