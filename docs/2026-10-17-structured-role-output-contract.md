# Единый JSON-выход ролей TaskFlow — черновик

**Статус:** контракт v1 принят как основа внедрения по указанию владельца
17.10.2026. Первый этап — iOS renderer; серверную проверку, переход ролей и
передачу между ролями внедрять отдельными шагами с проверкой совместимости.

## Зафиксированные решения владельца

- Роль выдаёт данные в одном фиксированном формате JSON.
- Список типов и полей закрытый: роль выбирает из заданных вариантов и не
  придумывает собственные типы.
- Обычный живой текст остаётся полноценной частью ответа и должен проявляться
  в чате по мере генерации, без показа пользователю сырого JSON.
- Цвета, типографика, размеры, отступы и сам вид карточек задаёт iOS-клиент.
- Дальнейшая настройка деталей виджетов идёт по реальному использованию.

## Что система уже делает

| Путь | Текущий формат и обработка |
|---|---|
| Обычный чат роли | Сервер распознаёт JSON и прежнюю YAML-подобную запись, затем выдаёт нормализованное поле `role_envelope` с `contract: "role.v1"`, строковым `output` и списком строк `artifacts`. Текст `output` также остаётся в `message.text`. Новый iOS renderer теперь читает и этот фактический формат, и целевой вариант со `schema_version: 1` и типизированными блоками; текущие роли пока не формируют массив блоков. |
| Сдача этапа плана | Инструмент принимает короткий `result` и обязательный `report_markdown`; структурный артефакт передаётся отдельно как `summary`, `payload`, `evidence`. |
| Отчёт владельцу | Общая политика задаёт пять разделов: «Результат», «Что сделано», «Проверки», «Ограничения», «Материалы». Сервер проверяет разделы и сохраняет Markdown-заметку в папку задачи. |
| Передача следующей роли | Плановый узел задаёт `key`, `type`, `format: json`, `required_fields`; связь плана указывает, какой артефакт передать. Следующий этап получает `slot_key`, `artifact_key`, `summary`, `payload`, `evidence`. |
| Итоговая проверка | Критик передаёт отчёт вместе с отдельным вердиктом. Вердикт и решение о принятии не должны выводиться только из текста отчёта. |

Локальный iOS-прототип показывает корректный префикс текущего `text` блока из
незакрытого `tf-json`, сохраняя обычный рендер Markdown. Незавершённые
escape-последовательности не появляются. Сохранённые сообщения с сервера теперь
передают `role_envelope` в renderer; текущий серверный вариант со строковым
`output` отображается как Markdown, целевой вариант с массивом блоков — нативными
компонентами. Сам сервер пока не выдаёт типизированные блоки в live-потоке.

Роли загружаются из таблицы `roles`; файлы `server/scripts/role-prompts/`
служат запасным источником инструкции. Поэтому список файлов с промптами сам
по себе не доказывает, какие роли включены. Read-only запрос к текущей базе
сервера 17.10.2026 показал десять включённых ролей:

| Роль | Источник инструкции в текущем состоянии |
|---|---|
| `researcher`, `analyst`, `critic_verifier`, `architect`, `builder`, `qa`, `designer` | В БД `prompt` пустой; файл fallback есть. |
| `secretary` | Есть и DB prompt, и файл fallback. |
| `code_orchestrator`, `infra_engineer` | Есть DB prompt; файла fallback нет. |

Первые семь — начальный набор в `roleRouting.ts`; остальные три видны только
при проверке текущего состояния таблицы. Состав остаётся динамическим и может
измениться независимо от версии клиента.

В инструкциях семи основных ролей уже повторяется общий внешний набор
`ok` / `output` / `artifacts` / `error` / `next_hint` / `needs_human`.
Назначение полей описано одинаково, но `output` сейчас текстовый. Серверная
нормализация называется `role.v1`; она не содержит `schema_version`,
`plan_artifact` и массива UI-блоков из целевого контракта ниже. Это два явно
обрабатываемых состояния миграции, а не один уже внедрённый формат.

