import Foundation

/// Реестр сценариев подсказок. Правило владельца (16.10.2026): новая функция —
/// новая подсказка. Добавить: повесить `.hintAnchor("…")` на элемент и описать
/// шаги здесь. Идентификаторы якорей — `HintAnchorID`.
enum HintAnchorID {
    static let voiceModes = "voice.modes"
    static let inboxTickets = "inbox.tickets"
    static let projectsAllTasks = "projects.all-tasks"
    static let allTasksFilter = "all-tasks.filter"
    static let chatSession = "chat.session"
    static let routineInstructions = "routine.instructions"
    static let routinePlanTemplate = "routine.planTemplate"
    static let routineHistory = "routine.history"
    static let taskCoordination = "task.coordination"
    /// Строка «Mission Control» в разделе «Контракт миссии» координации.
    static let missionControl = "task.mission-control"
    /// Сам экран Mission Control.
    static let missionControlScreen = "task.mission-control.screen"
    static let chatItemBudget = "server.setting.chat_item_max_actions"
    static let chatOwnMessageCopy = "chat.own-message.copy"
    static let unifiedPlanner = "planner.all-tasks"
    static let taskNumberCopy = "task.number.copy"
    static let aiUsage = "ai.usage"
    static let roleLoadRows = "role-load.rows"
    static let roleBehavior = "role.behavior"
    static let agentInstructions = "team.agent-instructions"
    static let chatDiscussionDelivery = "chat.discussion-delivery"
    static let chatExecutionMode = "chat.execution-mode"
    static let noteMarkdownEditing = "note.markdown-editing"
    static let voiceScreenShare = "voice.screen-share"
    static let voiceMinimize = "voice.minimize"
    static let voiceMiniPlayer = "voice.mini-player"
    static let roleExternalApps = "role.external-apps"
    static let chatCoordination = "chat.coordination"
    static let systemSummary = "system.summary"
    static let contextObservability = "role-load.context"
    static let jevUsage = "jev.usage"
    static let jevConnection = "jev.connection"
    static let chatDictation = "chat.dictation"
    static let chatComposerActions = "chat.composer.actions"
    static let chatContextWindow = "chat.context-window"
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
    /// Форма уточнения у владельца под ответом роли (26.10.2026).
    static let chatQuestion = "chat.question"
    /// Вид панели ввода в настройках (29.10.2026).
    static let chatComposerStyle = "settings.chat-composer-style"
    /// Стартовый экран личного чата с ролью (29.10.2026).
    static let chatRoleStart = "chat.role-start"
}

enum HintScenarios {
    static let inboxTickets = HintScenario(
        id: "inbox-tickets", title: "Обращения агентов", start: "requests",
        steps: ["requests": HintStep(anchor: HintAnchorID.inboxTickets,
            title: "Что ждёт вашего решения",
            text: "Во входящих — вопросы, согласования планов и решения, которых ждут агенты. Откройте тикет: на вопрос можно ответить здесь, а план или причину ожидания — рассмотреть в задаче. Само открытие ничего не разрешает и не запускает. После ответа или решения обращение исчезает при обновлении.", next: nil)])

    static let chatComposerControls = HintScenario(
        id: "chat-composer-controls", title: "Панель чата", start: "actions",
        steps: [
            "actions": HintStep(anchor: HintAnchorID.chatComposerActions, title: "Действия в одном меню",
                text: "Здесь вложения и режимы: Работа, Планирование, Цель, а у помощницы и исследователя — Исследование. В личном чате помощница работает только в чате. Выбор модели находится рядом; модели разложены по провайдерам.", next: "context"),
            "context": HintStep(anchor: HintAnchorID.chatContextWindow, title: "Сколько осталось контекста",
                text: "Здесь размер последнего измеренного окна и лимит фактической модели, а не суммарный расход беседы. Откройте строку, чтобы увидеть свежесть замера, обновить его, сжать контекст или начать новую сессию. После сжатия до нового ответа замер может быть неизвестен. Процент — ориентир, не гарантия места для следующего запроса.", next: "commands"),
            "commands": HintStep(anchor: HintAnchorID.chatComposerActions, title: "Навыки и инструменты",
                text: "В личном чате наберите / или выберите «Навыки и инструменты» в меню. Список приходит от сервера для этого агента. Выбор вставит команду в поле; допишите поручение и отправьте сообщение. Сам выбор ничего не запускает.", next: nil)
        ])

