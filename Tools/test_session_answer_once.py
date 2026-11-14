#!/usr/bin/env python3
"""Ответ сессии рисуется один раз: один серверный набор блоков.

Проверка на хосте (без симулятора и без сборки приложения): собирает настоящий
код `SessionFeed.serverTextBlocks`, `SessionFeed.serverEnvelopeExtras` и
`SessionFeed.serverEnvelopeSecondLayer` из
`Sources/Features/Sessions/SessionLiveTurn.swift` и проверяет на живых
значениях:

1. Запись с `text_blocks` (документ, таблица, документ) и конвертом той же
   таблицы не даёт второго слоя — иначе таблица печатается дважды
   (владелец 14.11.2026, скрин IMG_9652).
2. Файлы конверта (`artifacts`) не теряются: второй слой есть, `output` пуст.
3. Подсказка конверта (`next_hint`) и признак вопроса (`needs_human`) тоже
   не теряются — их в `text_blocks` нет.
4. Запись без `text_blocks` (старый сервер) по-прежнему получает конверт
   целиком, только без плоского текста, — иначе пропали бы таблица и виджет.
5. Конверт из одного текста при готовых блоках второго слоя не даёт.

Запуск: python3 Tools/test_session_answer_once.py
Коды возврата: 0 — тесты прошли; 1 — тесты упали; стенд не собрался — 2.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source_path = root / 'Sources/Features/Sessions/SessionLiveTurn.swift'
source = source_path.read_text()


def method(text: str, signature: str) -> str:
    if signature not in text:
        print('FAIL: в SessionLiveTurn.swift нет ' + signature)
        sys.exit(1)
    a = text.index(signature)
    b = text.index('{', a)
    depth = 1
    end = b + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[a:end]


def whole_function(text: str, name: str) -> str:
    body = method(text, f'func {name}(')
    start = text.index(f'func {name}(')
    a = text.rindex('\n', 0, start)
    return text[a + 1:start] + body


blocks_fn = whole_function(source, 'serverTextBlocks')
extras_fn = whole_function(source, 'serverEnvelopeExtras')
second_fn = whole_function(source, 'serverEnvelopeSecondLayer')

fixture = '''import Foundation

// Подменный JSONValue: имена случаев те же, что у SessionJSON в приложении.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    indirect case array([JSONValue])
    indirect case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return NSNumber(value: value)
        case .bool(let value): return value
        case .null: return NSNull()
        case .object(let values): return values.mapValues(\\.foundationValue)
        case .array(let values): return values.map(\\.foundationValue)
        }
    }
}

typealias SessionJSON = JSONValue

struct ChatServerBlock: Decodable {
    let type: String

    static func list(fromFoundation value: Any?) -> [ChatServerBlock]? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let blocks = try? JSONDecoder().decode([ChatServerBlock].self, from: data) else { return nil }
        return blocks.isEmpty ? nil : blocks
    }
}

enum SessionFeed {
    BLOCKS
    EXTRAS
    SECOND

    static func entry(_ json: String) -> SessionJSON? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SessionJSON.self, from: data)
    }
}

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok {
        print("PASS: " + name)
    } else {
        failures += 1
        print("FAIL: " + name + (detail.isEmpty ? "" : " — " + detail))
    }
}

let tableBlock = """
{"type":"table","header":["a","b"],"rows":[["1","2"]]}
"""
let docBlock = """
{"type":"doc","chars":12,"doc":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Готово"}]}]}}
"""
let envelope = """
{"schema_version":1,"ok":true,"output":[{"type":"text","text":"Готово"},{"type":"table","columns":["a","b"],"rows":[["1","2"]]}]}
"""
func entry(blocks: String?, envelope: String, extra: String = "") -> String {
    var parts: [String] = ["\\"type\\":\\"assistant\\"", "\\"id\\":\\"e1\\"", "\\"role_envelope\\":" + envelope]
    if let blocks { parts.append("\\"text_blocks\\":[" + blocks + "]") }
    return "{" + parts.joined(separator: ",") + extra + "}"
}

// 1. Готовые блоки + конверт с той же таблицей — второго слоя нет.
let plain = SessionFeed.entry(entry(blocks: docBlock + "," + tableBlock + "," + docBlock, envelope: envelope))
check("блоки и конверт: второго слоя нет", SessionFeed.serverEnvelopeSecondLayer(plain) == nil,
      String(describing: SessionFeed.serverEnvelopeSecondLayer(plain)))

// 2. Файлы конверта сохранены, таблица из конверта не печатается.
let withFiles = SessionFeed.entry(entry(
    blocks: docBlock + "," + tableBlock,
    envelope: "{\\"schema_version\\":1,\\"ok\\":true,\\"output\\":[{\\"type\\":\\"table\\",\\"columns\\":[\\"a\\"],\\"rows\\":[[\\"1\\"]]}],\\"artifacts\\":[{\\"kind\\":\\"file\\",\\"title\\":\\"план.md\\",\\"ref\\":\\"file:///tmp/plan.md\\"}]}"
))
let filesLayer = SessionFeed.serverEnvelopeSecondLayer(withFiles).flatMap(SessionFeed.entry)
var filesOK = false
if case .object(let object)? = filesLayer {
    let output = object["output"].flatMap { value -> [JSONValue]? in
        if case .array(let items) = value { return items }
        return nil
    }
    var artifacts = 0
    if case .array(let items)? = object["artifacts"] { artifacts = items.count }
    filesOK = (output?.isEmpty ?? false) && artifacts == 1
}
check("файлы конверта остались, output пуст", filesOK, String(describing: SessionFeed.serverEnvelopeSecondLayer(withFiles)))

// 3. Подсказка и вопрос конверта не теряются.
let withHint = SessionFeed.entry(entry(
    blocks: docBlock,
    envelope: "{\\"schema_version\\":1,\\"ok\\":true,\\"output\\":[{\\"type\\":\\"text\\",\\"text\\":\\"Готово\\"}],\\"next_hint\\":\\"Скажи «давай»\\"}"
))
var hintOK = false
if case .object(let object)? = SessionFeed.serverEnvelopeSecondLayer(withHint).flatMap(SessionFeed.entry) {
    if case .string(let hint)? = object["next_hint"] { hintOK = hint == "Скажи «давай»" }
}
check("подсказка конверта осталась", hintOK, String(describing: SessionFeed.serverEnvelopeSecondLayer(withHint)))

let withHuman = SessionFeed.entry(entry(
    blocks: docBlock,
    envelope: "{\\"schema_version\\":1,\\"ok\\":true,\\"output\\":[{\\"type\\":\\"text\\",\\"text\\":\\"Готово\\"}],\\"needs_human\\":true}"
))
var humanOK = false
if case .object(let object)? = SessionFeed.serverEnvelopeSecondLayer(withHuman).flatMap(SessionFeed.entry) {
    if case .bool(let flag)? = object["needs_human"] { humanOK = flag }
}
check("признак вопроса остался", humanOK, String(describing: SessionFeed.serverEnvelopeSecondLayer(withHuman)))

// 4. Запись без text_blocks (старый сервер) — конверт целиком, но без плоского текста.
let oldServer = SessionFeed.entry(entry(blocks: nil, envelope: envelope))
var oldOK = false
if case .object(let object)? = SessionFeed.serverEnvelopeExtras(oldServer).flatMap(SessionFeed.entry),
   case .array(let items)? = object["output"] {
    oldOK = items.count == 1
}
check("старый сервер: таблица из конверта на месте", oldOK, String(describing: SessionFeed.serverEnvelopeExtras(oldServer)))
check("старый сервер: второй слой = конверт", SessionFeed.serverEnvelopeSecondLayer(oldServer) == SessionFeed.serverEnvelopeExtras(oldServer))

// 5. Конверт из одного текста при готовых блоках — второго слоя нет.
let textOnly = SessionFeed.entry(entry(
    blocks: docBlock,
    envelope: "{\\"schema_version\\":1,\\"ok\\":true,\\"output\\":[{\\"type\\":\\"text\\",\\"text\\":\\"Готово\\"}]}"
))
check("только текст в конверте: второго слоя нет", SessionFeed.serverEnvelopeSecondLayer(textOnly) == nil,
      String(describing: SessionFeed.serverEnvelopeSecondLayer(textOnly)))

exit(failures == 0 ? 0 : 1)
'''

fixture = (fixture
           .replace('BLOCKS', blocks_fn.strip())
           .replace('EXTRAS', extras_fn.strip())
           .replace('SECOND', second_fn.strip()))

with tempfile.TemporaryDirectory(prefix='session-answer-once-') as tmp:
    tmp_path = Path(tmp)
    swift = tmp_path / 'main.swift'
    swift.write_text(fixture)
    binary = tmp_path / 'test'
    build = subprocess.run(['swiftc', '-O', '-o', str(binary), str(swift)],
                           capture_output=True, text=True)
    if build.returncode != 0:
        print(build.stderr[-4000:])
        print('ОШИБКА: тесты не собрались — это поломка стенда, а не результат тестов')
        sys.exit(2)
    code = subprocess.run([str(binary)]).returncode

print('GREEN: все тесты прошли' if code == 0 else f'GREEN не достигнут: тесты упали (код {code})')
sys.exit(code)
