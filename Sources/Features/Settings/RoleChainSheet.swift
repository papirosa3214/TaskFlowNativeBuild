import SwiftUI

/// Цепочка запасных одной роли (владелец 07.10.2026): сколько угодно запасных,
/// в любом порядке, хоть ни одной. «После основной — первая, затем вторая…».
/// Перетаскивание — кнопкой «Изменить», удаление — свайпом; каждое изменение
/// сохраняется сразу.
struct RoleChainSheet: View {
    @Bindable var viewModel: RoleModelsViewModel
    let profile: AgentProfile
    let models: [RuntimeModel]

    @Environment(\.dismiss) private var dismiss
    @State private var draft: [String]

    init(viewModel: RoleModelsViewModel, profile: AgentProfile, models: [RuntimeModel]) {
        self.viewModel = viewModel
        self.profile = profile
        self.models = models
        _draft = State(initialValue: profile.modelPolicy.fallbacks)
    }

    /// Актуальный профиль: после сохранения список ролей перечитывается, а `profile` — снимок на момент открытия.
    private var live: AgentProfile { viewModel.roles.first { $0.role == profile.role } ?? profile }
    private var primary: String { live.modelPolicy.primary }
    private var options: [RuntimeModel] { models.filter { $0.available && $0.isRoutable } }

    var body: some View {
        NavigationStack {
            List {
                Section("Основная") {
                    Text(models.name(forRef: primary)).tfText(.action)
                }
                Section {
                    ForEach(draft.indices, id: \.self) { index in
                        ModelMenu(
                            label: draft[index].isEmpty ? "— выберите —" : models.name(forRef: draft[index]),
                            accessibility: "Запасная \(index + 1)",
                            options: options.filter { $0.routeRef != primary },
                            disabled: viewModel.busy != nil
                        ) { model in
                            draft[index] = model.routeRef
                            save()
                        }
                    }
                    .onMove { from, to in
                        draft.move(fromOffsets: from, toOffset: to)
                        save()
                    }
                    .onDelete { offsets in
                        draft.remove(atOffsets: offsets)
                        save()
                    }
                    Button("Добавить запасную") { draft.append("") }
                        .disabled(draft.contains(""))
                        .frame(minHeight: 44)
                } header: {
                    Text("Запасные по порядку")
                } footer: {
                    Text(draft.isEmpty
                        ? "Запасных нет: упёрлась в лимит — роль остановится."
                        : "После основной — первая, затем вторая…")
                }
            }
            .navigationTitle(profile.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
    }

    /// На сервер уходят только выбранные, без повторов; пустая строка — добавленная, но ещё не выбранная.
    private func save() {
        var seen = Set<String>()
        let chosen = draft.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard chosen != live.modelPolicy.fallbacks else { return }
        Task { await viewModel.saveChain(role: profile.role, primary: primary, fallbacks: chosen) }
    }
}
