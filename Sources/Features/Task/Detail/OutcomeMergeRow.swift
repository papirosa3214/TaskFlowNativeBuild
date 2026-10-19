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
    let taskID: String
    var onToast: (String) -> Void = { _ in }

    @State private var row: ApiMergeQueue.Row?
    @State private var isRollingBack = false

    private let api = APIClient()

    var body: some View {
        if let row {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TFSpacing.sm) {
                    Label("Автослияние: \(row.state.title)", systemImage: row.state.symbol)
                        .tfText(.action)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(2)
                        .accessibilityIdentifier("outcome-merge-state")
                    Spacer(minLength: 0)
                    if row.state.canRollBack {
                        Button(isRollingBack ? "Откатываю…" : "Откатить") {
                            Task { await rollBack() }
                        }
                        .disabled(isRollingBack)
                        .accessibilityIdentifier("outcome-merge-rollback")
                    }
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
            .task(id: taskID) { await load() }
        }
    }

    /// Нет доступа или нет строки — молча: карточка от этой строки не зависит.
    private func load() async {
        guard let queue = try? await api.mergeQueue() else { return }
        row = queue.row(forTask: taskID)
    }

    private func rollBack() async {
        guard !isRollingBack else { return }
        isRollingBack = true
        defer { isRollingBack = false }
        do {
            try await api.rollBackMerge(taskID: taskID)
            onToast("Слияние возвращено")
            await load()
        } catch {
            onToast("Не удалось откатить")
        }
    }
}
