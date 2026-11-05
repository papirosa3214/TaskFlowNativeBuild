import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('design_guard_sheet', Path(__file__).with_name('design-system-guard.py'))
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class RawSheetTests(unittest.TestCase):
    def rules(self, source):
        return [finding[2] for finding in guard.scan_fragment(source)]

    def test_plain_sheet_is_an_error(self):
        for source in [
            '.sheet(isPresented: $shown) { Text("x") }',
            '.sheet(item: $item) { Text($0.title) }',
            'content.sheet(item: $request) { _ in EmptyView() }',
            'self.sheet(isPresented: $shown) { EmptyView() }',
            'sheet(item: $item) { _ in EmptyView() }',
        ]:
            with self.subTest(source=source):
                self.assertIn('raw-sheet', self.rules(source))

    def test_sheet_through_design_system_is_fine(self):
        for source in [
            '.tfSheet(isPresented: $shown) { EmptyView() }',
            '.tfSheet(item: $item) { _ in EmptyView() }',
            '.taskCardSheet(taskID: $id)',
            '.tfBottomSheet(isPresented: $shown) { EmptyView() }',
            'case .sheet(let value): show(value)',
            '// .sheet(item:) требует Identifiable',
        ]:
            with self.subTest(source=source):
                self.assertNotIn('raw-sheet', self.rules(source))

    def test_marked_exception_passes(self):
        self.assertNotIn('raw-sheet', self.rules('.sheet(item: $item) { _ in EmptyView() } // design-system-guard: ignore'))

    def test_tf_sheet_itself_may_call_the_system_sheet(self):
        self.assertIn('DesignSystem/Components/TFSheet.swift', guard.RAW_SHEET_ALLOWED)


if __name__ == '__main__':
    unittest.main()
