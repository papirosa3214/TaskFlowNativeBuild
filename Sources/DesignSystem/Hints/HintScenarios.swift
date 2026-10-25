import Foundation

/// Реестр сценариев подсказок. Правило владельца (16.10.2026): новая функция —
/// новая подсказка. Добавить: повесить `.hintAnchor("…")` на элемент и описать
/// шаги здесь. Идентификаторы якорей — `HintAnchorID`.
enum HintAnchorID {
    static let chatOwnMessageCopy = "chat.own-message.copy"
    static let unifiedPlanner = "planner.all-tasks"
    static let taskNumberCopy = "task.number.copy"
    static let aiUsage = "ai.usage"
    static let roleLoadRows = "role-load.rows"
    static let roleBehavior = "role.behavior"
    static let chatExecutionMode = "chat.execution-mode"
    static let noteMarkdownEditing = "note.markdown-editing"
    static let voiceMinimize = "voice.minimize"
    static let voiceMiniPlayer = "voice.mini-player"
    static let roleExternalApps = "role.external-apps"
    static let chatCoordination = "chat.coordination"
    static let systemSummary = "system.summary"
    static let contextObservability = "role-load.context"
    static let jevUsage = "jev.usage"
    static let jevConnection = "jev.connection"
    static let chatDictation = "chat.dictation"
    static let roleActions = "role.live-actions"
    static let chatMembersMenu = "chat.members-menu"
    /// Полоса чек-листа роли над полем ввода: серверные состояния пункта.
    static let chatWorkPlan = "chat.work-plan"
    /// Признак доставки под своим сообщением в чате с ролями.
    static let chatDeliveryBadge = "chat.delivery-badge"
    /// Кнопка «Работа» (два человечка) в шапке карточки задачи.
    static let taskWorkMenu = "task.work-menu"
    /// Заголовок секции «Шаги» карточки.
    static let taskSubtasks = "task.section.subtasks"
    /// Заголовок секции «План совместной работы».
    static let taskPlan = "task.section.collaborationPlan"
    /// Выбор «своя подзадача / по плану» у шага черновика.
    static let planWorkChoice = "plan.work-choice"
    static let webhooksEntry = "integrations.webhooks"
    static let webhooksAdd = "webhooks.add"
    static let webhookURL = "webhooks.url"
    static let webhookEvents = "webhooks.events"
    static let webhookProject = "webhooks.project"
    static let webhookCodexThread = "webhooks.thread"
    static let webhookSave = "webhooks.save"
    static let webhookTest = "webhooks.test"
}

enum HintScenarios {
    static let all: [HintScenario] = [chatOwnMessageCopy, unifiedPlanner, taskNumberCopy, aiUsage, roleLoadRows, roleBehavior, chatExecutionMode, voiceConversation, externalApps, webhooks, taskPlan, taskLinks, chatMembers, chatWorkPlan, chatDeliveryBadge, roleActions, chatDictation, jev, systemSummary, chatCoordination, contextObservability, jevUsage, noteMarkdownEditing]

    static let unifiedPlanner = HintScenario(
        id: "unified-planner", title: "Все задачи в одном списке", start: "list",
        steps: ["list": HintStep(anchor: HintAnchorID.unifiedPlanner, title: "Все задачи",
            text: "Входящие, Ждут вас, Просроченные, Сегодня и Предстоящие находятся в одной ленте. Заголовки закрепляются при прокрутке. Будущие появления рутин видны в Предстоящих; задачи без проекта распределяются по тем же правилам.")])

    static let chatOwnMessageCopy = HintScenario(
        id: "chat-own-message-copy", title: "Копировать своё сообщение", start: "copy",
        steps: ["copy": HintStep(anchor: HintAnchorID.chatOwnMessageCopy, title: "Скопировать сообщение",
            text: "Нажмите значок копирования под своим сообщением: весь текст попадёт в буфер обмена. Появится подтверждение «Скопировано». Текст сообщения также можно выделить.")])

    static let taskNumberCopy = HintScenario(
        id: "task-number-copy", title: "Скопировать номер задачи", start: "copy",
        steps: ["copy": HintStep(anchor: HintAnchorID.taskNumberCopy, title: "Отправьте номер задачи",
            text: "Нажмите иконку рядом с номером: в буфер обмена скопируется только номер задачи. Его можно вставить в сообщение.")])

