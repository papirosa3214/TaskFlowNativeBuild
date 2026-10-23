"""Lexical SwiftUI color checks. Balanced scopes, not proximity windows or screenshots."""
import re

CONTROL = {'Button', 'Picker', 'Menu', 'Link', 'NavigationLink'}
COLOR_MODS = {'tint', 'accentColor', 'foregroundStyle', 'foregroundColor', 'background'}
RED = re.compile(r'\b(?:tfRed(?:Solid)?|tfCoral|systemRed)\b|\b(?:Color|UIColor)\.red\b|(?<!\w)\.red\b')
BLUE = re.compile(r'\b(?:Color|UIColor)\.blue\b|(?<!\w)\.blue\b|\bsystemBlue\b|\bColor\.accentColor\b|(?<!\w)\.accentColor\b')
CALL = re.compile(r'\b([A-Za-z_]\w*)\s*(?=[({])')


def masked(source):
    """Preserve offsets/newlines; hide comments and Swift string literals."""
    chars = list(source)
    i = 0
    while i < len(source):
        start = i
        if source.startswith('//', i):
            end = source.find('\n', i)
            i = len(source) if end < 0 else end
        elif source.startswith('/*', i):
            i += 2
            depth = 1
            while i < len(source) and depth:
                if source.startswith('/*', i): depth += 1; i += 2
                elif source.startswith('*/', i): depth -= 1; i += 2
                else: i += 1
        elif source[i] == '"' or (source[i] == '#' and re.match(r'#+"', source[i:])):
            hashes = 0
            while i < len(source) and source[i] == '#': hashes += 1; i += 1
            quote = '"""' if source.startswith('"""', i) else '"'
            delimiter = quote + '#' * hashes
            i += len(quote)
            while i < len(source):
                if source[i] == '\\': i += 2; continue
                if source.startswith(delimiter, i): i += len(delimiter); break
                i += 1
        else:
            i += 1
            continue
        for j in range(start, min(i, len(chars))):
            if chars[j] != '\n': chars[j] = ' '
    return ''.join(chars)


def pairs(code):
    stack, result = [], {}
    for i, ch in enumerate(code):
        if ch in '({[': stack.append((ch, i))
        elif ch in ')}]' and stack and stack[-1][0] == {')': '(', '}': '{', ']': '['}[ch]:
            _, start = stack.pop(); result[start] = i
    return result


def skip(code, i):
    while i < len(code) and code[i].isspace(): i += 1
    return i


def expression(code, start, name_end, matched):
    """Constructor/call plus trailing closures and its own modifier chain."""
    i = skip(code, name_end)
    args = ''
    trailing = []
    if i < len(code) and code[i] == '(' and i in matched:
        args = code[i+1:matched[i]]; i = matched[i]+1
    elif i >= len(code) or code[i] != '{':
        return None
    base_end = i
    mods = []
    # Swift's first trailing closure and named trailing closures (label:, etc.).
    def closures(pos, record=False):
        while True:
            point = skip(code, pos)
            named = re.match(r'([A-Za-z_]\w*)\s*:\s*(?={)', code[point:])
            if named: point += named.end(); point = skip(code, point)
            if point < len(code) and code[point] == '{' and point in matched:
                if record: trailing.append((named[1] if named else None, point+1, matched[point]))
                pos = matched[point]+1
            else: return pos
    i = closures(i, record=True); base_end = i
    while True:
        point = skip(code, i)
        mod = re.match(r'\.([A-Za-z_]\w*)\s*(?=[({])', code[point:])
        if not mod: break
        arg_start = skip(code, point+mod.end())
        if arg_start not in matched: break
        end = matched[arg_start]+1
        end = closures(end)
        mods.append((mod[1], point, end, code[arg_start+1:matched[arg_start]]))
        i = end
    return {'start': start, 'base_end': base_end, 'end': i, 'args': args, 'mods': mods, 'trailing': trailing}


def top_args(args):
    """Split only top-level argument commas, not nested closures/calls."""
    matched = pairs(args)
    start = i = 0
    result = []
    while i < len(args):
        if i in matched: i = matched[i]+1; continue
        if args[i] == ',': result.append(args[start:i]); start = i+1
        i += 1
    return result + [args[start:]]



def label_source(node, code):
    """Action/destination/menu-content closures are not the visible label."""
    for label, start, end in node['trailing']:
        if label == 'label': return code[start:end]
    for arg in top_args(node['args']):
        if re.match(r'\s*label\s*:', arg): return arg.split(':', 1)[1]
    if node['trailing'] and (node['name'] == 'Link' or
            (node['name'] == 'Button' and re.search(r'\baction\s*:', node['args'])) or
            (node['name'] == 'NavigationLink' and re.search(r'\bdestination\s*:', node['args']))):
        _, start, end = node['trailing'][-1]
        return code[start:end]
    return ''


