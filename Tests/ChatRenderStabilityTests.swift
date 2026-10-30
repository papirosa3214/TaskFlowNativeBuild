import Foundation
import XCTest
#if !CHAT_RENDER_HOST
@testable import TaskFlow
#endif

final class ChatRenderStabilityTests: XCTestCase {
    func testShorteningSettledTextClampsTheRevealedPrefix() {
        let history = RoleTextRevealHistory()
        let now = Date(timeIntervalSince1970: 100)
        history.record(count: 100, now: now, rate: 100, animated: false)
        history.record(count: 20, now: now, rate: 100, animated: true)
        XCTAssertEqual(history.revealedUpTo, 20)
        history.record(count: 21, now: now, rate: 100, animated: true)
        XCTAssertEqual(history.opacity(at: 19, now: now), 1)
        XCTAssertEqual(history.opacity(at: 20, now: now), 0)
    }

    func testShorteningPendingTailKeepsTheSettledPrefix() {
        let history = RoleTextRevealHistory()
        let now = Date(timeIntervalSince1970: 100)
        history.record(count: 80, now: now, rate: 100, animated: false)
        history.record(count: 100, now: now, rate: 100, animated: true)
        history.record(count: 90, now: now, rate: 100, animated: true)
        XCTAssertEqual(history.revealedUpTo, 80)
        XCTAssertEqual(history.opacity(at: 79, now: now), 1)
    }

    #if CHAT_RENDER_HOST
    func testInsertingTextDoesNotReplaceTheFollowingActionRow() {
        let before = segmentIDs(["actions:read", "actions:write"])
        let after = segmentIDs(["actions:read", "text:1", "actions:write"])
        XCTAssertEqual(before[1], after[2], "An existing action must keep its parent identity")
        XCTAssertNotEqual(before[1], after[1], "New text must not inherit the action's state")
    }

    // Run the real renderer with a recording drawing context. No UI or simulator.
    func testSettledLongReplyDrawsPerLineRatherThanPerGlyph() {
        let now = Date(timeIntervalSince1970: 100)
        let renderer = RoleRevealRenderer(fade: RoleTextFade(isAnimating: false),
                                          now: now, history: RoleTextRevealHistory())
        let layout = Array(repeating: [Array(0..<100)], count: 100)
        var context = GraphicsContext()
        renderer.draw(layout: layout, in: &context)
        XCTAssertEqual(context.record.lines, 100)
        XCTAssertEqual(context.record.glyphs, 0)
    }

    func testFreshLineCannotBypassTheFade() {
        let now = Date(timeIntervalSince1970: 100)
        let renderer = RoleRevealRenderer(fade: RoleTextFade(rate: 100, isAnimating: true),
                                          now: now, history: RoleTextRevealHistory())
        var context = GraphicsContext()
        renderer.draw(layout: [[[0]]], in: &context)
        XCTAssertEqual(context.record.lines, 0, "A fresh line is still transparent")
        XCTAssertEqual(context.record.glyphs, 0)
    }

    func testMixedLineDrawsOnlyTheVisibleGlyphs() {
        let now = Date(timeIntervalSince1970: 100)
        let history = RoleTextRevealHistory()
        history.record(count: 2, now: now, rate: 100, animated: false)
        let renderer = RoleRevealRenderer(fade: RoleTextFade(rate: 100, isAnimating: true),
                                          now: now, history: history)
        var context = GraphicsContext()
        renderer.draw(layout: [[[0, 1, 2]]], in: &context)
        XCTAssertEqual(context.record.lines, 0)
        XCTAssertEqual(context.record.glyphs, 2)
    }
    #endif
}
