import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("guard", Path(__file__).with_name("design-system-guard.py"))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class ScreenHeadingTests(unittest.TestCase):
    def scan(self, second, other_screen=False, override=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'Sources').mkdir()
            (root / 'Sources/Profile.swift').write_text('''struct Profile: View {
func section(title: String) -> some View {
 VStack { TFSectionHeader(title, style: .caps) }
}
}''')
            (root / 'Sources/External.swift').write_text('''struct External: View {
var body: some View {
 VStack {
''' + second + '''
 }
}
}''')
            config = [{"screen": "Profile", "level": "sections", "headings": [
                {"path": "Sources/Profile.swift", "type": "Profile", "member": "section"},
                {"path": "Sources/External.swift", "type": "External", "member": "body"}]}]
            if other_screen:
                config = [dict(config[0], headings=config[0]['headings'][:1]),
                          dict(config[0], screen='Other', headings=config[0]['headings'][1:])]
            return guard.scan_screen_headings(str(root), config, overrides=override or {})

    def test_allowed_title_still_conflicts_with_sibling_sections(self):
        self.assertTrue(self.scan('Text("External").tfText(.title).foregroundStyle(Color.tfText)'))

    def test_shared_component_matches(self):
        self.assertEqual(self.scan('TFSectionHeader("External", style: .caps)'), [])

    def test_other_screen_can_have_its_own_style(self):
        self.assertEqual(self.scan('Text("External").tfText(.title)', other_screen=True), [])

    def test_override_on_same_component_is_a_mismatch(self):
        self.assertTrue(self.scan('TFSectionHeader("External", style: .caps)\n .fontWeight(.bold)'))

    def test_caps_mode_must_match_sibling_sections(self):
        self.assertTrue(self.scan('TFSectionHeader("External", style: .standard)'))

    def test_missing_heading_fails_closed(self):
        self.assertTrue(self.scan('Image(systemName: "star")'))

    def test_comments_are_not_headings(self):
        self.assertEqual(self.scan('// Text("Fake").tfText(.title)\nTFSectionHeader("External", style: .caps)'), [])

if __name__ == '__main__':
    unittest.main()
