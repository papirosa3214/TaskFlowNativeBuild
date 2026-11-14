# Режим ролей: прежний дом вкладки «Чат» возвращён (14.11.2026)

Работа: `LOCK-CHATS-ROLES-MODE-RESTORE-20261114`. Только iOS, один экран
`Sources/Features/Roles/RoleChatsScreen.swift` и возвращённый экран создания
чата. Поток новых сессий (`Sources/Features/Sessions/`, `ownerSessionsHome`)
не менялся; сервер не менялся.

Поручение владельца (14.11.2026): «вернуть всю прежнюю логику режима ролей, а
не только лички других ролей. Помощник в этом режиме — обычная роль со своей
личной комнатой; личные комнаты остальных ролей и групповые чаты должны снова
присутствовать и работать как раньше… Новые сессии остаются отдельным режимом
без изменений.»

## Когда и где пропало

`c12907ff` — «feat(chats): плоский чат с Помощником, папки-проекты и одна
форма сессий» (12.11.2026). В том же коммите из `RoleChatsScreen.swift`
удалены:

- состояния `showingCreate`, `openProjects`, `avatarRoleID`, `avatarEpoch`;
- свойство `groupSections` (`RoleSessionList.groups(candidates, scope: .groups)`);
- прежний дом: «Закреплённые» → «Помощник владельца» → «Роли» → «Внешние
  агенты» → «Групповые чаты» (каталог папками проектов), а вместо него в корень
  встал `assistantChatsHome` — плоский список сессий Помощника;
- `homeRoleRow`, `avatarPhotoButton`, `avatarEdit`, `groupsCatalog`,
  `folderRow`, `struct AvatarRoleBox`;
- шторки `CreateRoleChatScreen` и `AvatarCropEditor` (файл
  `RoleChatCreateScreen.swift` уехал в `archive/chats-groups-2026-11-12/`);
- ветка `.groups` в `chatScroll`, `case .groups: showingCreate = true` в
  `startNewSession`, заголовок «Групповые чаты»;
- Помощник вычеркнут из ряда ролей (`$0.id != Self.assistantID`).

## Данные скрыты, а не удалены

- Экран как читал, так и читает те же ответы сервера: снимок комнат
  (`rooms?.roles`, `dms`, `personalChatID`, `lastMessage`) и список `chats`.
  Запросов на удаление/очистку в `c12907ff` нет, `purgeRoleChat` как был, так и
  остался ручным действием владельца.
- Косвенно: комнаты были доступны по прямому маршруту `AppRoute.chatRole(id:)`
  ещё до этой правки — то есть данные приходили, просто из дома убрали входы.
- На сервере в те же дни (`~/Проекты/New-Todoist`, 12.11.2026) коммиты
  `442217a7` (новые сессии Помощника), `e0993216` (реестр ролей),
  `cec22fe2`, `63dd6a59`, `fab5ca3c` — ни один не удаляет чаты и участников.
  Соответственно, серверная правка не нужна и не делалась.

## Что возвращено

`Sources/Features/Roles/RoleChatsScreen.swift` (+225/−35):

- `chatsHome`: `if ownerSessionsBeta { ownerSessionsHome } else { rolesHome }`;
- `rolesHome` — прежний дом целиком: «Закреплённые», «Помощник владельца»
  (`Self.assistantID = "u-secretary"`), «Роли», «Внешние агенты»,
  «Групповые чаты» + `groupsCatalog`;
- `homeRoleRow(_:photoOnAvatar:)`, `avatarPhotoButton`, `avatarEdit`,
  `AvatarRoleBox`, `groupsCatalog`, `folderRow`, `groupSections`;
- шторки создания чата и правки фото;
- `chatScroll` — ветка каталога при `selectedScope == .groups`;
- `startNewSession` — `.groups` снова открывает «Новый чат»;
- `headerTitle` — «Групповые чаты» в режиме ролей;
- `stories` — Помощник снова первый кружок в режиме ролей;
- `rowMember` — кружки в корне режима ролей.

`Sources/Features/Roles/RoleChatCreateScreen.swift` восстановлен из
`git show c12907ff^:…` без правок; `xcodegen generate` выполнен (файл попадает
в цель через `- path: Sources`).

### Как ограждён режим новых сессий

Всё новое поведение стоит под `ownerSessionsBeta`:

- `chatsHome` при бете отдаёт `ownerSessionsHome` — как было;
- круг «аватарки» в корне: `guard (isHome && !ownerSessionsBeta) || …`
  — в бете корень по-прежнему без кружков;
- полоска проектов `ChatsFolderBar` — `… isHome, ownerSessionsBeta, !projects.isEmpty …`;
- свайп между проектами — `guard ownerSessionsBeta`;
- каталог `.groups` в бете недостижим: `selectedScope` из дома беты всегда
  `.role(u-secretary)`.

Подсказка `chatsProjectFolders` не восстанавливалась: сценарий снят 12.11.2026,
а `HintAnchorID.externalAgentAvatar` с тех пор про портрет в профиле роли —
чужая подсказка на кружке врала бы. Новую подсказку не выдумывал.

## Проверки (точечные)

1. `xcrun swiftc -parse Sources/Features/Roles/RoleChatsScreen.swift
   Sources/Features/Roles/RoleChatCreateScreen.swift` → чисто.
2. Статическая сверка символов, на которые опирается возвращённый код:
   `RoleMemberAvatar` (`RoleChatListRow.swift:110`), `TFListRow`
   (`TFCard.swift:286+`), `RoleAvatarAsset.role(forUserID:)` /
   `imageName(for:)` / `isExternalChatRole` (`RoleAvatarAsset.swift:141,154,167`),
   `RoleRoom.member` (`ChatRooms.swift:61`), `canJoinChat`
   (`RoleProfile.swift:143`), `tfSheet(item:onDismiss:content:)`
   (`TFSheet.swift:25`).
3. `python3 Tools/design-system-guard.py --diff HEAD` → «чисто»;
   сверка диффа с `c12907ff^` (снимок `git show c12907ff^:…`).

Сборка Xcode, симулятор, UI-тесты и установка не запускались: на момент работы
шёл чужой `xcodebuild test-without-building` (UI-раннер), действует правило
«одна сборка за раз», и такие проверки запрещены без отдельного поручения.
Значит компиляцией возвращённый код ещё не подтверждён — это ограничение
работы, а не проверенный факт.

## Осталось

- приёмка владельца по внешнему виду дома режима ролей;
- компиляционная сборка (инкрементальная) — когда не идёт чужой прогон.