def label_colors(label):
    """All visible built-in leaves need color; one colored sibling is insufficient.

    Custom label components/closures have their own implementation. With no
    built-in leaves here, this lexical checker cannot establish their color.
    """
    matched = pairs(label)
    nodes = []
    for found in CALL.finditer(label):
        node = expression(label, found.start(), found.end(1), matched)
        if node:
            node['name'] = found[1]; nodes.append(node)
    leaves = [node for node in nodes if node['name'] in {'Text', 'Label', 'Image'}]
    if not leaves:
        red = any(mod in {'foregroundStyle', 'foregroundColor'} and RED.search(args) for node in nodes for mod, _s, _e, args in node['mods'])
        return (None if label.strip() else False), bool(red)
    neutral, red = True, False
    for leaf in leaves:
        parents = sorted([node for node in nodes if node['start'] <= leaf['start'] and node['end'] >= leaf['end']], key=lambda node: node['end']-node['start'])
        color = next((args for parent in parents for mod, _s, _e, args in parent['mods'] if mod in {'foregroundStyle', 'foregroundColor'}), None)
        if color is None: neutral = False
        if leaf['name'] in {'Text', 'Label'} and color is not None and RED.search(color): red = True
    return neutral, red

def scan_control_colors(path, source):
    code = masked(source)
    matched = pairs(code)
    nodes = []
    for found in CALL.finditer(code):
        node = expression(code, found.start(), found.end(1), matched)
        if node:
            node['name'] = found[1]
            nodes.append(node)
    dialogs = [node for node in nodes if node['name'] in {'alert', 'confirmationDialog', 'contextMenu', 'swipeActions', 'Menu'}]
    findings = []
    lines = source.splitlines()
    emitted = set()
    def emit(offset, rule):
        line = source.count('\n', 0, offset)+1
        if line > len(lines) or 'design-system-guard: ignore' in lines[line-1]: return
        if (line, rule) not in emitted:
            findings.append((path, line, rule, lines[line-1].strip())); emitted.add((line, rule))
    # Explicit blue anywhere is a violation, including ordinary Text.
    # Scan modifier arguments only; references inside prose/comments are masked.
    for found in re.finditer(r'\.(tint|accentColor|foregroundStyle|foregroundColor|background)\s*\(', code):
        opening = code.find('(', found.start())
        if opening in matched and BLUE.search(code[opening+1:matched[opening]]):
            emit(found.start(), 'system-blue-color')
    library = '/DesignSystem/' in ('/'+path.replace('\\', '/'))
    for node in nodes:
        name = node['name']
        if library: continue  # Definitions/previews of palette primitives, not screen actions.
        if name == 'TFButton':
            variant = next((arg.split(':', 1)[1] for arg in top_args(node['args']) if re.match(r'\s*variant\s*:', arg)), None)
            if variant is None or re.search(r'\.primary\b', variant): emit(node['start'], 'red-button')
            continue
        if name not in CONTROL: continue
        inside_dialog = any(parent['start'] < node['start'] < parent['base_end'] and parent is not node for parent in dialogs)
        if inside_dialog: continue
        ancestors = sorted([parent for parent in nodes if parent['start'] < node['start'] and parent['end'] >= node['end']], key=lambda item: item['end']-item['start'])
        environment = [node]+ancestors
        # An own or nearest ancestor tint wins; a sibling tint never applies.
        tint = next((args for parent in environment for mod, _s, _e, args in parent['mods'] if mod in {'tint', 'accentColor'}), None)
        own_colors = [(mod, args) for mod, _s, _e, args in node['mods'] if mod in COLOR_MODS]
        label = label_source(node, code)
        # Follow visible text through label-local containers; colored status
        # Images alone do not make the whole action a red text button.
        label_color, red_label = label_colors(label)
        foreground = next((args for parent in environment for mod, _s, _e, args in parent['mods'] if mod in {'foregroundStyle', 'foregroundColor'}), None)
        if (foreground is not None and RED.search(foreground)) or re.search(r'\brole\s*:\s*\.destructive\b', node['args']) or any(RED.search(args) for _mod, args in own_colors) or (tint is not None and RED.search(tint)) or red_label:
            emit(node['start'], 'red-button')
        if tint is not None and not re.search(r'\bnil\b|\.none\b', tint): continue
        # Label color/styles suppress the ordinary automatic button accent.
        # Menu-style Picker specifically needs tint: foregroundStyle alone does
        # not color the selected option consistently on current iOS.
        if name != 'Picker':
            style = next((args for mod, _s, _e, args in node['mods'] if mod == 'buttonStyle'), '')
            if foreground is not None or label_color is True or (label and label_color is None) or (style and not re.search(r'\.(?:bordered|borderedProminent|automatic)\b', style)): continue
            if name == 'NavigationLink' and any(parent['name'] in {'List', 'Form'} for parent in ancestors): continue
        else:
            style = next((args for mod, _s, _e, args in node['mods'] if mod == 'pickerStyle'), '')
            if re.search(r'\.(?:segmented|wheel|inline)\b', style): continue
        emit(node['start'], 'implicit-system-blue')
    return sorted(findings, key=lambda row: (row[1], row[2]))
