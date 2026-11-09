import SwiftUI

/// «Спросить базу»: датасеты чипсами, вопрос, ответ модели и источники.
///
/// Шторка системная: раскрывается и закрывается свайпом, кнопок «Готово» и
/// «Закрыть» внизу нет (правило владельца 05.11.2026).
public struct KnowledgeAskSheet: View {
    @State private var viewModel: KnowledgeAskViewModel
    @FocusState private var isQuestionFocused: Bool

    public init(datasets: [ApiKnowledgeDataset], preselecting: String?) {
        _viewModel = State(
            initialValue: KnowledgeAskViewModel(datasets: datasets, preselecting: preselecting)
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.lg) {
                    datasetChips
                    questionField
                    TFErrorBanner(viewModel.errorMessage, variant: .block)
                    if let answer = viewModel.answer {
                        answerBlock(answer)
                    }
                }
                .padding(TFSpacing.lg)
            }
            .navigationTitle("Спросить базу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await viewModel.ask() }
                    } label: {
                        if viewModel.isAsking {
                            ProgressView()
                        } else {
                            Text("Спросить")
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
                    Button {
                        viewModel.toggle(dataset)
                    } label: {
                        Text(dataset.name)
                            .tfText(.action)
                            .foregroundStyle(isSelected ? Color.tfRed : Color.tfText)
                            .padding(.horizontal, TFSpacing.md)
                            .padding(.vertical, TFSpacing.xs)
                            .overlay(
                                Capsule().strokeBorder(
                                    isSelected ? Color.tfRed : Color.tfDim,
                                    lineWidth: 1
                                )
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
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
    private func answerBlock(_ answer: KnowledgeAnswer) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            if let text = answer.answer, !text.isEmpty {
                TFCard {
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
                Text(hint).tfText(.action).foregroundStyle(Color.tfSub)
            }

            if answer.chunks.isEmpty {
                Text("В выбранных датасетах ничего не нашлось.")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            } else {
                Text("Источники")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                ForEach(Array(answer.chunks.enumerated()), id: \.element.id) { index, chunk in
                    TFCard {
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
                }
            }
        }
    }
}
