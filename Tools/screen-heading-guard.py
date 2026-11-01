"""Screen-local semantic heading contracts; intentionally not a Swift renderer."""
import json
import re
from pathlib import Path


def block(text, start):
    """Return a balanced Swift block, ignoring braces in comments/strings."""
    depth = 0
    quoted = escaped = comment = False
    begin = None
    for i in range(start, len(text)):
        ch = text[i]
        if comment:
            if ch == '\n':
                comment = False
            continue
        if quoted:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == '"':
                quoted = False
            continue
        if ch == '"':
            quoted = True
        elif text[i:i+2] == '//':
            comment = True
        elif ch == '{':
            if begin is None:
                begin = i + 1
            depth += 1
        elif ch == '}' and begin is not None:
            depth -= 1
            if depth == 0:
                return begin, text[begin:i]
    return None, ''


def heading(text, selector):
    type_match = re.search(r'\b(?:struct|class|extension)\s+' + re.escape(selector['type']) + r'\b', text)
    if not type_match:
        return 1, None
    type_start, source = block(text, type_match.end())
    member = re.search(r'\b(?:func|var)\s+' + re.escape(selector['member']) + r'\b', source)
    if not member:
        return 1, None
    start, body = block(source, member.end())
    offset = type_start + start
    # Contracts identify the semantic section container. Its first text/label is
    # the heading; other body text is deliberately outside this comparison.
    clean = re.sub(r'//[^\n]*', lambda m: ' ' * len(m.group(0)), body)
    # `SettingsCapsLabel` в списке — для файлов, которые ещё не переведены на
    # канон: такой заголовок сторож опознаёт по имени (иначе «заголовок не
    # найден» и проверка закрылась бы вслепую). Вернуть обёртку нельзя —
    # это ловит правило `raw-caps-heading` сторожа дизайн-системы.
    found = re.search(r'\b(SettingsCapsLabel|TFSectionHeader|Text)\s*\([^\n]*?\)', clean)
    if not found:
        return text[:offset].count('\n') + 1, None
    tail = clean[found.end():]
    modifiers = re.match(r'[^\n]*(?:\n[ \t]*\.[^\n]*)*', tail)[0]
    expression = found[0] + modifiers
    # Content and padding may differ; typography and case may not.
    styles = []
    for match in re.finditer(r'\.(tfText|font|fontWeight|foregroundStyle|foregroundColor|textCase|tracking|kerning)\s*\(', modifiers):
        depth = 1
        end = match.end()
        while end < len(modifiers) and depth:
            depth += (modifiers[end] == '(') - (modifiers[end] == ')')
            end += 1
        styles.append(re.sub(r'\s+', '', modifiers[match.start():end]))
    signature = found[1] + '|' + '|'.join(sorted(styles))
    if found[1] == 'Text' and '.uppercased()' in expression:
        signature += '|uppercased'
    # Режим заголовка — часть оформления: «капс» и обычная подпись на одном
    # уровне различаться не должны.
    if found[1] == 'TFSectionHeader' and 'style:.caps' in re.sub(r'\s+', '', expression):
        signature += '|caps'
    return text[:offset + found.start()].count('\n') + 1, signature


def scan_screen_headings(root, scopes=None, overrides=None, affected=None):
    root = Path(root)
    overrides = overrides or {}
    if scopes is None:
        config = root / 'Tools/screen-heading-scopes.json'
        if not config.exists():
            return []
        scopes = json.loads(config.read_text())
    findings = []
    for scope in scopes:
        paths = {str(root / item['path']) for item in scope['headings']}
        if affected is not None and not paths.intersection(affected):
            continue
        reference = None
        for item in scope['headings']:
            path = str(root / item['path'])
            try:
                text = overrides[path] if path in overrides else Path(path).read_text()
                line, signature = heading(text, item)
            except OSError:
                line, signature = 1, None
            if signature is None:
                reason = f"{scope['screen']}/{scope['level']}: heading missing in {item['type']}.{item['member']}"
            elif reference is None:
                reference = signature
                continue
            elif signature != reference:
                reason = f"{scope['screen']}/{scope['level']}: {signature} != {reference}"
            else:
                continue
            findings.append((path, line, 'screen-heading-consistency', reason))
    return findings