    static let assistantSession = HintScenario(
        id: "assistant-session", title: "Сессия помощника", start: "session",
        steps: ["session": HintStep(anchor: HintAnchorID.chatSession,
            title: "Один разговор — одна сессия",
            text: "Нажмите «Сессия»: здесь модель и поддерживаемые уровни размышлений, рабочая папка, контекст и инструменты. Настройки сохраняются для этого разговора. «Новая сессия» создаёт отдельный чат; прежний остаётся в списке. Сжатие и сброс контекста сохраняют историю.")])

    /// Окно сессии в чате с ролью (29.10.2026): левая кнопка новой панели
    /// ввода открывает его, и то, что раньше было в меню действий, живёт
    /// здесь же.
    static let roleSession = HintScenario(
        id: "role-session", title: "Сессия роли", start: "session",
        steps: ["session": HintStep(anchor: HintAnchorID.chatSession,
            title: "Сессия роли",
            text: "Левая круглая кнопка в панели ввода открывает сессию: здесь модель с её описанием, уровни размышлений, рабочая папка, контекст, вложения и режим работы. Модель можно пометить звездочкой — избранные показываются первыми. Настройки сохраняются для этого разговора.", next: nil)])

    static let agentPromptSettings = HintScenario(
        id: "agent-prompt-settings", title: "Инструкции агентов", start: "common",
        steps: ["common": HintStep(anchor: HintAnchorID.agentInstructions,
            title: "Три отдельные настройки",
            text: "В «Команде» общие инструкции задают правила работы всех агентов. Откройте нужного агента: «Личность» меняет характер и манеру общения, «Личные инструкции» — его обязанности и правила работы. Изменения применяются со следующего обращения.", next: nil)])

    /// Вид панели ввода в чатах (29.10.2026): родная или новая.
    static let chatComposerStyle = HintScenario(
        id: "chat-composer-style", title: "Панель ввода", start: "style",
        steps: ["style": HintStep(anchor: HintAnchorID.chatComposerStyle,
            title: "Две панели ввода",
            text: "Выключен тумблер — родная панель: поле в капсуле, а под ним ряд действий. Включён — новая: всё в одну строку, поле и значки в одной капсуле, кнопка действий слева, отправка справа. Переключение мгновенное, перезапуск не нужен. Обе панели работают одинаково: диктовка, вложения, модель, папка и кольца контекста на месте.", next: nil)])

    /// Стартовый экран личного чата с ролью (29.10.2026).
    static let chatRoleStart = HintScenario(
        id: "chat-role-start", title: "Начало чата с ролью", start: "start",
        steps: ["start": HintStep(anchor: HintAnchorID.chatRoleStart,
            title: "С чего начать разговор",
            text: "Пока в чате нет сообщений, здесь приветствие роли и четыре быстрые команды — типичные для неё задачи. Нажмите команду: текст подставится в поле ввода, его можно дописать своим или отправить сразу. Команды подсказывают направление, а не ограничивают: обычное сообщение работает так же.", next: nil)])

    static let taskCoordination = HintScenario(
        id: "task-coordination", title: "Почему шаг ждёт", start: "step",
        steps: [
            "step": HintStep(anchor: HintAnchorID.taskCoordination, title: "Выберите шаг",
                text: "В меню задачи выберите «Координация». Нажмите нужный шаг: ниже появятся его состояние, причина ожидания и доступное действие. Перезапуск требует причины и подтверждения. Настройки моделей и остальные решения открываются в существующем управлении. Открытие панели само ничего не запускает.", next: "mission"),
            "mission": HintStep(anchor: HintAnchorID.missionControl, title: "Контракт миссии",
                text: "Ниже в этом же экране — раздел «Контракт миссии»: критерии, записанные до работы, и проверка по ним. Если шаг ждёт, посмотрите сначала здесь: непроверенный критерий не даёт закрыться задаче.", next: nil)
        ])

