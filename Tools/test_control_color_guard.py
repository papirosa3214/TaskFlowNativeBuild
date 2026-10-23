import contextlib
import importlib.util
import io
import json
import os
from unittest import mock
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location('design_guard_colors', Path(__file__).with_name('design-system-guard.py'))
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class ControlColorTests(unittest.TestCase):
    def rules(self, source):
        return [finding[2] for finding in guard.scan_fragment(source)]

    def test_tfbutton_explicit_and_default_primary_are_errors(self):
        for source in ['TFButton("Save") { save() }', 'TFButton(\n "Save", icon: "checkmark",\n variant: .primary\n) { save() }']:
            with self.subTest(source=source):
                self.assertIn('red-button', self.rules(source))

    def test_settings_secondary_outline_are_allowed(self):
        for variant in ['secondary', 'outline']:
            self.assertEqual(self.rules(f'TFButton("Save", variant: .{variant}) {{ save() }}'), [])

    def test_red_custom_button_and_coral_reset_are_errors(self):
        for source in ['Button("Reset") { reset() }\n.foregroundStyle(Color.tfCoral)', 'Button { save() } label: { Text("Save").foregroundColor(.red) }', 'Button("Save") {}\n.background(Color.tfRedSolid)', 'VStack { Button("Save") {} }.tint(.red)', 'Button("Delete", role: .destructive) {}']:
            with self.subTest(source=source):
                self.assertIn('red-button', self.rules(source))

    def test_red_error_text_is_not_a_red_button(self):
        self.assertNotIn('red-button', self.rules('VStack {\n Text(error).foregroundStyle(Color.tfRed)\n TFButton("Save", variant: .secondary) {}\n}'))

    def test_explicit_system_blue_text_and_tint_are_errors(self):
        for source in ['Text("Hi").foregroundStyle(.blue)', 'Text("Hi").foregroundColor(Color.blue)', 'Picker("Gender", selection: $gender) {}.tint(.blue)', 'VStack {}.accentColor(Color.blue)', '.tint(.blue)', 'Text("Hi").foregroundColor(Color(uiColor: .systemBlue))']:
            with self.subTest(source=source):
                self.assertIn('system-blue-color', self.rules(source))

    def test_untinted_picker_and_default_button_are_errors(self):
        for source in ['Picker("Gender", selection: $gender) { Text("Male").tag(0) }', 'Button("Save") { save() }', 'Link("Help", destination: url)', 'Menu("Options") { Button("Open") {} }']:
            with self.subTest(source=source):
                self.assertIn('implicit-system-blue', self.rules(source))

    def test_neutral_tint_is_inherited_only_from_ancestor(self):
        self.assertEqual(self.rules('VStack {\n Picker("Gender", selection: $gender) {}\n}.tint(Color.tfText)'), [])
        self.assertIn('implicit-system-blue', self.rules('VStack {\n Picker("Gender", selection: $gender) {}\n Button("Other") {}.tint(Color.tfText)\n}'))

    def test_local_blue_override_is_not_hidden_by_neutral_parent(self):
        self.assertIn('system-blue-color', self.rules('VStack { Picker("Gender", selection: $gender) {}.tint(.blue) }.tint(Color.tfText)'))

    def test_plain_neutral_button_is_allowed_and_child_color_does_not_leak(self):
        self.assertEqual(self.rules('Button("Open") {}.buttonStyle(.plain).foregroundStyle(Color.tfText)'), [])
        self.assertIn('red-button', self.rules('Button("Reset") {}.buttonStyle(.plain).foregroundStyle(Color.tfCoral)'))
        self.assertIn('implicit-system-blue', self.rules('VStack {\n Text("Title").foregroundStyle(Color.tfText)\n Picker("Gender", selection: $gender) {}\n}'))

    def test_system_dialog_is_exempt_but_external_control_is_not(self):
        source = 'VStack {}\n.alert("Continue?", isPresented: $show) {\n Button("Delete", role: .destructive) {}\n}\nPicker("Gender", selection: $gender) {}'
        findings = guard.scan_fragment(source)
        self.assertFalse(any(f[1] == 3 and f[2] in ['red-button', 'implicit-system-blue'] for f in findings))
        self.assertTrue(any(f[1] == 5 and f[2] == 'implicit-system-blue' for f in findings))

    def test_comments_and_strings_do_not_create_controls_or_colors(self):
        self.assertEqual(self.rules('// TFButton("Save") {}\n/* Picker("Gender", selection: $g) {} */\nText("Button( and .tint(.blue)")'), [])

    def test_ignore_is_explicit_and_local(self):
        source = 'TFButton("Save") {} // design-system-guard: ignore\nTFButton("Other") {}'
        hits = [f for f in guard.scan_fragment(source) if f[2] == 'red-button']
        self.assertEqual([f[1] for f in hits], [2])

    def test_label_and_label_container_red_foregrounds_are_errors(self):
        for label in ['CustomRow().foregroundStyle(Color.tfCoral)', 'HStack { Text("Save") }.foregroundStyle(Color.tfCoral)', 'Label("Save", systemImage: "checkmark").foregroundStyle(Color.tfCoral)']:
            with self.subTest(label=label):
                self.assertIn('red-button', self.rules('Button {} label: { ' + label + ' }'))

    def test_red_status_icon_does_not_make_neutral_text_a_red_button(self):
        source = 'Button {} label: { HStack { Text("Save").foregroundStyle(Color.tfText); Image(systemName: "circle").foregroundStyle(Color.tfRed) } }'
        self.assertNotIn('red-button', self.rules(source))

    def test_inherited_red_foreground_is_an_error(self):
        self.assertIn('red-button', self.rules('VStack { Button("Save") {} }.foregroundStyle(Color.tfCoral)'))

    def test_nil_tint_does_not_prove_a_neutral_color(self):
        self.assertIn('implicit-system-blue', self.rules('Picker("Gender", selection: $gender) {}.tint(nil)'))
        self.assertIn('system-blue-color', self.rules('Picker("Gender", selection: $gender) {}.tint(.accentColor)'))

    def test_nearest_tint_wins_with_repeated_modifiers(self):
        self.assertIn('red-button', self.rules('VStack { Button("Save") {} }.tint(.red).tint(Color.tfText)'))

    def test_colored_icon_does_not_hide_automatic_text_color(self):
        self.assertIn('implicit-system-blue', self.rules('Button { save() } label: { HStack { Text("Save"); Image(systemName: "checkmark").foregroundStyle(Color.tfText) } }'))

    def test_menu_item_color_does_not_color_menu_title(self):
        self.assertIn('implicit-system-blue', self.rules('Menu("Options") { Button("Open") {}.foregroundStyle(Color.tfText) }'))

    def test_button_action_body_does_not_supply_label_color(self):
        self.assertIn('implicit-system-blue', self.rules('Button("Save") { let message = Text("X").foregroundStyle(Color.tfText) }'))

    def test_new_rules_fail_cli_and_are_not_warnings(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(guard.render(guard.scan_fragment('TFButton("Save") {}')), 1)
            self.assertEqual(guard.render(guard.scan_fragment('Picker("Gender", selection: $gender) {}')), 1)

    def test_new_file_removing_tint_is_detected_with_unchanged_control_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'Sources/Test.swift'
            source.parent.mkdir()
            source.write_text('VStack {\n Picker("Gender", selection: $gender) {}\n}.tint(Color.tfText)\n')
            proc = subprocess.run([sys.executable, str(Path(guard.__file__)), '--root', tmp, '--new-file', str(source)], input=source.read_text().replace('.tint(Color.tfText)', ''), text=True, capture_output=True)
            self.assertEqual(proc.returncode, 1, proc.stdout)
            self.assertIn('[implicit-system-blue]', proc.stdout)

    def test_new_file_neutral_parent_not_rejected_by_fragment_false_positive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'Sources/Test.swift'
            source.parent.mkdir()
            source.write_text('VStack {\n Text("Old")\n}.tint(Color.tfText)\n')
            new = source.read_text().replace('Text("Old")', 'Picker("Gender", selection: $gender) {}')
            proc = subprocess.run([sys.executable, str(Path(guard.__file__)), '--root', tmp, '--new-file', str(source)], input=new, text=True, capture_output=True)
            self.assertEqual(proc.returncode, 0, proc.stdout)

class GuardEntryPointTests(unittest.TestCase):
    def test_folder_gate_rejects_default_red_without_baseline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'Sources').mkdir()
            (root / 'Sources/Test.swift').write_text('TFButton("Save") {}')
            proc = subprocess.run([sys.executable, guard.__file__, '--root', tmp, '--folder'], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 1)
            self.assertIn('[red-button]', proc.stdout)

    def test_diff_deletion_of_tint_is_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'Sources').mkdir()
            file = root / 'Sources/Test.swift'
            file.write_text('VStack {\n Picker("Gender", selection: $gender) {}\n}.tint(Color.tfText)\n')
            subprocess.run(['git', 'init', '-q', tmp], check=True)
            subprocess.run(['git', '-C', tmp, 'add', 'Sources'], check=True)
            subprocess.run(['git', '-C', tmp, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture'], check=True)
            file.write_text(file.read_text().replace('.tint(Color.tfText)', ''))
            proc = subprocess.run([sys.executable, guard.__file__, '--root', tmp, '--diff', 'HEAD'], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 1, proc.stdout)
            self.assertIn('[implicit-system-blue]', proc.stdout)

    def hook(self):
        default = Path(__file__).parents[1] / '.claude/hooks/guard_design_system.py'
        spec = importlib.util.spec_from_file_location('hook_test', os.environ.get('DESIGN_GUARD_HOOK_TEST_SOURCE', str(default)))
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        return module

    def test_edit_hook_supplies_complete_inherited_color_context(self):
        hook = self.hook()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'Sources').mkdir(); (root / 'Tools').mkdir()
            (root / 'Tools/design-system-guard.py').touch()
            file = root / 'Sources/Test.swift'
            file.write_text('VStack {\n Text("Old")\n}.tint(Color.tfText)')
            payload = {"tool_name": "Edit", "tool_input": {"file_path": str(file), "old_string": 'Text("Old")', "new_string": 'Picker("Gender", selection: $gender) {}'}}
            with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": tmp}), mock.patch.object(sys, 'stdin', io.StringIO(json.dumps(payload))), mock.patch.object(hook.subprocess, 'run', return_value=type('Result', (), {'returncode': 0})()) as run:
                self.assertEqual(hook.main(), 0)
                self.assertIn('--new-file', run.call_args.args[0])
                self.assertIn('.tint(Color.tfText)', run.call_args.kwargs['input'])

    def test_color_error_does_not_pass_on_second_hook_attempt(self):
        hook = self.hook()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'Sources').mkdir(); (root / 'Tools').mkdir()
            (root / 'Tools/design-system-guard.py').touch(); hook.STATE_DIR = str(root / 'state')
            payload = {"tool_name": "Write", "tool_input": {"file_path": str(root / 'Sources/Test.swift'), "content": 'TFButton("Save") {}'}}
            failed = type('Result', (), {'returncode': 1, 'stdout': 'error [red-button]', 'stderr': ''})()
            with mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": tmp}), mock.patch.object(hook.subprocess, 'run', return_value=failed), contextlib.redirect_stderr(io.StringIO()):
                for _ in range(2):
                    with mock.patch.object(sys, 'stdin', io.StringIO(json.dumps(payload))):
                        self.assertEqual(hook.main(), 2)

if __name__ == '__main__':
    unittest.main()
