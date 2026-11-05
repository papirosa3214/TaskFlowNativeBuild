import SwiftUI

/// Кнопка выбора модели: открывает шторку со списком по провайдерам и поиском.
/// Общая для строк «Модели ролей» и шторки роли. До 20.10.2026 здесь было
/// системное `Menu` — на 158 моделях оно с телефона не открывалось и не листалось.
struct ModelMenu: View {
    let label: String
    let accessibility: String
    let options: [RuntimeModel]
    var disabled = false
    /// Во всю ширину строки списка: нажатие засчитывается по всей строке, а не только по подписи.
    var fillsRow = false
    /// Что сейчас мешает провайдеру (лимит, ключ) — дописывается к названию группы.
    var problem: (String) -> String? = { _ in nil }
    let onPick: (RuntimeModel) -> Void

    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: TFSpacing.xs) {
                Text(label)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
                if fillsRow { Spacer(minLength: 0) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(accessibility)
        .tfSheet(isPresented: $picking) {
            ModelPickerSheet(title: accessibility, options: options, problem: problem) { model in
                picking = false
                onPick(model)
            }
        }
    }

    static func sectionTitle(_ provider: String, problem: String?) -> String {
        let title = RuntimeModel.providerTitle(provider)
        return problem.map { "\(title) — ⚠︎ \($0)" } ?? title
    }
}

/// Список моделей по провайдерам. Подписки — выше оплаты за запросы: OpenCode Go
/// раньше Zen, иначе одноимённые модели Zen попадаются первыми (20.10.2026).
private struct ModelPickerSheet: View {
    let title: String
    let options: [RuntimeModel]
    let problem: (String) -> String?
    let onPick: (RuntimeModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [RuntimeModel] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return options }
        return options.filter {
            $0.displayName.lowercased().contains(q) || $0.id.lowercased().contains(q)
                || RuntimeModel.providerTitle($0.provider).lowercased().contains(q)
        }
    }

    private var providerOrder: [String] {
        var seen: [String] = []
        for model in filtered where !seen.contains(model.provider) { seen.append(model.provider) }
        let first = ["opencode-go", "openai-codex", "minimax"]
        return seen.filter(first.contains).sorted { first.firstIndex(of: $0)! < first.firstIndex(of: $1)! }
            + seen.filter { !first.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(providerOrder, id: \.self) { provider in
                    Section(ModelMenu.sectionTitle(provider, problem: problem(provider))) {
                        ForEach(filtered.filter { $0.provider == provider }, id: \.uid) { model in
                            Button { onPick(model) } label: {
                                Text(model.displayName)
                                    .tfText(.body)
                                    .foregroundStyle(Color.tfText)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .tfSettingsListRow()
                            .accessibilityLabel("\(model.displayName), \(RuntimeModel.providerShort(model.provider))")
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Модель или провайдер")
            .tfSettingsListChrome()
            .tfScreenBackground()
            .tfNativeHeader(title)
            .environment(\.tfTypeSettingsEnabled, true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Отмена") { dismiss() } }
            }
        }
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