    /// Контракт миссии (02.11.2026): что считается готовым по критериям,
    /// записанным ДО работы. Новая функция — новая подсказка (правило
    /// владельца 16.10.2026).
    static let missionControl = HintScenario(
        id: "mission-control", title: "Контракт миссии", start: "coordination",
        steps: [
            "coordination": HintStep(anchor: HintAnchorID.taskCoordination, title: "Где искать контракт",
                text: "В меню задачи выберите «Координация». Внизу есть раздел «Контракт миссии» — критерии, записанные до работы: что именно считается готовым.", next: "mission"),
            "mission": HintStep(anchor: HintAnchorID.missionControl, title: "Откройте Mission Control",
                text: "Нажмите «Mission Control». Здесь видно, что считается готовым по контракту, какая проверка не прошла и кто её закрывал. Сам раздел ничего не меняет — это чтение.", next: "screen"),
            "screen": HintStep(anchor: HintAnchorID.missionControlScreen, title: "Что здесь видно",
                text: "Сверху — итог: сколько критериев пройдено, сколько провалено и сколько не проверяется вживую. Ниже — каждый критерий: номер, чем проверяется, какой шаг его закрыл. Отдельным списком — дыры в покрытии и журнал: кто что проверял и что открылось на доработку.", next: nil)
        ])

    static let all: [HintScenario] = [voiceModes,inboxTickets,allTasks,voiceScreenShare,assistantSession,routineEditing, chatDiscussionDelivery, chatComposerControls, agentPromptSettings, taskCoordination, missionControl, chatItemBudget, chatOwnMessageCopy, unifiedPlanner, taskNumberCopy, aiUsage, roleLoadRows, roleBehavior, chatExecutionMode, voiceConversation, externalApps, webhooks, taskPlan, taskLinks, chatMembers, chatWorkPlan, chatDeliveryBadge, roleActions, chatDictation, jev, systemSummary, chatCoordination, contextObservability, jevUsage, noteMarkdownEditing, chatQuestion, chatComposerStyle, chatRoleStart, roleSession]

    static let allTasks = HintScenario(
        id: "projects-all-tasks", title: "Все задачи и статусы", start: "entry",
        steps: [
            "entry": HintStep(anchor: HintAnchorID.projectsAllTasks, title: "Откройте все задачи",
                text: "Плитка «Все задачи» рядом с архивом открывает общий список, включая задачи без проекта.", next: "filter"),
            "filter": HintStep(anchor: HintAnchorID.allTasksFilter, title: "Выберите статус",
                text: "В меню выберите один статус: «В работе», «На проверке», «Заблокированы» или «Ожидающие запуска». Для обычного просмотра выберите «Не выполненные» или «Все, включая выполненные».", next: nil)
        ])

    static let routineEditing = HintScenario(
        id: "routine-editing", title: "Задание и настройки рутины", start: "instructions",
        steps: [
            "instructions": HintStep(anchor: HintAnchorID.routineInstructions, title: "Измените задание",
                text: "Нажмите рутину в «Моих рутинах», чтобы открыть её настройки. Здесь можно прочитать и изменить полное задание агенту, исполнителя и расписание. Нажмите «Сохранить изменения»: новые настройки будут использоваться в будущих запусках. Уже созданные задачи останутся прежними.", next: "planTemplate"),
            "planTemplate": HintStep(anchor: HintAnchorID.routinePlanTemplate, title: "Выберите исполнение",
                text: "Откройте «Исполнитель». Здесь те же шаблоны, что в карточке задачи, в том числе «Один исполнитель». Выбранный шаблон будет использоваться в будущих запусках без второго автоплана. «Автоматически» снимает выбор: план подбирается при создании задачи. Нажмите «Сохранить изменения».", next: "history"),
            "history": HintStep(anchor: HintAnchorID.routineHistory, title: "Посмотрите прошлые запуски",
                text: "Внизу настроек существующей рутины откройте «История запусков». Здесь видны созданные задачи, ошибки и пропуски. Нажмите созданную задачу, чтобы открыть её.", next: nil)
        ])

    /// Уточнение роли у владельца (26.10.2026): форма под ответом роли.
    static let chatQuestion = HintScenario(
        id: "chat-question", title: "Уточнение у владельца", start: "answer",
        steps: ["answer": HintStep(anchor: HintAnchorID.chatQuestion, title: "Ответьте на вопрос роли",
            text: "Когда роль не может решить сама, она задаёт вопрос с вариантами — под её ответом появляется форма. Нажмите подходящий вариант или напишите свой в поле «Свой вариант», затем «Отправить ответ». Роль продолжит работу с того места, где остановилась, и увидит ваш ответ в переписке. Можно добавить заметку для роли.", next: nil)])