    static let roleLoadRows = HintScenario(
        id: "role-load-rows", title: "Свернуть ненужные роли", start: "collapse",
        steps: ["collapse": HintStep(anchor: HintAnchorID.roleLoadRows, title: "Оставьте нужные графики",
            text: "Нажмите имя роли слева, чтобы скрыть её график. Останется короткая строка с именем и стрелкой. Нажмите её или стрелку слева, чтобы развернуть роль. Можно свернуть несколько ролей независимо друг от друга.", next: nil)])

    static let roleBehavior = HintScenario(
        id: "role-behavior", title: "Личность и шаблоны роли", start: "templates",
        steps: ["templates": HintStep(anchor: HintAnchorID.roleBehavior, title: "Настройте характер роли",
            text: "Шаблон открывается в редакторе. Можно изменить описание личности и выбрать мужской или женский пол — так роль будет говорить о себе. «Сохранить шаблон» добавляет свой вариант в библиотеку; «Применить личность» отдельно сохраняет действующее поведение для следующего запуска. Общие и персональные инструкции доступны в контексте роли.", next: nil)])

    static let chatExecutionMode = HintScenario(
        id: "chat-execution-mode", title: "Как выполнять работу", start: "choose",
        steps: ["choose": HintStep(anchor: HintAnchorID.chatExecutionMode, title: "В чате или по карточке",
            text: "Откройте меню «Работа» у поля ввода. После разделителя выберите «В чате», чтобы роль выполнила поручение здесь без создания карточки, или «По карточке» — для работы через задачу с этапами и приёмкой. Выбор сохраняется для разговора и голосовых сообщений. Уже отправленное поручение продолжает работу в своём режиме.", next: nil)])

    static let noteMarkdownEditing = HintScenario(
        id: "note-markdown-editing", title: "Чтение и правка заметки", start: "edit",
        steps: ["edit": HintStep(anchor: HintAnchorID.noteMarkdownEditing, title: "Карандаш открывает Markdown",
            text: "Заметка открывается для чтения, как ответ в чате. Нажмите карандаш рядом с меню «…», чтобы править исходный Markdown. Изменения сохраняются автоматически; галочка завершает правку и возвращает просмотр. При ошибке сохранения редактор остаётся открытым.", next: nil)])

    static let voiceConversation = HintScenario(
        id: "voice-conversation", title: "Голос и переписка", start: "minimize",
        steps: [
            "minimize": HintStep(anchor: HintAnchorID.voiceMinimize, title: "Разговор остаётся с вами",
                text: "Сверните голосовой экран: микрофон останется включённым, а вы сможете читать переписку и пользоваться приложением. Реплики и сводки сохраняются в том чате, из которого начат разговор.",
                next: "mini", advancesOnTap: true),
            "mini": HintStep(anchor: HintAnchorID.voiceMiniPlayer, title: "Вернуться к разговору",
                text: "Нажмите на шарик, чтобы раскрыть голосовой экран. Удерживайте его, чтобы открыть переписку или завершить разговор.")
        ])

    static let externalApps = HintScenario(
        id: "external-apps", title: "Внешние приложения Помощника владельца", start: "access",
        steps: [
            "access": HintStep(anchor: HintAnchorID.roleExternalApps, title: "Подключения и возможности",
                text: "Здесь показаны Gmail с подключёнными адресами и доступ Помощника владельца к Things 3. Эти же сведения используются в Настройках → Интеграции. Нажми «Показать возможности», чтобы прочитать доступные действия из каталога инструментов. Статус Things «Доступен» означает, что проверка чтения через Mac прошла успешно.",
                documentationResource: "2026-10-18-role-external-apps")
        ])

