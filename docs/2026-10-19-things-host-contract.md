# Things tools contract in TaskFlow Host

## Что изменено

Host теперь читает `/Users/max/.hermes/scripts/things_tools_contract.json` при
каждом вызове `things3`. Этот JSON — единственный источник имён инструментов,
описаний и `inputSchema`; отдельного списка разрешённых имён в TypeScript больше
нет. Host проверяет структуру контракта, уникальность имён, обязательные поля,
типы, enum, вложенные свойства и массивы по схеме до запуска MCP.

MCP JSON-RPC `error` и результат `isError: true` теперь завершают операцию
ошибкой Host. Текст ошибки сохраняется. Такой ответ не превращается в
`{ ok: true }` и не выглядит как пустой список.

Изменены только эти файлы вне git-репозитория Host:

- `/Users/max/.local/share/taskflow-host/src/operations/things3.ts`
- `/Users/max/.local/share/taskflow-host/test/things3.test.ts`

Контракт JSON и скрипт Things MCP не менялись в этой части работы.

## Проверка

- RED до изменения Host: `things_list` отвергался ручным списком, проверки
  контракта и MCP `isError` отсутствовали; focused test завершился с 6 падениями.
- GREEN после правки: `npm test -- --run test/things3.test.ts` — 14/14.
- `npm run build` — успешно.
- Сборка обновила генерируемую папку `dist/`, которую запускает LaunchAgent.
  Работающий Host не перезапускался, поэтому его процесс пока использует
  загруженный до этой сборки код. Чтобы изменения вступили в силу, нужно
  перезапустить `com.taskflow.host`.
- Тесты используют заглушки; живые Things и работающий LaunchAgent не трогались.
- Host не перезапускался. После этого нужно проверить read-only вызов
  Things-инструмента через шлюз.

## Восстановление

Исходные файлы перед правкой сохранены в `docs/2026-10-19-things-host-contract/before/`.
Полный патч текущего изменения сохранён в
`docs/2026-10-19-things-host-contract/things-host.patch`.

Установленная копия Host не является git checkout, поэтому исходники,
резервные копии и patch сохранены отдельно в документации TaskFlow.