    static let chatDiscussionDelivery = HintScenario(
        id: "chat-discussion-delivery", title: "Итог обсуждения", start: "status",
        steps: ["status": HintStep(anchor: HintAnchorID.chatDiscussionDelivery, title: "Статус обсуждения",
            text: "Здесь показан последний полученный статус обсуждения и доставки итога. «Ожидает доставки» означает, что итог сохранён; «Получен исполнителем» — что сервер подтвердил получение. Если получатель не найден, итог остаётся сохранённым.")])

    static let unifiedPlanner = HintScenario(
        id: "unified-planner", title: "Все задачи в одном списке", start: "list",
        steps: ["list": HintStep(anchor: HintAnchorID.unifiedPlanner, title: "Все задачи",
            text: "Входящие, Ждут вас, Просроченные, Сегодня и Предстоящие находятся в одной ленте. Заголовки закрепляются при прокрутке. Будущие появления рутин видны в Предстоящих; задачи без проекта распределяются по тем же правилам.")])

    static let chatOwnMessageCopy = HintScenario(
        id: "chat-own-message-copy", title: "Действия со своим сообщением", start: "copy",
        steps: ["copy": HintStep(anchor: HintAnchorID.chatOwnMessageCopy, title: "Долгое нажатие на сообщение",
            text: "Зажмите своё сообщение: в меню можно выделить или скопировать текст, сохранить его или поделиться. Пока роль не взяла сообщение в работу, доступно «Убрать сообщение»: оно исчезнет из ленты и очереди. Взятое в работу сообщение убрать нельзя.")])

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

    static let voiceModes = HintScenario(
        id: "voice-modes", title: "Проверка голосовых режимов", start: "mode",
        steps: ["mode": HintStep(anchor: HintAnchorID.voiceModes,
            title: "Режим следующего звонка",
            text: "Текущий режим — обычный голосовой разговор. Для сравнения выберите Pipecat с Gemini Live или исполнителем чата. Выбор применяется со следующего звонка. В режиме с исполнителем чата фраза распознаётся после паузы, ответ сохраняется в чате; показ экрана недоступен. Если эксперимент недоступен, выберите текущий режим.")])

    static let voiceScreenShare = HintScenario(
        id: "voice-screen-share", title: "Показать экран Помощнику", start: "start",
        steps: ["start": HintStep(anchor: HintAnchorID.voiceScreenShare,
            title: "Экран в том же разговоре",
            text: "Нажмите «Показать экран Помощнику», выберите TaskFlow и подтвердите «Начать трансляцию» в системном окне. Затем откройте другое приложение: голосовой разговор продолжится, а экран будет передаваться Помощнику из этого чата. Микрофон трансляции оставьте выключенным — разговор использует свой микрофон. Остановить показ можно здесь или через системный индикатор записи.")])

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
            text: "Нажатие на микрофон не вызывает клавиатуру: пока пусто, микрофон стоит на месте кнопки отправки. После остановки записи расшифровка добавляется в поле: её можно поправить руками или дополнить следующей диктовкой. Сообщение уходит только по кнопке отправки.", next: nil)])

    static let roleActions = HintScenario(
        id: "role-actions", title: "Действия и навыки роли", start: "actions",
        steps: ["actions": HintStep(anchor: HintAnchorID.roleActions, title: "Что делает роль",
            text: "В ходе работы различаются чтение, запись, правки, поиск, тесты и другие действия. После успешного чтения файла навыка появляется «Навык подключён» с его именем. Это подтверждает получение инструкции, а не выполнение всех её требований. Нажмите действие, чтобы открыть подробности.", next: nil)])

    static let chatItemBudget = HintScenario(
        id: "chat-item-budget", title: "Лимит действий чек-листа", start: "limit",
        steps: ["limit": HintStep(
            anchor: HintAnchorID.chatItemBudget, title: "Бюджет одного пункта",
            text: "Нажмите параметр, чтобы изменить число действий на один пункт чек-листа роли. Один вызов инструмента — одно действие; сдача пункта и сообщения о ходе работы не расходуют лимит. После принятой сервером сдачи следующий пункт получает новый бюджет. Настройка применяется без перезапуска сервера, уже выполненные действия не обнуляются.", next: nil)])

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