    static let webhooks = HintScenario(
        id: "webhooks", title: "Вебхуки: отправка событий TaskFlow", start: "entry",
        steps: [
            "entry": HintStep(anchor: HintAnchorID.webhooksEntry, title: "Что такое вебхук",
                text: "Вебхук отправляет выбранные события TaskFlow по HTTP(S) на совместимый внешний сервис-приёмник. Например, так другой сервис может получить результат этапа. Это исходящая отправка: сам TaskFlow не создаёт адрес приёмника. Codex для этого не требуется. Нажми строку, чтобы открыть список и настройки.", next: "add", advancesOnTap: true,
                documentationResource: "2026-10-18-webhooks-integration"),
            "add": HintStep(anchor: HintAnchorID.webhooksAdd, title: "Добавь приёмник",
                text: "Нажми «+», чтобы создать подписку. Если подписка уже есть, можно нажать на её карточку, чтобы изменить настройки.", next: "url", advancesOnTap: true),
            "url": HintStep(anchor: HintAnchorID.webhookURL, title: "Адрес и ключ",
                text: "Введи название и HTTP(S)-адрес сервиса, который принимает запросы. Общий ключ укажи только если принимающая сторона ожидает его. Без доступного приёмника доставка не сработает.", next: "events"),
            "events": HintStep(anchor: HintAnchorID.webhookEvents, title: "Выбери события",
                text: "Отметь типы событий TaskFlow, которые нужно отправлять. Каждый выбранный тип создаёт отдельный запрос при наступлении соответствующего события.", next: "project"),
            "project": HintStep(anchor: HintAnchorID.webhookProject, title: "Ограничь проект",
                text: "Можно оставить один проект или выбрать «Все проекты», чтобы получать события из любого проекта. По умолчанию форма подставляет TaskFlow - NewTodoist.", next: "codex-choice"),
            "codex-choice": HintStep(anchor: HintAnchorID.webhookCodexThread, title: "Нужна передача в Codex?",
                text: "HTTP-вебхук работает с совместимым внешним приёмником; Codex не обязателен. Важно: форма заранее заполняет ID чата. Если нужна только HTTP-доставка, сначала вручную очисти поле ID, затем выбери «Только HTTP-приёмник». Выбор шага сам поле не меняет. Если нужна и передача в Codex, проверь ID нужной ветки.",
                branches: [
                    HintBranch(title: "Только HTTP-приёмник", next: "save"),
                    HintBranch(title: "Ещё передавать в Codex", next: "codex"),
                ]),
            "codex": HintStep(anchor: HintAnchorID.webhookCodexThread, title: "Проверь чат Codex",
                text: "Оставь ID только если хочешь дополнительно передавать события в эту ветку Codex. HTTP-доставка внешнему приёмнику всё равно остаётся основной подпиской.", next: "save"),
            "save": HintStep(anchor: HintAnchorID.webhookSave, title: "Сохрани подписку",
                text: "Подписка сохраняется на сервере TaskFlow. Кнопка станет доступна, когда введено название, корректный HTTP(S)-адрес и выбрано хотя бы одно событие. Нажми «Сохранить», чтобы перейти к проверке.", next: "test", advancesOnTap: true),
            "test": HintStep(anchor: HintAnchorID.webhookTest, title: "Проверь доставку",
                text: "Нажми «Проверить доставку». На карточке смотри HTTP-ответ и ошибку отдельно от постановки события в очередь и подтверждения запуска Codex: успешная HTTP-отправка сама по себе не подтверждает запуск чата.", next: nil),
        ])

    static let chatCoordination = HintScenario(
        id: "chat-coordination", title: "Обращения к коллегам", start: "coordination",
        steps: ["coordination": HintStep(anchor: HintAnchorID.chatCoordination, title: "Кого подключила роль",
            text: "В исходном чате видно, кому роль задала вопрос, ожидает ли он обработки и что происходит с ответом. Раскройте строку, чтобы прочитать вопрос и полученный ответ. Пока обращение не завершено, можно попросить его остановить. Вопрос, уже переданный в рабочую сессию, отдельно от работы остановить нельзя — приложение сообщит об этом.", next: nil)])

    static let systemSummary = HintScenario(
            id: "system-summary", title: "Состояние системы", start: "summary",
            steps: ["summary": HintStep(anchor: HintAnchorID.systemSummary, title: "Общая сводка",
                text: "Здесь сразу раскрыты поломки, тревоги, починенные механизмы и то, что работает штатно. Нажмите строку проблемы, чтобы открыть связанную задачу. Список рабочих карточек находится в меню «…» → «Карточки работ».", next: "reading"),
                    "reading": HintStep(anchor: HintAnchorID.systemSummary, title: "Как читать сводку",
                text: "Строки разложены по факту, а не по тексту сторожевого скрипта. «Поломки» — подтверждённый отказ, «Тревоги» — проверка прошла формально, но текст говорит об отказе, «Починено» — восстановилось само, «Работает в штатном режиме» — всё штатно. Если строка помечена «подробности не пришли», сторож не прислал продолжения. Нажатие на строку с поломкой открывает связанную рабочую карточку.", next: nil)])

