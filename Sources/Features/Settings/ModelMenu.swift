import SwiftUI

/// Меню выбора модели, сгруппированное по провайдеру. Общее для строк
/// «Модели ролей» и редактора цепочки запасных.
struct ModelMenu: View {
    let label: String
    let accessibility: String
    let options: [RuntimeModel]
    var disabled = false
    /// Что сейчас мешает провайдеру (лимит, ключ) — дописывается к названию группы.
    var problem: (String) -> String? = { _ in nil }
    let onPick: (RuntimeModel) -> Void

    /// Подписки — выше оплаты за запросы: OpenCode Go раньше Zen, иначе одноимённые
    /// модели Zen попадаются первыми и выбираются по ошибке (20.10.2026).
    private var providerOrder: [String] {
        var seen: [String] = []
        for model in options where !seen.contains(model.provider) { seen.append(model.provider) }
        let first = ["opencode-go", "openai-codex", "minimax"]
        return seen.filter(first.contains).sorted { first.firstIndex(of: $0)! < first.firstIndex(of: $1)! }
            + seen.filter { !first.contains($0) }
    }

    var body: some View {
        Menu {
            ForEach(providerOrder, id: \.self) { provider in
                Section(Self.sectionTitle(provider, problem: problem(provider))) {
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

    static func sectionTitle(_ provider: String, problem: String?) -> String {
        let title = RuntimeModel.providerTitle(provider)
        return problem.map { "\(title) — ⚠︎ \($0)" } ?? title
    }
}

extension Array where Element == RuntimeModel {
    /// Человеческое имя модели по записи в маршруте роли; неизвестная — как есть.
    func name(forRef ref: String) -> String {
        model(forRef: ref)?.displayName ?? ref
    }

    /// Имя модели с коротким провайдером: «DeepSeek V4.1 Flash · Go» — у OpenCode Go
    /// и Zen модели называются одинаково, а платятся по-разному.
    func label(forRef ref: String) -> String {
        guard let model = model(forRef: ref) else { return ref }
        return "\(model.displayName) · \(RuntimeModel.providerShort(model.provider))"
    }

    /// Модель по записи в маршруте: и `провайдер/id`, и прежний «голый» id.
    func model(forRef ref: String) -> RuntimeModel? {
        first { $0.routeRef == ref } ?? first { $0.id == ref && $0.isRoutable }
    }
}
