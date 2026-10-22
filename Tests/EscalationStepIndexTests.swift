import XCTest
@testable import TaskFlow

/// Окно правки шага напоминания: номер шага не протухает.
///
/// High №2 кодревью 22.10.2026: номер шага захвачен при отрисовке и
/// использовался для `remove(at:)` и `rule.steps[index]`. Правило успевает
/// измениться (перечитано с сервера, шаги пересортированы по часам) — правка
/// попадала в соседний шаг, а при уходе за границу был «index out of range».
final class EscalationStepIndexTests: XCTestCase {

    private func step(_ hours: Int, priorityMax: Int = 4) -> EscalationStep {
        EscalationStep(afterHours: hours, priorityMax: priorityMax, channels: ["inapp"])
    }

    private func rule(_ steps: [EscalationStep]) -> EscalationRule {
        EscalationRule(
            enabled: true,
            quietFrom: "22:00",
            quietTo: "08:00",
            weekdays: [1, 2, 3, 4, 5],
            steps: steps
        )
    }

    /// Правило перечитали, шаг сдвинулся: правка должна попасть в СВОЙ шаг,
    /// а не в тот, что теперь стоит на прежнем номере.
    func testПравкаПопадаетВТотЖеШаг() {
        let own = step(24)
        let other = step(48)
        var rule = rule([own, other])
        let draft = EscalationStepDraft(index: 0, step: own)

        // Правило перечитали с сервера — перед шагом появился более ранний.
        rule.steps = [step(1), own, other]
        let edited = EscalationStep(afterHours: 30, priorityMax: 2, channels: ["inapp", "apns"])

        draft.save(step: edited, into: &rule)

        XCTAssertEqual(rule.steps.count, 3)
        XCTAssertEqual(rule.steps[0], step(1), "чужой шаг не тронут")
        XCTAssertEqual(rule.steps[1], edited, "правка попала в свой шаг")
        XCTAssertEqual(rule.steps[2], other, "соседний шаг не тронут")
    }

    /// То же для удаления: удаляется свой шаг, а не соседний по номеру.
    func testУдалениеНеБьётПоСоседнемуШагу() {
        let own = step(24)
        let other = step(48)
        var rule = rule([own, other])
        let draft = EscalationStepDraft(index: 0, step: own)

        rule.steps = [step(1), own, other]

        draft.deleteStep(from: &rule)

        XCTAssertEqual(rule.steps.count, 2)
        XCTAssertEqual(rule.steps[0], step(1), "чужой шаг не тронут")
        XCTAssertEqual(rule.steps[1], other, "удалён свой шаг")
    }

    /// Номер шага ушёл за границу списка (правило сократилось) — правка не
    /// должна падать и должна попасть в свой шаг.
    func testШагЗаПределомСпискаНеПадает() {
        let own = step(24)
        var rule = rule([own])
        let draft = EscalationStepDraft(index: 1, step: own)
        let edited = EscalationStep(afterHours: 30, priorityMax: 2, channels: ["inapp", "apns"])

        draft.save(step: edited, into: &rule)

        XCTAssertEqual(rule.steps.count, 1)
        XCTAssertEqual(rule.steps[0], edited, "правка попала в свой шаг")
    }

    /// Новый шаг: правка добавляется, а не перезаписывает существующий.
    func testНовыйШагНеПерезаписываетСуществующий() {
        let existing = step(48)
        var rule = rule([existing])
        let draft = EscalationStepDraft(index: nil, step: existing)

        draft.save(step: step(48, priorityMax: 2), into: &rule)

        XCTAssertEqual(rule.steps.count, 2)
        XCTAssertEqual(rule.steps[0], existing, "существующий шаг не тронут")
    }
}