В двух текущих шаблонах планов уже перечислены конкретные типы артефактов:

| Шаблон | Роль и ключ артефакта | Обязательные поля payload |
|---|---|---|
| Продуктовая фича | Аналитик → `feature_spec` | `scope`, `out_of_scope`, `acceptance_criteria`, `nfr`, `open_questions` |
| Продуктовая фича | Архитектор → `architecture_decision` | `context`, `options`, `decision`, `consequences`, `rollout_rollback` |
| Продуктовая фича | Дизайнер → `feature_ux_spec` | `screens`, `state_matrix`, `accessibility`, `open_questions` |
| Продуктовая фича | Разработчик → `implementation_pack` | `change_refs`, `build_id`, `test_report`, `deployment_notes`, `known_limitations` |
| Продуктовая фича | QA → `feature_test_report` | `acceptance_matrix`, `evidence`, `defects`, `recommendation` |
| Регрессия | Аналитик → `bug_report` | `summary`, `repro_steps`, `observed`, `expected`, `severity`, `scope`, `environment`, `workaround` |
| Регрессия | Архитектор → `root_cause_analysis` | `context`, `options`, `decision`, `consequences`, `rollout_rollback` |
| Регрессия | Разработчик → `fix_pack` | `change_refs`, `root_cause_summary`, `build_id`, `test_report`, `deployment_notes`, `known_limitations` |
| Регрессия | QA → `regression_test_report` | `acceptance_matrix`, `evidence`, `defects`, `recommendation` |

Эти ключи назначаются шаблонами и связываются рёбрами плана. Сервер
проверяет имя артефакта и наличие перечисленных полей; типы и ограничения
значений каждого поля текущим контрактом ещё не описаны.

Кроме шаблонов фичи и регрессии, для исполнительской дочерней карточки
создаётся `card_result` типа `result_pack` с полями `summary`, `evidence`,
`document_refs`. Профили `single_executor`, `research`, `delivery` и
`full_cycle` обычно создают узлы без `output_artifact`: обязательным остаётся
читаемый отчёт. У произвольного или ручного узла контракт может быть задан
прямо в плане, поэтому у роли нет неизменного глобального artifact key.

## Модель контракта v1

### Форма v1

Один внешний объект используется и в обычном чате, и в отчётах ролей. Все
ключи конверта обязательны: пустое значение передаётся как `null`, `false`
или `[]`, а не опускается. Неизвестные ключи на уровнях конверта и блоков
отклоняются.

| Ключ | Тип | Правило |
|---|---|---|
| `schema_version` | integer | Ровно `1` для этого варианта схемы. |
| `ok` | boolean | Итог выполнения самой роли, не вердикт критика и не статус этапа плана. |
| `output` | block[] | Порядок блоков задаёт порядок показа. Может содержать обычный текст, отчёт и визуальные данные. |
| `artifacts` | artifact_ref[] | Созданные для владельца документы, файлы, ссылки или изменения; только ссылки и короткие подписи. |
| `plan_artifact` | plan_artifact или null | Машинный payload для передачи по плану; его key/type/поля задаёт контракт текущего узла. Вне узла с контрактом — `null`. |
| `error` | object или null | Стандартизированная ошибка при `ok: false`; `null` при успехе. |
| `next_hint` | string или null | Рекомендованный следующий шаг; не выбирает и не запускает роль. |
| `needs_human` | boolean | Нужны ли решение или подтверждение владельца. |

`artifacts` сохраняет нынешнее значение общего конверта. `plan_artifact` —
отдельное поле для машинной сдачи этапа; серверный адаптер передаёт его в
действующий аргумент `artifact` инструмента `taskflow_subtask_done`. В обычном
чате, без плана с `output_artifact`, здесь всегда `null`.

`error` имеет фиксированные ключи `code`, `message`, `retryable`; коды v1:
`validation_error`, `tool_error`, `blocked`, `other`. В `message` остаётся
короткое объяснение на русском. Технические журналы в чат не вкладываются,
а передаются как ссылка-материал или evidence.

### Закрытый список блоков

