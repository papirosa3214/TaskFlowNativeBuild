import Foundation

/// Реестр сценариев подсказок. Правило владельца (16.10.2026): новая функция —
/// новая подсказка. Добавить: повесить `.hintAnchor("…")` на элемент и описать
/// шаги здесь. Идентификаторы якорей — `HintAnchorID`.
enum HintAnchorID {
    static let chatCoordination = "chat.coordination"
    static let systemSummary = "system.summary"
    static let jevConnection = "jev.connection"
    static let chatDictation = "chat.dictation"
    static let roleActions = "role.live-actions"
    static let chatMembersMenu = "chat.members-menu"
    /// Кнопка «Работа» (два человечка) в шапке карточки задачи.
    static let taskWorkMenu = "task.work-menu"
    /// Заголовок секции «Шаги» карточки.
    static let taskSubtasks = "task.section.subtasks"
    /// Заголовок секции «План совместной работы».
    static let taskPlan = "task.section.collaborationPlan"
    /// Выбор «своя подзадача / по плану» у шага черновика.
    static let planWorkChoice = "plan.work-choice"
}

enum HintScenarios {
    static let all: [HintScenario] = [taskPlan, taskLinks, chatMembers, roleActions, chatDictation, jev, systemSummary, chatCoordination]

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
