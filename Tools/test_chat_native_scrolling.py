"""Source architecture checks, not runtime smoothness or UI tests."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class NativeChatScrollingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.screen = (ROOT / 'Sources/Features/Chat/RoleChatsScreen.swift').read_text()
        cls.feed = cls.screen.split('private var messageScroll: some View {', 1)[1].split('private var visibleLiveTurns:', 1)[0]
        cls.composer = (ROOT / 'Sources/Features/Chat/ChatVoiceComposer.swift').read_text()

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
        self.present('.scrollPosition($chatScrollPosition, anchor: .bottom)', self.feed)
        self.present('chatScrollPosition.isPositionedByUser', self.feed)
        for token in ['ScrollViewReader', '.onScrollPhaseChange', '.onChange(of: feedItems.last?.id)', 'Task.yield()']:
            self.absent(token, self.feed)

    def test_feed_does_not_apply_custom_motion_transactions(self):
        for token in ['withAnimation', '.animation(', '.transition(']:
            self.absent(token, self.feed)

    def test_keyboard_uses_native_focus_and_interactive_dismissal(self):
        self.present('.scrollDismissesKeyboard(.interactively)', self.feed)
        self.present('composerFocused = false', self.feed)
        self.present('FocusState<Bool>.Binding', self.composer)
        self.absent('ChatComposerKeyboardDismissGesture', self.composer)
        self.absent('DragGesture(', self.composer)

if __name__ == '__main__':
    unittest.main()