| `type` | Обязательные поля | Допустимые дополнительные поля |
|---|---|---|
| `text` | `text` | Нет. Обычный текст; оформление задаёт клиент. |
| `heading` | `text`, `level` | `level`: 1–3. |
| `list` | `items` | `ordered` (boolean, по умолчанию false). Один уровень списка; для вложенности — отдельный следующий блок. |
| `table` | `columns`, `rows` | `title`. Колонки — строки; каждая строка должна иметь столько же ячеек, сколько колонок. Выравнивание выбирает клиент. |
| `status` | `code`, `title` | `text`. `code`: `info`, `in_progress`, `passed`, `failed`, `blocked`, `skipped`. |
| `progress` | `title`, `current`, `total` | `unit`, `label`; числа неотрицательные, `current` не больше `total`. |
| `chart` | `title`, `kind`, `points` | `unit`; `kind`: `bar` или `line`; точка — `{label, value}`. |
| `diagram` | `title`, `kind`, `items` | `kind`: `chain`, `ladder` или `timeline`; элемент — `{label, state, detail?}`. `state`: `queued`, `in_progress`, `done`, `blocked`, `failed`, `skipped`. |
| `report` | `report_kind`, `sections` | `report_kind`: `intermediate` или `final`; разделы — общая форма ниже. |
| `handoff` | `artifact_key`, `summary` | Нет. Получатель берётся из графа плана и никогда не выбирается текстом роли. |

Все блоки запрещают незаявленные поля. Markdown- и HTML-разметка внутри `text`
не интерпретируется как оформление. Свободный HTML, CSS, JavaScript,
модельные имена компонентов, цвета, шрифты, размеры, отступы, координаты и
произвольные URL действиями не являются частью v1. `chart` и `diagram` несут
только данные; оформление и геометрию выбирает клиент.

