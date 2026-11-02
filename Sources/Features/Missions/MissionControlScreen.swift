import SwiftUI
import Observation

/// Стор экрана Mission Control. Данные — контракт ассерций карточки, журнал
/// прохождения и навыки миссии (сервер .110, миграции 189–191).
@MainActor @Observable
final class MissionControlModel {
    var assertions: [MissionAssertion] = []
    var outcome: MissionOutcome?
    var events: [MissionEvent] = []
    var skills: [MissionSkill] = []
    var coverage: AssertionCoverage?
    var loaded = false
    var loading = false
    var error: String?
    /// Сервер без контрактов (старая выкладка .110): маршрута нет. Это не
    /// поломка — экран должен сказать об этом словами, а не ошибкой.
    var unsupported = false

    private let api = APIClient()

    func load(taskID: String) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let contract = try await api.missionContract(taskID: taskID)
            assertions = contract.assertions
            outcome = contract.outcome
            events = (try? await api.missionEvents(taskID: taskID)) ?? []
            skills = (try? await api.missionSkills(taskID: taskID)) ?? []
            coverage = await loadCoverage(taskID: taskID)
            error = nil
        } catch {
            if case APIError.routeMissing = error {
                unsupported = true
                assertions = []
                outcome = nil
            } else {
                self.error = error.localizedDescription
            }
        }
        loaded = true
    }

    /// Покрытие считается по плану задачи: без плана считать нечего.
    private func loadCoverage(taskID: String) async -> AssertionCoverage? {
        guard let plan = try? await api.collaborationPlans(taskId: taskID).first else { return nil }
        return try? await api.assertionCoverage(taskID: taskID, planID: plan.id)
    }
}

/// Mission Control — что считается готовым по контракту ассерций, что не
/// пройдено, что происходило.
///
/// Наблюдательный экран: контракт здесь не пишется и не правится. Пишет его
/// владелец или оркестратор через API.
struct MissionControlScreen: View {
    let taskID: String
    @State private var model = MissionControlModel()

    var body: some View {
        List {
            if model.unsupported {
                Section {
                    Text("Сервер пока не знает про контракт миссий")
                        .tfText(.body)
                        .accessibilityIdentifier("mission.unsupported")
                    Text("Обновите TaskFlow на .110 — после выкладки экран покажет контракт задачи.")
                        .tfText(.meta)
                }
            }
            if let error = model.error {
                Section {
                    Text(error)
                        .tfText(.body)
                        .accessibilityIdentifier("mission.error")
                    Button("Обновить") { Task { await model.load(taskID: taskID) } }
                }
            }
            if model.loading && !model.loaded {
                Section { TFLoading(.inline) }
            }
            if model.loaded && model.error == nil && !model.unsupported {
                if let outcome = model.outcome, outcome.hasContract {
                    summarySection(outcome)
                    assertionsSection
                    if let coverage = model.coverage, !coverage.violations.isEmpty {
                        coverageSection(coverage)
                    }
                    if !model.skills.isEmpty { skillsSection }
                    eventsSection
                } else {
                    Section {
                        Text("У задачи нет контракта ассерций")
                            .tfText(.body)
                            .accessibilityIdentifier("mission.no-contract")
                        Text("Пока контракта нет, «готово» значит «критик посмотрел и одобрил» — критерии подгоняются под получившееся. Контракт фиксирует критерии до работы, и непроверенное «готово» больше не проходит.")
                            .tfText(.meta)
                    }
                }
            }
        }
        .tfNativeHeader("Mission Control", displayMode: .inline)
        .hintAnchor(HintAnchorID.missionControlScreen)
        // Плоский список — как в координации (02.11.2026): без серых подложек.
        .listStyle(.plain)
        .refreshable { await model.load(taskID: taskID) }
        .task { await model.load(taskID: taskID) }
    }

    // MARK: - Секции

    private func summarySection(_ outcome: MissionOutcome) -> some View {
        Section("Итог по контракту") {
            LabeledContent("Пройдено", value: "\(outcome.passed) из \(outcome.total)")
            if outcome.failed > 0 {
                LabeledContent("Не пройдено", value: "\(outcome.failed)")
                    .foregroundStyle(Color.tfRed)
            }
            if outcome.blocked > 0 {
                LabeledContent("Не проверяется вживую", value: "\(outcome.blocked)")
                    .foregroundStyle(Color.tfOrange)
            }
            if outcome.pending > 0 {
                LabeledContent("Ещё не проверено", value: "\(outcome.pending)")
            }
            LabeledContent("Миссия", value: outcome.closed ? "закрыта" : "открыта")
                .foregroundStyle(outcome.closed ? Color.tfGreen : Color.tfText)
        }
    }

    private var assertionsSection: some View {
        Section("Ассерции") {
            ForEach(model.assertions) { assertion in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
                        Text(assertion.assertionId)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                        Spacer(minLength: 0)
                        TFPill(assertion.statusEnum.title, color: color(for: assertion.statusEnum))
                    }
                    Text(assertion.title)
                        .tfText(.body)
                    Text(assertion.behavior)
                        .tfText(.meta)
                    if let tool = assertion.tool {
                        Text("Проверка: \(tool)")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                    }
                    if let slot = assertion.claimedBySlot {
                        Text("Закрыл шаг: \(slot)")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfDim)
                    }
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private func coverageSection(_ coverage: AssertionCoverage) -> some View {
        Section("Дыры в покрытии") {
            ForEach(coverage.violations, id: \.message) { violation in
                Text(violation.message)
                    .tfText(.body)
                    .foregroundStyle(Color.tfRed)
            }
        }
    }

    private var skillsSection: some View {
        Section("Навыки миссии") {
            ForEach(model.skills) { skill in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(skill.name)
                        .tfText(.body)
                    Text(skill.description)
                        .tfText(.meta)
                    Text("Роль: \(skill.role)")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private var eventsSection: some View {
        Section("Журнал миссии") {
            if model.events.isEmpty {
                Text("Событий пока нет").tfText(.meta)
            }
            ForEach(model.events) { event in
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    Text(event.kindTitle)
                        .tfText(.body)
                    Text(event.ts)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                .padding(.vertical, TFSpacing.xs)
            }
        }
    }

    private func color(for status: MissionAssertionStatus) -> Color {
        switch status {
        case .pending: return .tfDim
        case .passed: return .tfGreen
        case .failed: return .tfRed
        case .blocked: return .tfOrange
        }
    }
}
