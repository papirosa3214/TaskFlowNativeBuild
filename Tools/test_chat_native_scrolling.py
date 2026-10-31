"""Source architecture checks, not runtime smoothness or UI tests."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class NativeChatScrollingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.screen = (ROOT / 'Sources/Features/Roles/RoleChatsScreen.swift').read_text()
        cls.feed = cls.screen.split('private var messageScroll: some View {', 1)[1].split('private var visibleLiveTurns:', 1)[0]
        cls.composer = (ROOT / 'Sources/ChatComponents/Composer/ChatVoiceComposer.swift').read_text()

    def absent(self, token, source):
        self.assertTrue(token not in source, 'Unexpected custom mechanism: ' + token)

    def present(self, token, source):
        self.assertTrue(token in source, 'Missing native integration: ' + token)

    def test_growth_cannot_feed_measured_height_back_into_scroll_layout(self):
        for name in ['readingReplyHeight', 'ownAnchorHeight', 'readingSpacer', 'readingOverflows', 'ownAnchorFraction']:
            with self.subTest(name=name):
                self.absent(name, self.screen)
        self.absent('.onGeometryChange(', self.feed)

    def test_native_position_owns_user_scrolling_without_packet_scroll_requests(self):
        # Якорь у привязки позиции не задан: «быть у низа» держит
        # `defaultScrollAnchor`, а не два механизма сразу (владелец 30.10.2026).
        self.present('.scrollPosition($chatScrollPosition)', self.feed)
        self.absent('.scrollPosition($chatScrollPosition, anchor: .bottom)', self.feed)
        self.present('.defaultScrollAnchor(chatFollowsBottom ? .bottom : nil, for: .sizeChanges)', self.feed)
        for token in ['ScrollViewReader', '.onChange(of: feedItems.last?.id)', 'Task.yield()']:
            self.absent(token, self.feed)

    def test_bottom_following_changes_only_from_the_owners_scroll(self):
        # Рост ответа тоже двигает геометрию; привязка к низу не должна от
        # этого мигать (владелец 30.10.2026).
        self.present('if chatScrollPhase == .tracking || chatScrollPhase == .interacting', self.feed)
        self.absent('isPositionedByUser || chatIsNearBottom', self.feed)

    def test_feed_does_not_animate_row_insertions(self):
        # Анимация всей ленты на вставку строк не успевала за ростом ответа и
        # удерживала ленту между двумя положениями — качели (30.10.2026).
        self.absent('.animation(TFMotion.standard, value: orderedFeed', self.feed)
        self.absent('withAnimation', self.feed)

    def test_keyboard_uses_native_focus_and_interactive_dismissal(self):
        self.present('.scrollDismissesKeyboard(.interactively)', self.feed)
        self.present('composerFocused = false', self.feed)
        self.present('FocusState<Bool>.Binding', self.composer)
        self.absent('ChatComposerKeyboardDismissGesture', self.composer)
        self.absent('DragGesture(', self.composer)

if __name__ == '__main__':
    unittest.main()