Ниже — машинно-читаемый черновик JSON Schema Draft 2020-12 для конверта и
блоков. Ограничения, зависящие от другого поля или контекста узла плана,
проверяются дополнительным серверным валидатором.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "TaskFlow role output v1",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "ok", "output", "artifacts", "plan_artifact", "error", "next_hint", "needs_human"],
  "properties": {
    "schema_version": { "const": 1 },
    "ok": { "type": "boolean" },
    "output": {
      "type": "array", "maxItems": 200,
      "items": { "$ref": "#/$defs/outputBlock" }
    },
    "artifacts": {
      "type": "array", "maxItems": 20,
      "items": { "$ref": "#/$defs/material" }
    },
    "plan_artifact": { "oneOf": [{ "type": "null" }, { "$ref": "#/$defs/planArtifact" }] },
    "error": { "oneOf": [{ "type": "null" }, { "$ref": "#/$defs/error" }] },
    "next_hint": { "type": ["string", "null"], "maxLength": 4000 },
    "needs_human": { "type": "boolean" }
  },
  "allOf": [
    { "if": { "properties": { "ok": { "const": true } }, "required": ["ok"] }, "then": { "properties": { "error": { "type": "null" } } } },
    { "if": { "properties": { "ok": { "const": false } }, "required": ["ok"] }, "then": { "properties": { "error": { "$ref": "#/$defs/error" } } } }
  ],
  "$defs": {
    "text": {
      "type": "object", "additionalProperties": false, "required": ["type", "text"],
      "properties": { "type": { "const": "text" }, "text": { "type": "string", "maxLength": 65536 } }
    },
    "heading": {
      "type": "object", "additionalProperties": false, "required": ["type", "text", "level"],
      "properties": { "type": { "const": "heading" }, "text": { "type": "string", "maxLength": 1000 }, "level": { "type": "integer", "minimum": 1, "maximum": 3 } }
    },
    "list": {
      "type": "object", "additionalProperties": false, "required": ["type", "items"],
      "properties": { "type": { "const": "list" }, "ordered": { "type": "boolean", "default": false }, "items": { "type": "array", "minItems": 1, "maxItems": 200, "items": { "type": "string", "maxLength": 4000 } } }
    },
    "table": {
      "type": "object", "additionalProperties": false, "required": ["type", "columns", "rows"],
      "properties": {
        "type": { "const": "table" }, "title": { "type": "string", "maxLength": 1000 },
        "columns": { "type": "array", "minItems": 1, "maxItems": 12, "items": { "type": "string", "maxLength": 200 } },
        "rows": { "type": "array", "maxItems": 100, "items": { "type": "array", "items": { "type": "string", "maxLength": 4000 } } }
      }
    },
    "status": {
      "type": "object", "additionalProperties": false, "required": ["type", "code", "title"],
      "properties": { "type": { "const": "status" }, "code": { "enum": ["info", "in_progress", "passed", "failed", "blocked", "skipped"] }, "title": { "type": "string", "maxLength": 1000 }, "text": { "type": "string", "maxLength": 4000 } }
    },
    "progress": {
      "type": "object", "additionalProperties": false, "required": ["type", "title", "current", "total"],
      "properties": { "type": { "const": "progress" }, "title": { "type": "string", "maxLength": 1000 }, "current": { "type": "number", "minimum": 0 }, "total": { "type": "number", "exclusiveMinimum": 0 }, "unit": { "type": "string", "maxLength": 64 }, "label": { "type": "string", "maxLength": 256 } }
    },
    "chart": {
      "type": "object", "additionalProperties": false, "required": ["type", "title", "kind", "points"],
      "properties": { "type": { "const": "chart" }, "title": { "type": "string", "maxLength": 1000 }, "kind": { "enum": ["bar", "line"] }, "unit": { "type": "string", "maxLength": 64 }, "points": { "type": "array", "minItems": 1, "maxItems": 500, "items": { "type": "object", "additionalProperties": false, "required": ["label", "value"], "properties": { "label": { "type": "string", "maxLength": 256 }, "value": { "type": "number" } } } } }
    },
    "diagram": {
      "type": "object", "additionalProperties": false, "required": ["type", "title", "kind", "items"],
      "properties": { "type": { "const": "diagram" }, "title": { "type": "string", "maxLength": 1000 }, "kind": { "enum": ["chain", "ladder", "timeline"] }, "items": { "type": "array", "minItems": 1, "maxItems": 100, "items": { "type": "object", "additionalProperties": false, "required": ["label", "state"], "properties": { "label": { "type": "string", "maxLength": 256 }, "state": { "enum": ["queued", "in_progress", "done", "blocked", "failed", "skipped"] }, "detail": { "type": "string", "maxLength": 2000 } } } } }
    },
    "check": {
      "type": "object", "additionalProperties": false, "required": ["label", "status"],
      "properties": { "label": { "type": "string", "maxLength": 1000 }, "status": { "enum": ["passed", "failed", "blocked", "skipped", "not_run"] }, "detail": { "type": "string", "maxLength": 4000 }, "evidence_refs": { "type": "array", "maxItems": 8, "items": { "type": "string", "maxLength": 1024 } } }
    },
    "material": {
      "type": "object", "additionalProperties": false, "required": ["kind", "title", "ref"],
      "properties": { "kind": { "enum": ["url", "document", "file", "change", "artifact", "log"] }, "title": { "type": "string", "maxLength": 1000 }, "ref": { "type": "string", "maxLength": 1024 } }
    },
    "report": {
      "type": "object", "additionalProperties": false, "required": ["type", "report_kind", "sections"],
      "properties": {
        "type": { "const": "report" }, "report_kind": { "enum": ["intermediate", "final"] },
        "sections": {
          "type": "object", "additionalProperties": false,
          "required": ["result", "work", "checks", "limitations", "materials"],
          "properties": {
            "result": { "type": "array", "items": { "$ref": "#/$defs/reportBlock" } },
            "work": { "type": "array", "items": { "$ref": "#/$defs/reportBlock" } },
            "checks": { "type": "array", "maxItems": 200, "items": { "$ref": "#/$defs/check" } },
            "limitations": { "type": "array", "items": { "$ref": "#/$defs/reportBlock" } },
            "materials": { "type": "array", "maxItems": 8, "items": { "$ref": "#/$defs/material" } }
          }
        }
      }
    },
    "handoff": {
      "type": "object", "additionalProperties": false, "required": ["type", "artifact_key", "summary"],
      "properties": { "type": { "const": "handoff" }, "artifact_key": { "type": "string", "maxLength": 128 }, "summary": { "type": "string", "maxLength": 4000 } }
    },
    "outputBlock": { "oneOf": [
      { "$ref": "#/$defs/text" }, { "$ref": "#/$defs/heading" }, { "$ref": "#/$defs/list" },
      { "$ref": "#/$defs/table" }, { "$ref": "#/$defs/status" }, { "$ref": "#/$defs/progress" },
      { "$ref": "#/$defs/chart" }, { "$ref": "#/$defs/diagram" }, { "$ref": "#/$defs/report" },
      { "$ref": "#/$defs/handoff" }
    ] },
    "reportBlock": { "oneOf": [
      { "$ref": "#/$defs/text" }, { "$ref": "#/$defs/heading" }, { "$ref": "#/$defs/list" },
      { "$ref": "#/$defs/table" }, { "$ref": "#/$defs/status" }
    ] },
    "planArtifact": {
      "type": "object", "additionalProperties": false,
      "required": ["key", "type", "format", "summary", "payload", "evidence"],
      "properties": {
        "key": { "type": "string", "maxLength": 128 }, "type": { "type": "string", "maxLength": 128 },
        "format": { "const": "json" }, "summary": { "type": "string", "maxLength": 4000 },
        "payload": { "type": "object" }, "evidence": { "type": "array", "maxItems": 8, "items": { "$ref": "#/$defs/material" } }
      }
    },
    "error": {
      "type": "object", "additionalProperties": false, "required": ["code", "message", "retryable"],
      "properties": { "code": { "enum": ["validation_error", "tool_error", "blocked", "other"] }, "message": { "type": "string", "minLength": 1, "maxLength": 4000 }, "retryable": { "type": "boolean" } }
    }
  }
}
```

Дополнительный валидатор проверяет: суммарный текст отчёта не превышает
64 000 символов; число ячеек каждой строки совпадает с `columns`; `current`
не больше `total`; `payload` соответствует JSON Schema конкретного
`output_artifact` узла; `handoff.artifact_key` существует на подтверждённом
ребре плана. Полный конверт измеряется в UTF-8 байтах.

### Единая форма отчёта

В `report.sections` всегда присутствуют пять ключей в одном смысле, независимо
от того, промежуточный отчёт или итоговый:

| Ключ | Форма | Что содержит |
|---|---|---|
| `result` | block[] | Вывод и текущая рекомендация. |
| `work` | block[] | Что сделано. |
| `checks` | check[] | Проверки и фактический результат каждой. |
| `limitations` | block[] | Ограничения и неизвестное. Пустой список — ограничения не указаны. |
| `materials` | material[] | Источники, документы, журналы и артефакты, на которые опирается отчёт. |

`check` требует `label` и `status`; допустимы `detail` и `evidence_refs`.
Статусы: `passed`, `failed`, `blocked`, `skipped`, `not_run`. Пустой список
проверок означает «проверки не запускались», а не успех. `material` требует
`kind`, `title`, `ref`; `kind` — `url`, `document`, `file`, `change`,
`artifact` или `log`. Внутри разделов отчёта разрешены только `text`, `heading`, `list`,
`table` и `status`: промежуточный/итоговый документ остаётся читаемым и
переводимым в текущий Markdown-формат. `progress`, `chart`, `diagram`,
вложенные `report` и `handoff` остаются отдельными блоками чата. Пустой раздел
передаётся как `[]`. При конвертации в обязательные непустые Markdown-разделы
сервер добавляет точную нейтральную фразу по смыслу: работы нет, проверки не
запускались, ограничения не указаны или материалы не приложены. Пустой список
проверок никогда не превращается в «всё прошло».

Роль может добавить в `output` обычные `text`-блоки до или после отчёта; их
не нужно дублировать внутри `result`. Клиент показывает разделы в фиксированном
порядке, а совместимый серверный адаптер формирует из них прежний
`report_markdown` для текущего API.

### Артефакты и приём результата

`artifacts` содержит ссылки на созданные владельцу материалы; каждый элемент
имеет `kind`, `title` и `ref`. Машинная сдача этапа находится отдельно в
`plan_artifact`: он содержит `key`, `type`, `format: "json"`, `summary`,
`payload` и `evidence: material[]`. `key`, `type`, `format` и обязательные
поля payload берутся из контракта этапа, их нельзя придумывать или
переименовывать. Payload сохраняет индивидуальную структуру существующего
артефакта роли. Сервер проверяет его до закрытия этапа. Фактический валидатор
проверяет наличие обязательных ключей и непустые значения, но типы значений
пока не проверяет. `evidence` ограничен восемью ссылками, путь — 1024
символами. JSON Schema v1 должна добавить проверку типов до действующего
валидатора. Отдельный вердикт ревью остаётся отдельным
структурированным полем API/команды сдачи; его нельзя выводить из текста
`report` или `ok`.

`handoff` в `output` только отображает факт передачи. Сервер подставляет
подтверждённую связь плана и artifact key. В обычном чате без узла плана такой
блок запрещён.

### Размер и длинные ответы

Предлагаемые эксплуатационные пределы v1, которые надо подтвердить
нагрузочным прогоном до включения:

- JSON-конверт — до 512 KiB UTF-8, до 200 блоков `output`;
- один текстовый блок — до 64 KiB UTF-8, список — до 200 пунктов;
- таблица — до 100 строк данных и 12 колонок;
- график — до 500 точек; схема — до 100 элементов.

Для совместимости общий текстовый объём `report` дополнительно ограничен
64 000 Unicode-символами: столько принимает текущий валидатор
`report_markdown`. Сервер сейчас допускает HTTP body до 25 MiB, а передача
артефакта принимает до 8 ссылок evidence с путём до 1024 символов. Это
фактические серверные лимиты, но они не являются целевыми лимитами JSON и не
доказывают, что iOS удобно отрисует тело такого размера. Предлагаемый лимит
512 KiB на envelope намеренно строже; он остаётся проектным значением до
измерения на клиенте и уточнения транспортного пути чата.

Эти пределы не меняют смысловую форму отчёта и оставляют место для результата
заметно больше демонстрационного. Если полный материал больше предела, роль
сдаёт краткое резюме и типизированный документ/evidence, а в `materials`
появляется ссылка на него; данные нельзя молча обрезать. В чате длинные
текстовые разделы прокручиваются вместе с лентой, широкие и длинные таблицы —
в собственном окне. Пределы должны проверяться сервером до сохранения, а
клиент должен показать явную ошибку при нарушении.

Текущий Swift-прототип повторно ищет незавершённый текст внутри растущего JSON,
поэтому он доказывает только отображение корректного префикса на малых
фикстурах. Для крупных потоков перед запуском нужен инкрементальный серверный
парсер/поток типизированных событий и один итоговый проверенный JSON; нельзя
оставлять на каждый тик полный повторный разбор 512 KiB.

### Поток данных и совместимость

```text
роль → один JSON-конверт → серверная проверка →
поток типизированных событий в чат → renderer iOS
                         └→ адаптер текущих API result/report_markdown
                         └→ проверка artifact.payload по узлу плана → следующий этап
