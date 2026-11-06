import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('design_guard_font', Path(__file__).with_name('design-system-guard.py'))
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class SystemFontStyleTests(unittest.TestCase):
    """Владелец 06.11.2026: любой текст должен подчиняться «Настройки → Шрифт».

    Системный стиль шрифта (`.font(.headline)` и т.п.) идёт мимо шкалы
    `.tfText(...)`, и ползунки настроек на такой текст не действуют.
    """

    def rules(self, source):
        return [finding[2] for finding in guard.scan_fragment(source)]

    def test_system_text_style_is_an_error(self):
        for source in [
            'Text("x").font(.headline)',
            'Text(title).font(.subheadline.weight(.semibold))',
            '.font(.caption2)',
            '.font(.title2.bold())',
            '.font(.body)',
            '.font(Font.footnote)',
            '.font(.system(.caption, design: .monospaced))',
            'let f = Font.callout',
        ]:
            with self.subTest(source=source):
                self.assertIn('system-font-style', self.rules(source))

    def test_scale_and_other_code_is_fine(self):
        for source in [
            'Text("x").tfText(.body)',
            'Text("x").tfText(.caption).fontWeight(.semibold)',
            '.tfTypeFont(size: 16, weight: .semibold)',
            'case .body: .subheadline',
            '.font(.tfMono)',
            '// .font(.headline) раньше стоял здесь',
        ]:
            with self.subTest(source=source):
                self.assertNotIn('system-font-style', self.rules(source))

    def test_marked_exception_passes(self):
        self.assertNotIn('system-font-style', self.rules('.font(.headline) // design-system-guard: ignore'))

    def test_typography_scale_itself_may_use_system_styles(self):
        self.assertIn('DesignSystem/Theme/Typography.swift', guard.SYSTEM_FONT_STYLE_ALLOWED)


if __name__ == '__main__':
    unittest.main()