    static let contextObservability = HintScenario(
        id: "context-observability", title: "Контекст и JEV в загрузке ролей", start: "context",
        steps: ["context": HintStep(anchor: HintAnchorID.contextObservability, title: "Вклад в работу роли",
            text: "Сводка показывает срабатывания за период графика. Раскройте последние срабатывания: там видны источники, отбор JEV, время, причины пропуска и ошибки. Количества показывают вход и выход конкретной операции; это не оценка качества итоговой работы.")])

    static let aiUsage = HintScenario(
        id: "ai-usage", title: "Статистика", start: "usage",
        steps: ["usage": HintStep(anchor: HintAnchorID.aiUsage, title: "Токены, кэш и стоимость",
            text: "Раздел «Статистика» в обзоре. Выберите сегодня, 7 или 30 дней. Здесь расход ответов моделей ролям TaskFlow, включая сохранённые сессии. Стоимость — тарифная оценка, а не списание с подписки. История выполненных задач с графиком — в архиве.")])

    static let jevUsage = HintScenario(
        id: "jev-usage", title: "Расход JEV", start: "usage",
        steps: ["usage": HintStep(anchor: HintAnchorID.jevUsage, title: "Расход текущего ключа",
            text: "Выберите сутки, неделю или месяц. Здесь учитываются только запросы TaskFlow с сохранённым ключом и адресом API с момента начала учёта. Если провайдер не вернул токены, запрос помечен отдельно; стоимость и баланс без данных провайдера не рассчитываются.")])

    static let jev = HintScenario(
        id: "jev", title: "Оценщик JEV", start: "connection",
        steps: ["connection": HintStep(anchor: HintAnchorID.jevConnection, title: "Подключение JEV",
            text: "Сохраните адрес API, модель и ключ, затем нажмите «Проверить подключение». Ниже выберите, где использовать оценщик. Настройки общие с вебом; если JEV выключен, не отвечает или не уверен, работа продолжается как без него.", next: nil)])

    static let chatDictation = HintScenario(
        id: "chat-dictation", title: "Диктовка в черновик", start: "dictation",
        steps: ["dictation": HintStep(anchor: HintAnchorID.chatDictation, title: "Диктуйте и редактируйте",
            text: "Микрофон доступен и после набора текста или выбора адресата через @. После остановки записи расшифровка добавляется в поле: её можно поправить руками или дополнить следующей диктовкой. Сообщение уходит только по кнопке отправки.", next: nil)])

    static let roleActions = HintScenario(
        id: "role-actions", title: "Действия и навыки роли", start: "actions",
        steps: ["actions": HintStep(anchor: HintAnchorID.roleActions, title: "Что делает роль",
            text: "В ходе работы различаются чтение, запись, правки, поиск, тесты и другие действия. После успешного чтения файла навыка появляется «Навык подключён» с его именем. Это подтверждает получение инструкции, а не выполнение всех её требований. Нажмите действие, чтобы открыть подробности.", next: nil)])

    static let chatWorkPlan = HintScenario(
        id: "chat-work-plan",
        title: "Чек-лист роли в чате",
        start: "plan",
        steps: [
            "plan": HintStep(
                anchor: HintAnchorID.chatWorkPlan,
                title: "Сервер ведёт пункты, а не модель",
                text: "Нажмите строку — раскроется весь план. Синий значок — пункт идёт сейчас, зелёный — сдан и рядом виден принятый итог, оранжевый с восклицательным знаком — пункт заблокирован и ждёт ответа или доступа, серый квадрат остановки — план остановлен, остальные пункты больше не начнутся. Следующий пункт начинается только после того, как роль сдала текущий: перепрыгнуть пункт нельзя.",
                next: nil),
        ])

    static let chatDeliveryBadge = HintScenario(
        id: "chat-delivery-badge",
        title: "Дошло ли сообщение до роли",
        start: "delivery",
        steps: [
            "delivery": HintStep(
                anchor: HintAnchorID.chatDeliveryBadge,
                title: "Сохранено — ещё не передано",
                text: "Под своим сообщением в чате с ролями виден признак доставки. «Сохранено» — сообщение лежит в ленте, «В очереди» — ждёт своей передачи, «Передано исполнителю» — роль взяла его в работу, «Не передано» — прежний ход отменён. Проверь актуальный план и уточнения перед повтором поручения.",
                next: nil),
        ])

