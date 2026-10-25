import Foundation
import XCTest
@testable import TaskFlow

/// Показанный текст живого пузыря не должен пропадать, когда сервер меняет
/// состав текстовых пунктов: закрытие хода собирает шаги и ответ в один
/// пункт, и при сопоставлении по порядковому номеру сравнивались разные
/// тексты. Раньше показанный текст обнулялся — пузырь схлопывался, его
/// высота падала, а лента, привязанная к низу, прыгала вверх и ответ
/// печатался заново.
final class RoleChatPacerPrefixTests: XCTestCase {
    func testVisibleTextSurvivesChangedComposition() {
        let step = RoleChatLiveStep(id: "s", tool: "read", detail: nil, status: .done)
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Готово"), .step(step), .text("Проверил файл")])
        drain(&pacer)
        XCTAssertTrue(pacer.visibleItems.contains(.text("Проверил файл")))

        // Сервер закрывает ход: состав пунктов другой, ответ приходит целиком.
        pacer.ingest([.step(step), .text("Проверил файл. Готово")])
        XCTAssertTrue(pacer.visibleItems.contains(.text("Проверил файл")),
                      "Показанный текст не должен обнуляться: пузырь схлопывается, лента прыгает")
    }

    func testGrownTextKeepsShownPrefix() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Проверил")])
        drain(&pacer)
        pacer.ingest([.text("Проверил файл")])
        XCTAssertTrue(pacer.visibleItems.contains(.text("Проверил")))
    }

    func testChangedTextStillResets() {
        var pacer = RoleLiveTextPacer()
        pacer.ingest([.text("Проверяю файл")])
        drain(&pacer)
        // Сервер заменил текст целиком — старое показывать нельзя.
        pacer.ingest([.text("Новый ответ")])
        XCTAssertFalse(pacer.visibleItems.contains(.text("Проверяю файл")))
    }

    private func drain(_ pacer: inout RoleLiveTextPacer, step: TimeInterval = 0.016) {
        var guardTicks = 10_000
        while pacer.hasPendingText && guardTicks > 0 {
            pacer.advance(elapsed: step)
            guardTicks -= 1
        }
    }
}
