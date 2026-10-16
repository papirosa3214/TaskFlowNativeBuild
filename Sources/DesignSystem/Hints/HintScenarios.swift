import Foundation

/// Реестр сценариев подсказок. Правило владельца (16.10.2026): новая функция —
/// новая подсказка. Добавить: повесить `.hintAnchor("…")` на элемент и описать
/// шаги здесь. Идентификаторы якорей — `HintAnchorID`.
enum HintAnchorID {
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
    static let all: [HintScenario] = [taskPlan, taskLinks, chatMembers]

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
                text: "Выбери в меню «Предложить план по шаблону» и подходящий шаблон: «Доставка», «Исследование» и другие. Шаги и роли появятся в карточке черновиком — сначала посмотри их, потом утверди.",
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
