import SwiftUI

/// «Память TaskFlow» в «Интеграциях» (владелец 08.11.2026): «добавь интеграцию
/// TaskFlow именно Mnemosyne… хочу видеть количество раз по конкретным агентам,
/// кто туда обращается, и мне должен быть окно ввода, чтобы я мог сам
/// запрашивать информацию и смотреть, что там за барахло валяется».
///
/// Сверху — кто обращался и сколько записей держит. Ниже — поиск по банкам:
/// одно поле, живой запрос, найденное целиком (это память, а не превью).
struct TaskflowMemoryScreen: View {
    @State private var agents: [MemoryAgentStat] = []
    @State private var banks: [String] = []
    @State private var results: [MemoryBrowseItem] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let api = APIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                TFErrorBanner(errorMessage, variant: .inline)

                TFSectionHeader("Кто обращается")
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                if agents.isEmpty && isLoading {
                    TFLoading()
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                } else {
                    ForEach(agents) { agent in
                        TFListRow(
                            icon: "person.crop.circle",
                            iconStyle: .plain,
                            title: agent.name,
                            subtitle: agent.subtitle,
                            trailing: AnyView(
                                Text(agent.callsText)
                                    .font(TFFont.caption)
                                    .foregroundStyle(Color.tfSub)
                            ),
                            verticalPadding: TFSpacing.xs
                        )
                        .accessibilityIdentifier("memory.agent.\(agent.id)")
                        TFDivider(inset: TFSpacing.screenHorizontal)
                    }
                }

                TFSectionHeader("Что лежит")
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .padding(.top, TFSpacing.sm)
                Text(banksLine)
                    .font(TFFont.caption)
                    .foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .accessibilityIdentifier("memory.banks")

                if !query.isEmpty && results.isEmpty && !isLoading {
                    TFEmptyState(icon: "magnifyingglass", text: "По этому запросу в памяти ничего нет")
                        .padding(.horizontal, TFSpacing.screenHorizontal)
                        .padding(.top, TFSpacing.md)
                }

                ForEach(results) { item in
                    TFCard(padding: TFSpacing.md) {
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            Text(item.bankTitle)
                                .font(TFFont.caption)
                                .foregroundStyle(Color.tfSub)
                            Text(item.text)
                                .font(TFFont.body)
                                .foregroundStyle(Color.tfText)
                                .fixedSize(horizontal: false, vertical: true)
                            if let at = item.at {
                                Text(ChatListTime.label(at) ?? at)
                                    .font(TFFont.caption)
                                    .foregroundStyle(Color.tfSub)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .accessibilityIdentifier("memory.item.\(item.id)")
                }
            }
            .padding(.vertical, TFSpacing.md)
        }
        .tfScreenBackground()
        .tfNativeHeader("Память TaskFlow")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Что там лежит?")
        .task { await loadAgents() }
        // Живой поиск: пауза в наборе — запрос. Ответ применяется только для
        // последнего введённого текста, иначе выдача «прыгает» назад.
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespaces)
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await loadItems(text)
        }
    }

    private var banksLine: String {
        guard !banks.isEmpty else { return "" }
        return "Банков: \(banks.count) · \(banks.prefix(3).joined(separator: ", "))" +
            (banks.count > 3 ? " и ещё \(banks.count - 3)" : "")
    }

    private func loadAgents() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let envelope = try await api.memoryAgents()
            agents = envelope.agents
            banks = envelope.banks
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadItems(_ text: String) async {
        do {
            let envelope = try await api.memoryBrowse(query: text)
            guard !Task.isCancelled else { return }
            results = envelope.items
            banks = envelope.banks
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
