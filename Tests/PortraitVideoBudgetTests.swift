import Testing
import Foundation
@testable import TaskFlow

/// Порог одновременных видео-портретов (LOCK-ALL-TASKS-VIDEO-CAP-20261011).
///
/// Каждый кружок — отдельный `AVQueuePlayer` + `AVPlayerLooper`. На списке из
/// 69 задач это 69 плееров и 199 потоков, приложение перестаёт отвечать
/// (спиндамп симулятора от 11.10.2026). Порог держит число живых кружков, а
/// всё остальное молча рисуется статикой.
@Suite("Порог видео-портретов")
struct PortraitVideoBudgetTests {
    @MainActor
    private func budget() -> TFPortraitVideoBudget { TFPortraitVideoBudget.shared }

    @Test("Пока кружков не больше порога, играют все")
    @MainActor
    func allowsUpToLimit() {
        let b = budget()
        let ids = (0..<TFPortraitVideoBudget.limit).map { _ in UUID() }
        for id in ids { #expect(b.acquire(id, loop: "loop-\(id)"), "кружок должен получить слот в пределах порога") }
        for id in ids { #expect(b.allows(id)) }
        for id in ids { b.release(id) }
    }

    @Test("Сверх порога кружки получают статику")
    @MainActor
    func rejectsOverLimit() {
        let b = budget()
        let inBudget = (0..<TFPortraitVideoBudget.limit).map { _ in UUID() }
        for id in inBudget { b.acquire(id, loop: "loop-\(id)") }
        let extra = UUID()
        #expect(b.acquire(extra, loop: "loop-\(extra)") == false, "шестой кружок превышает бюджет — он обязан стать статичным")
        #expect(b.allows(extra) == false)
        for id in inBudget { b.release(id) }
    }

    @Test("Освободившийся слот достаётся следующему кружку")
    @MainActor
    func releasesSlot() {
        let b = budget()
        let first = (0..<TFPortraitVideoBudget.limit).map { _ in UUID() }
        for id in first { b.acquire(id, loop: "loop-\(id)") }
        #expect(b.acquire(UUID(), loop: "loop-extra") == false)

        b.release(first[first.count - 1])
        let late = UUID()
        #expect(b.acquire(late, loop: "loop-\(late)"), "после ухода кружка с экрана слот должен освободиться")
        b.release(late)
        for id in first { b.release(id) }
    }

    @Test("Повторный захват того же кружка не съедает второй слот")
    @MainActor
    func idempotentAcquire() {
        let b = budget()
        let id = UUID()
        #expect(b.acquire(id, loop: "loop-same"))
        #expect(b.acquire(id, loop: "loop-same"), "тот же кружок не должен занимать место дважды")
        for _ in 0..<(TFPortraitVideoBudget.limit - 1) { b.acquire(UUID(), loop: "loop-\(UUID())") }
        #expect(b.acquire(UUID(), loop: "loop-over") == false)
        b.release(id)
    }
}