    static let chatMembers = HintScenario(
        id: "chat-members",
        title: "Участники и адресация чата",
        start: "members",
        steps: [
            "members": HintStep(
                anchor: HintAnchorID.chatMembersMenu,
                title: "Соберите собеседников",
                text: "В меню выберите «Добавить участника». Помощника владельца можно пригласить вместе с другими ролями. С одним собеседником чат личный: пишите без @. С несколькими — групповой: выберите адресата через @. После удаления остальных участников личный режим вернётся.",
                next: nil),
        ])

    static let taskLinks = HintScenario(
        id: "task-links",
        title: "Связанные задачи",
        start: "links",
        steps: [
            "links": HintStep(
                anchor: "task.section.linkedTasks",
                title: "Связать карточки",
                text: "Раскрой раздел. Можно создать новую дочернюю задачу или привязать существующую как дочернюю. Если родителя ещё нет, здесь же можно выбрать родительскую задачу. В короткой карточке кнопки по краям ряда ярлыков скрывают клавиатуру и включают диктовку.",
                next: nil),
        ])

    static let taskPlan = HintScenario(
        id: "task-plan",
        title: "Карточка и план совместной работы",
        start: "work-menu",
        steps: [
            "work-menu": HintStep(
                anchor: HintAnchorID.taskWorkMenu,
                title: "План совместной работы",
                text: "Здесь решается, какие роли и в каком порядке делают задачу. Нажми на кнопку — откроется меню работы.",
                next: "plan-source",
                advancesOnTap: true),
            "plan-source": HintStep(
                anchor: HintAnchorID.taskWorkMenu,
                title: "Откуда взять план",
                text: "В меню два пути. «Предложить план из подзадач» — роли встанут на уже написанные подзадачи, ничего не пропадёт. «Предложить план по шаблону» — роли и шаги подберутся по смыслу карточки. Какие у тебя подзадачи?",
                branches: [
                    HintBranch(title: "Подзадачи уже написаны", next: "from-subtasks"),
                    HintBranch(title: "Подзадач нет", next: "from-template"),
                ]),
            "from-subtasks": HintStep(
                anchor: HintAnchorID.taskWorkMenu,
                title: "Собрать план из подзадач",
                text: "Выбери в меню «Предложить план из подзадач» (а если уже висит черновик по шаблону — «Собрать план из подзадач»). Каждая подзадача станет шагом своей роли. Если увидишь «Утвердить план подготовки — N подзадач без исполнителей», значит план собран по шаблону и эти подзадачи останутся пустыми.",
                next: "work-choice"),
            "from-template": HintStep(
                anchor: HintAnchorID.taskWorkMenu,
                title: "План по шаблону",
                text: "Выбери в меню «Предложить план по шаблону» подходящий вариант: например, «Баг или регрессия», «UX-концепция», «API-интеграция» или «Аудит». Шаблон задаёт роли, задания и навыки этапов. Сначала посмотри черновик, затем утверди запуск. Аудит сам не начинает исправления.",
                next: "steps"),
            "work-choice": HintStep(
                anchor: HintAnchorID.planWorkChoice,
                title: "Своя подзадача или работа плана",
                text: "Если подготовка переформулировала шаг, выбери: свой текст — роль сделает ровно то, что написал ты; «По плану» — по тексту подготовки. Пока выбор не сделан у всех таких шагов, утвердить план нельзя.",
                next: "approve"),
            "approve": HintStep(
                anchor: HintAnchorID.taskWorkMenu,
                title: "Утвердить и запустить",
                text: "Когда шаги устраивают — в этом же меню «Утвердить план совместной работы». Роли встанут на шаги и начнут по порядку.",
                next: "steps"),
            "steps": HintStep(
                anchor: HintAnchorID.taskSubtasks,
                title: "Роли на шагах",
                text: "У каждого шага — своя роль и состояние: ждёт, в работе, готово. Если шаг долго не двигается — напиши оркестратору в чат карточки: он видит, что с шагом, и умеет его перезапустить.",
                next: nil),
        ])
}
