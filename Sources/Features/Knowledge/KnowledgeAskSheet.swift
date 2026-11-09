import SwiftUI

/// «Спросить базу»: датасеты чипсами, вопрос, ответ модели и источники.
///
/// Шторка системная: раскрывается и закрывается свайпом, кнопок «Готово» и
/// «Закрыть» внизу нет (правило владельца 05.11.2026).
public struct KnowledgeAskSheet: View {
    @State private var viewModel: KnowledgeAskViewModel
    @FocusState private var isQuestionFocused: Bool

    public init(datasets: [ApiKnowledgeDataset], preselecting: String?, initialQuestion: String = "") {
        _viewModel = State(
            initialValue: KnowledgeAskViewModel(
                datasets: datasets, preselecting: preselecting, question: initialQuestion
            )
        )
    }

    public var body: some View {
        NavigationStack {
            List {
                Section { datasetChips }
                Section { questionField }
                if viewModel.errorMessage != nil {
                    Section { TFErrorBanner(viewModel.errorMessage, variant: .block) }
                }
                if let answer = viewModel.answer {
                    answerSections(answer)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(TFSpacing.sm)
            .tfScreenBackground()
            .tint(Color.tfText)
            .navigationTitle("Спросить базу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await viewModel.ask() }
                    } label: {
                        if viewModel.isAsking {
                            TFLoading(.inline)
                        } else {
                            Text("Спросить")
                                .foregroundStyle(Color.tfText)
                        }
                    }
                    .disabled(!viewModel.canAsk)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var datasetChips: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text("Где искать")
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
            FlowLayout(spacing: TFSpacing.sm) {
                ForEach(viewModel.datasets) { dataset in
                    let isSelected = viewModel.selectedDatasetIds.contains(dataset.id)
                    KnowledgeRimButton(
                        title: dataset.name,
                        systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                    ) {
                        viewModel.toggle(dataset)
                    }
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            if let hint = viewModel.hintText {
                Text(hint).tfText(.action).foregroundStyle(Color.tfSub)
            }
        }
    }

    private var questionField: some View {
        HStack(spacing: TFSpacing.sm) {
            TextField("Что нужно найти?", text: $viewModel.question, axis: .vertical)
                .lineLimit(1...4)
                .focused($isQuestionFocused)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.search)
                .onSubmit { Task { await viewModel.ask() } }
        }
    }

    @ViewBuilder
    private func answerSections(_ answer: KnowledgeAnswer) -> some View {
        if let text = answer.answer, !text.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(text)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                    if let model = answer.model {
                        Text(model)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                    }
                }
            }
        } else if let hint = answer.hint {
            Section {
                Text(hint).tfText(.action).foregroundStyle(Color.tfSub)
            }
        }

        if answer.chunks.isEmpty {
            Section {
                Text("В выбранных датасетах ничего не нашлось.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
        } else {
            Section {
                ForEach(Array(answer.chunks.enumerated()), id: \.element.id) { index, chunk in
                    VStack(alignment: .leading, spacing: TFSpacing.xs) {
                        Text("\(index + 1). \(chunk.title ?? chunk.documentName)")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                        Text(chunk.text)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                            .lineLimit(8)
                    }
                }
            } header: {
                Text("Источники")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
        }
    }
}
