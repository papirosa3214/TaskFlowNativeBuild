import SwiftUI

/// Меню выбора модели, сгруппированное по провайдеру. Общее для строк
/// «Модели ролей» и редактора цепочки запасных.
struct ModelMenu: View {
    let label: String
    let accessibility: String
    let options: [RuntimeModel]
    var disabled = false
    let onPick: (RuntimeModel) -> Void

    private var providerOrder: [String] {
        var seen: [String] = []
        for model in options where !seen.contains(model.provider) { seen.append(model.provider) }
        return seen
    }

    var body: some View {
        Menu {
            ForEach(providerOrder, id: \.self) { provider in
                Section(provider) {
                    ForEach(options.filter { $0.provider == provider }, id: \.uid) { model in
                        Button(model.displayName) { onPick(model) }
                    }
                }
            }
        } label: {
            HStack(spacing: TFSpacing.xs) {
                Text(label)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(disabled)
        .accessibilityLabel(accessibility)
    }
}

extension Array where Element == RuntimeModel {
    /// Человеческое имя модели по записи в маршруте роли; неизвестная — как есть.
    func name(forRef ref: String) -> String {
        first { $0.routeRef == ref }?.displayName ?? ref
    }
}
