# Интеграция: блок действий, аватарки в списке сессий, чипы ссылок (карточка 3e8b9b3b)

Дата: 11.11.2026. Репозиторий: `/Users/max/Проекты/TaskFlowNativeBuild`.

## Что влито

Ветка `roles/3e8b9b3b-541a-40a3-93f0-9544a10cf7ea` (`6808ae17`) слита в `main`
merge-коммитом `c42214ee`. Внутри три правки:

| Правка | Коммит | Файлы |
| --- | --- | --- |
| П2: аватарки только в общем списке чатов | `9e234971`, `dabb6f9f` | `Sources/Core/Models/RoleSessionList.swift`, `Sources/Features/Roles/RoleChatsScreen.swift`, `Tests/RoleSessionListTests.swift` |
| П1: раскрытый блок действий не сворачивается сам | `995ea96f` (первая версия), `966bef78` (доработка) | `Sources/Features/Roles/RoleFeedExpansion.swift`, `RoleLiveTurnView.swift`, `RoleActionGroup.swift`, `RoleChatRoomScreen.swift`, `RoleWorkSheet.swift`, `Tests/RoleFeedExpansionTests.swift`, `Tools/test_role_feed_expansion.py` |
| П3: чипы ссылок соразмерны тексту | `48cf5911` | `Sources/Chat/Feed/ChatInlineIcon.swift`, `Tests/ChatInlineIconTests.swift` |

Плюс склейка с `main` внутри ветки — `6808ae17` (main на тот момент `c82541fb`).

## Почему первая версия П1 не пошла

Проверяющий вернул П1: раскрытие переехало в хранилище экрана
(`RoleFeedExpansion`), но ни одна вью на него не подписывалась. Ячейка ленты
собирается один раз в `cellForRowAt` (`Sources/Chat/Feed/ChatFeedVirtualList.swift:297`),
поэтому тап по полосе «Действия» менял только таблицу ключей, а вид строки — нет.
Доработка `966bef78` вынесла содержимое списка в `RoleLiveItemsContent` с
`@ObservedObject store: RoleFeedExpansion`; `RoleLiveItemsList` осталась тонкой
обёрткой и подставляет своё хранилище для шторки «Работа» и предпросмотров.
Сторож на подписку добавлен в `Tools/test_role_feed_expansion.py`.

## Проверки (на слитом main, `c42214ee`)

| Команда | Результат |
| --- | --- |
| `python3 Tools/test_role_feed_expansion.py` | 5 тестов, 0 падений |
| `python3 Tools/test_role_session_list.py` | 18 тестов, 0 падений |
| `python3 Tools/test_chat_link_presentation.py` | 24 теста, 0 падений |
| `python3 Tools/test_chat_inline_icon.py` | 6 тестов, 0 падений |
| `python3 Tools/design-system-guard.py --diff HEAD^1` | сторож: чисто |
| `git merge-base --is-ancestor` для `9e234971`, `995ea96f`, `966bef78`, `48cf5911` | все коммиты предки `main` |

Сборка, симулятор, UI-тесты и установка на iPhone не запускались — вид
оценивает владелец.

## Доставка не выполнена

`git push origin main` (GitHub `papirosa3214/TaskFlowNativeBuild`) и `git push github main`
(локальное зеркало `/Users/max/ios-github-mirror.git`) из этого окружения не проходят:

- GitHub: `gh` не может прочитать свою конфигурацию (`/Users/max/.config/gh/config.yml: operation not permitted`),
  в результате `could not read Username for 'https://github.com'`;
- зеркало и Gitea: `/Users/max/.ssh` и `/Users/max/ios-github-mirror.git` недоступны
  (`Operation not permitted`), имя `gitea` не разрешается.

Нужно одно действие владельца: отправить `main` (`c42214ee`) в GitHub и в зеркало
штатной копией репозитория либо выдать роли доступ к ключу и токену.

## Что ещё сделано

Строка `LOCK-CHAT-ACTION-FOLD-20261111` в `AGENT-WORK-SCOPES/2026-11.md` переведена
в `REVIEW` доработкой; правка команды проверки (реальный скрипт —
`Tools/test_role_feed_expansion.py`) внесена тем же коммитом `966bef78`.