```

Потоковые события — только проекция проверяемого конверта, а не второй
контракт. Финальный envelope остаётся единственным источником истины. Сервер
не закрывает этап и не передаёт артефакт дальше до проверки всего конверта.
Для старых ролей сохраняется текущий Markdown/YAML-путь через адаптер на время
перехода; новые роли переключаются по одной. Это сохраняет существующих
потребителей ценой временной поддержки двух входных форм.

### Ошибка и совместимость

- Старый Markdown/YAML-подобный вывод продолжает читаться действующим
  преобразователем до завершения постепенного перехода; JSON v1 получает
  отдельный `schema_version` и не угадывается по форме текста.
- При неизвестной версии, типе, поле или превышении лимита сервер отклоняет
  результат с `validation_error`, указывает JSON-путь ошибки и запускает не
  более одной попытки исправления с конкретной причиной. Невалидный JSON не
  передаётся следующей роли и не закрывает этап; полный ответ не дублируется в
  общедоступном логе, диагностический фрагмент ограничен и очищен от секретов.
- iOS для уже сохранённой валидной версии рисует компоненты; для неизвестной
  версии показывает понятную ошибку и доступный для копирования исходник.
  Старые сообщения автоматически не переписываются.

Не заводить второй конкурирующий конверт: отправная точка — уже существующий
общий набор полей роли. В v1 конверт становится настоящим JSON, получает
версию, а строка `output` заменяется списком типизированных блоков.
Текущие потребители ждут строку, поэтому этот переход потребует совместимого
преобразователя и не может быть сделан одной правкой промптов.

```json
{
  "schema_version": 1,
  "ok": true,
  "output": [
    { "type": "text", "text": "Сверил результаты. Проверка завершена." },
    {
      "type": "report",
      "report_kind": "intermediate",
      "sections": {
        "result": [{ "type": "text", "text": "Проверка завершена." }],
        "work": [{ "type": "list", "items": ["Сверены три источника."] }],
        "checks": [{ "label": "Сверка данных", "status": "passed" }],
        "limitations": [{ "type": "text", "text": "Один источник обновляется с задержкой." }],
        "materials": []
      }
    }
  ],
  "artifacts": [],
  "plan_artifact": null,
  "error": null,
  "next_hint": null,
  "needs_human": false
}
```

Форма принята как базовый контракт v1. Серверная ветка
`codex/structured-role-output-v1-20261017` в отдельной рабочей копии теперь
проверяет целевой `schema_version: 1`, отдаёт его в `role_envelope` и во время
live-потока извлекает текущий незакрытый `text`-блок. Старый `contract:
role.v1` со строковым `output` сохранён через совместимый путь. Проверка:
серверный тестовый файл — 34/34 PASS на Node 22; TypeScript-компиляция PASS.
Эта ветка не слита и не развёрнута; живые роли по-прежнему выдают старую
строковую форму, а iOS renderer уже читает оба формата. Полная совместимость
нового `output` со всеми внешними потребителями ещё не проверена. Плановый
`taskflow_subtask_done` остаётся отдельным вызовом инструмента; в нём должны
использоваться те же утверждённые типы `report` и `plan_artifact`, а сервер
должен собирать из них текущие поля `result`, `report_markdown` и `artifact`.
Поля `plan_artifact.payload` сверяются с контрактом узла плана; здесь намеренно
нет выдуманного примера payload. Сдача этапа и все промпты ролей ещё не
переведены на типизированные блоки.

### Ограниченный набор блоков чата

Закрытый список v1 — ровно типы из таблицы «Закрытый список
блоков»: `text`, `heading`, `list`, `table`, `status`, `progress`, `chart`,
`diagram`, `report`, `handoff`. Универсального `widget` с произвольным объектом
данных в v1 нет: его широкий динамический payload не даёт надёжно проверить
форму заранее. Существующие сохранённые блоки `tf-widget` останутся на старом
совместимом пути; включать отдельные widget-категории в новую схему можно
версиями контракта после описания точных полей нужного вида.

Текущий preview проверил текст, заголовок, статус, виджеты/график/цепочку,
отчёт, таблицу и передачу, но таблица не попала в кадр; её визуальная
приёмка ещё нужна. В целевом контракте текстовые поля — обычные строки,
а переносы, карточки, плотность и масштаб задаёт клиент. Серверный адаптер
может из единого JSON сформировать прежнюю Markdown-заметку и поля API.

### Артефакт и передача

Артефакт следующей роли остаётся типизированным по контракту конкретного узла:
фиксированы ключ, тип, формат и обязательные поля. В черновом целевом формате
роль сдаёт тот же `key`, короткое `summary`, `payload` и evidence в
`plan_artifact`. Поле `artifacts` сохраняет отдельное назначение: ссылки на
созданные для владельца документы, файлы и изменения. Роль не выбирает
следующего получателя: его определяют связи плана и серверный gate.
Пользовательская карточка передачи должна строиться по подтверждённой связи и
артефакту, а не доверять свободно придуманному полю `recipient`.

### Проверка и восстановление

- Разрешённые `type`, `status` и `report_kind` задаются версионированной
  схемой; дополнительные поля без объявления отклоняются.
- Артефакт проверяется относительно контракта узла до сдачи этапа.
- Неизвестная версия или тип дают явную ошибку с диагностическим исходником,
  а не пустое место в чате.
- В неполном JSON парсер потоково извлекает и показывает текущий `text`-блок;
  сырой JSON не показывается. Завершённый документ затем полностью
  проверяется, а уже видимый текст сохраняется при финализации.
- Старые сообщения и Markdown-заметки автоматически не переписываются.

## Карта реальных точек, которые надо связать

| Область | Текущая точка |
|---|---|
| Роли и инструкции | `server/src/roleRouting.ts`, динамическая таблица `roles`, запасные Markdown-файлы промптов |
| Контекст этапа | `server/src/runtime/roleContextResolver.ts`, `server/src/runtime/instructionDefaults.ts`; `task.plan` получает `artifactContract` |
| Отчёт | `server/src/lib/roleReportPolicy.ts`, `server/src/lib/roleResultReport.ts` |
| Сдача и gate | `server/src/routes/subtasks.ts`, `server/src/routes/subtask-artifacts.ts`, `server/src/runtime/collaborationPlanContext.ts` |
| Инструмент ролей | `server/scripts/mcp_server.py`: `taskflow_subtask_done` сейчас содержит отдельные `result`, `report_markdown`, `artifact` |
| Чат на iOS | `Sources/Features/Chat/ChatRichContent.swift`, `RoleReplyMarkdown.swift`, `ChatStructuredOutputView.swift` |

## Этапы внедрения и оставшиеся технические вопросы

1. iOS renderer v1 читает единый конверт и рисует разрешённые блоки; текущая
   проверка — compile-only и локальная DEBUG-фикстура.
2. Серверный валидатор и адаптер должны собирать из конверта действующие
   `result`, `report_markdown` и `artifact`. Пока сервер требует
   `report_markdown`; заменять его прямой передачей JSON нельзя.
3. Сверить изменяемый состав ролей и контракты узлов перед внедрением. Снимок
   таблицы `roles` включает 10 ролей; контракты стандартных T03/T05 и
   `card_result` перечислены выше, но произвольные узлы задают контракт прямо
   в плане. Роли не добавлять и последовательность работ не менять.
4. Согласовать и измерить лимиты транспорта и инкрементального разбора на
   реальном живом ходе; полный JSON-конверт остаётся источником истины.
5. После серверного адаптера постепенно переключать роли и узлы по одной
   группе, сохраняя старый путь чтения до проверки каждого потока.

## Проверенные источники

- iOS: локальный прототип и [отчёт просмотра](/Users/max/Проекты/TaskFlowNativeBuild/docs/2026-10-17-structured-role-output-preview.md).
- Серверная рабочая БД на `.110`, read-only запрос таблицы `roles` 17.10.2026;
  серверный `main`, чтение без изменений: `roleReportPolicy.ts`,
  `roleResultReport.ts`, `roleRouting.ts`, `roleContextResolver.ts`,
  `instructionDefaults.ts`, `collaborationPlanContext.ts`,
  `task-collaboration-plans.ts`, `subtask-artifacts.ts`, `index.ts`, маршруты
  сдачи и определения инструментов `mcp_server.py`.
- Проектные заметки: `docs/2026-10-08-human-role-reports.md` и
  `docs/2026-10-08-report-format.md`.
- База знаний: ранее найденное правило — развёрнутый документ и машинный
  артефакт являются отдельными понятными путями; передача должна проверяться
  до закрытия этапа.
