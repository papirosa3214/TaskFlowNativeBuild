#!/usr/bin/env python3
"""Локальная база и фоновая синхронизация (LOCK-LOCAL-DB-SYNC-20261031).

Проверки статические: они ловят именно те ошибки, которые не поймает сборка,
— «забыли сохранить отпечаток в базу», «удалили историю», «взяли курсор
из памяти, а не из базы». Логика GRDB проверяется юнит-тестами
`Tests/LocalDbSyncTests.swift` (их гоняет владелец на маке).

Запуск: python3 Tools/test_local_db_sync.py
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f'  ✓ {message}')
    else:
        failures.append(message)
        print(f'  ✗ {message}')


def read(rel: str) -> str:
    path = root / rel
    if not path.exists():
        failures.append(f'нет файла: {rel}')
        return ''
    return path.read_text()


# ── 1. Файлы и зависимость ────────────────────────────────────────────────
print('Файлы и зависимость')

db_file = read('Sources/Core/Store/LocalDatabase.swift')
store_file = read('Sources/Core/Store/LocalStore.swift')
engine_file = read('Sources/Core/Store/SyncEngine.swift')
api_file = read('Sources/Core/Networking/APIClient+LocalSync.swift')
project_yml = read('project.yml')

check(bool(db_file), 'Sources/Core/Store/LocalDatabase.swift на месте')
check(bool(store_file), 'Sources/Core/Store/LocalStore.swift на месте')
check(bool(engine_file), 'Sources/Core/Store/SyncEngine.swift на месте')
check(bool(api_file), 'Sources/Core/Networking/APIClient+LocalSync.swift на месте')

check('GRDB:' in project_yml, 'GRDB объявлен в packages:')
check(
    'https://github.com/groue/GRDB.swift.git' in project_yml,
    'GRDB тянется с официального репозитория',
)
check(
    re.search(r'^\s*- package: GRDB\s*$', project_yml, re.M) is not None,
    'GRDB подключён к таргету TaskFlow',
)
check(
    re.search(r'from:\s*7\.\d+\.\d+', project_yml) is not None,
    'версия GRDB закреплена конкретной (не «latest»)',
)
check(
    'import GRDB' in db_file and 'import GRDB' in store_file,
    'GRDB импортируется там, где идёт работа с базой',
)

# ── 2. Схема ───────────────────────────────────────────────────────────────
print('Схема')

for table, columns in {
    'chat': ['id', 'title', 'kind', 'room_kind', 'updated_at',
             'last_message_json', 'unread_count', 'archived_at', 'payload_json'],
    'message': ['id', 'chat_id', 'sequence', 'created_at', 'payload_json'],
    'task': ['id', 'updated_at', 'payload_json'],
    'notification': ['id', 'created_at', 'payload_json'],
    'sync_state': ['state_key', 'value'],
}.items():
    match = re.search(rf'db\.create\(table: "{table}"\)(.*?)\n\s*\}}', db_file, re.S)
    body = match.group(1) if match else ''
    missing = [c for c in columns if f'"{c}"' not in body]
    check(not missing, f'таблица {table}: все столбцы на месте' + (f' (нет: {missing})' if missing else ''))

check(
    re.search(r'db\.create\(\s*index: "message_on_chat_sequence",\s*on: "message",\s*columns: \["chat_id", "sequence"\]', db_file) is not None,
    'индекс по (chat_id, sequence) есть — курсор догрузки не тормозит',
)
check(
    'state_key' in db_file and 'db.create(table: "sync_state")' in db_file,
    'столбец курсоров назван state_key (KEY — зарезервированное слово SQLite)',
)
check(
    '.primaryKey()' in db_file and 'payload_json' in db_file,
    'сырой ответ сервера хранится в payload_json',
)

# ── 3. Правила слияния: только upsert, ничего не удалять ──────────────────
print('Правила слияния')

upserts = re.findall(r'INSERT INTO (\w+)', store_file)
check(len(upserts) >= 4, f'запись идёт через upsert (найдено вставок: {len(upserts)})')
check(
    store_file.count('ON CONFLICT(id) DO UPDATE SET') >= 4,
    'каждая таблица обновляется по ключу id, а не заменяется целиком',
)
check(
    'INSERT OR REPLACE' not in store_file,
    'нет INSERT OR REPLACE: он сносит непрочитанные столбцы и ломает историю',
)

deletes = re.findall(r'DELETE FROM (\w+)', store_file)
# Полная чистка при выходе из аккаунта — законна. Вне неё удалять можно
# только то, о чём сервер сказал явно (удалённая задача) и один курсор.
clear_all_at = store_file.find('func clearAll()')
outside = store_file if clear_all_at < 0 else store_file[:clear_all_at]
deletes_outside = re.findall(r'DELETE FROM (\w+)', outside)
check(
    set(deletes_outside) <= {'task', 'sync_state'},
    f'вне чистки при выходе удаляется только то, о чём сервер сказал явно '
    f'(встречается: {sorted(set(deletes_outside))})',
)
check(
    'clearAll()' in store_file and set(deletes) >= {'chat', 'message', 'task'},
    'выход из аккаунта чистит все таблицы, а не половину',
)
check(
    'removeTasks' in store_file and 'removed_ids' in read('Sources/Core/Stores/TaskStore.swift'),
    'удаление задач идёт по removed_ids — только по прямому сигналу сервера',
)

# ── 4. Отпечаток и курсор живут в базе, а не в памяти ─────────────────────
print('Отпечаток и курсор')

task_store = read('Sources/Core/Stores/TaskStore.swift')
check(
    'LocalStore.shared.syncState(SyncStateKeys.tasksETag)' in task_store,
    'ETag списка задач берётся из базы, а не только из памяти',
)
check(
    'LocalStore.shared.setSyncState(SyncStateKeys.tasksETag' in task_store,
    'ETag списка задач сохраняется в базу — перезапуск его переживает',
)
check(
    'LocalStore.shared.setSyncState(SyncStateKeys.tasksCursor' in task_store,
    'курсор дельты сохраняется в базу',
)
check(
    'LocalStore.shared.syncState(SyncStateKeys.tasksCursor)' in task_store,
    'курсор дельты читается из базы — после перезапуска догрузка продолжается',
)

store = read('Sources/Core/Store/LocalStore.swift')
for key in ['tasksETag', 'tasksCursor', 'chatsETag', 'chatsPaging']:
    check(f'static let {key}' in store, f'ключ курсора {key} объявлен')

# ── 5. Экраны читают из базы ──────────────────────────────────────────────
print('Экраны читают из базы')

check(
    'LocalStore.shared.tasks()' in task_store,
    'список задач сначала берётся из базы (экран рисуется без сети)',
)
check(
    'LocalStore.shared.notifications()' in read('Sources/Core/Stores/NotificationStore.swift'),
    'лента уведомлений сначала берётся из базы',
)

from chat_screen_sources import read_chat_screen
screen = read_chat_screen(Path(__file__).resolve().parents[1])
check(
    'LocalStore.shared.chats(' in screen,
    'список чатов сначала берётся из базы',
)
check(
    'LocalStore.shared.messages(chatID:' in screen,
    'переписка комнаты сначала берётся из базы',
)
check(
    'after: cursor' in screen,
    'комната спрашивает только НОВОЕ сообщение (after=курсор), а не всю историю',
)
check(
    'limit: cursor.map { _ in 50 }' in screen,
    'порция догрузки — 50 сообщений',
)
check(
    'updatedMessages + messages' in screen,
    'при догрузке новая порция не выкидывает старую историю из ленты',
)

# ── 6. WS-событие попадает в базу ─────────────────────────────────────────
print('Реалтайм')

app = read('Sources/App/TaskFlowApp.swift')
check(
    'SyncEngine.shared.ingest(event)' in app,
    'событие сокета уходит в локальную базу',
)
check(
    'syncAll()' in app,
    'фоновая синхронизация запускается после первой отрисовки',
)
check(
    'guard store.syncState(SyncStateKeys.chatsPaging) == "1" else { return }' in engine_file,
    'событие сокета не тянет всю историю чата, пока сервер не подтвердил постраничную выдачу',
)
check(
    'SyncStateKeys.chatsPaging' in screen,
    'комната запоминает, что сервер умеет постраничную выдачу',
)

# ── 7. Выход из аккаунта чистит базу ───────────────────────────────────────
print('Выход из аккаунта')

session = read('Sources/Core/Session/SessionStore.swift')
check(
    'LocalStore.shared.clearAll()' in session,
    'выход из аккаунта чистит локальную базу — чужие данные не остаются на телефоне',
)
check(session.count('LocalStore.shared.clearAll()') >= 2,
      'база чистится и по кнопке «выйти», и по протухшему токену (401)')

# ── 8. Сеть: таймаут и повтор ─────────────────────────────────────────────
print('Сеть')

check(
    'localSyncTimeout: TimeInterval = 10' in api_file,
    'у запросов синхронизации таймаут 10 секунд',
)
check(
    api_file.count('timeout: Self.localSyncTimeout') >= 4,
    'таймаут стоит на КАЖДОМ запросе синхронизации (списки, сообщения, уведомления)',
)
check(
    'Task.sleep' in engine_file,
    'неудачный запрос повторяется с задержкой',
)

# ── Итог ───────────────────────────────────────────────────────────────────
print()
if failures:
    print(f'ПРОВАЛЕНО: {len(failures)}')
    for item in failures:
        print(f'  — {item}')
    sys.exit(1)
print('Локальная база и синхронизация: все проверки прошли')
