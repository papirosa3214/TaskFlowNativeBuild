import Foundation

/// Стартовый экран личного чата с ролью: приветствие и четыре быстрые
/// команды (владелец 29.10.2026 — макет `mockups/role-chat-start/`).
///
/// Тексты живут на устройстве, а не на сервере: сервер отдаёт реестр ролей и
/// их описания, но приветствия и подсказки — часть интерфейса. Когда понадобится
/// правка без выпуска приложения, каталог переедет в ответ сервера, а
/// `RoleChatStarter.starter(for:)` останется тем же входом.
///
/// Логика чистая и без SwiftUI — поэтому проверяется на хосте, без симулятора.
public struct RoleChatStarterCommand: Equatable, Sendable, Identifiable {
    /// Что написано на кнопке.
    public let title: String
    /// Подсказка под названием: что будет дальше.
    public let hint: String
    /// Текст, который подставляется в поле ввода.
    public let prompt: String
    /// Значок SF Symbols.
    public let icon: String

    public var id: String { title }

    public init(title: String, hint: String, prompt: String, icon: String) {
        self.title = title
        self.hint = hint
        self.prompt = prompt
        self.icon = icon
    }
}

/// Приветствие роли и её быстрые команды.
public struct RoleChatStarter: Equatable, Sendable {
    /// Ключ роли из реестра сервера (`researcher`, `secretary`, …).
    public let roleKey: String
    /// Приветствие от лица роли.
    public let greeting: String
    /// Ровно четыре команды — по решению владельца 29.10.2026.
    public let commands: [RoleChatStarterCommand]

    public init(roleKey: String, greeting: String, commands: [RoleChatStarterCommand]) {
        self.roleKey = roleKey
        self.greeting = greeting
        self.commands = commands
    }
}

/// Каталог стартовых экранов по ключам ролей.
public enum RoleChatStarters {
    /// Сколько команд показываем: по решению владельца 29.10.2026 — четыре.
    public static let commandCount = 4

    private static func command(_ title: String, _ hint: String, _ prompt: String, _ icon: String) -> RoleChatStarterCommand {
        RoleChatStarterCommand(title: title, hint: hint, prompt: prompt, icon: icon)
    }

    /// Каталог по ключам ролей живого реестра (11 включённых ролей).
    public static let all: [String: RoleChatStarter] = [
        "researcher": RoleChatStarter(
            roleKey: "researcher",
            greeting: "Скажите тему — найду источники, сравню варианты и соберу выводы.",
            commands: [
                command("Сравни варианты решения", "и скажи, какой лучше", "Сравни варианты решения и скажи, какой лучше", "arrow.left.arrow.right"),
                command("Найди документацию", "по API, со ссылками", "Найди свежую документацию по API и приведи ссылки", "magnifyingglass"),
                command("Разберись в нашем коде", "как это устроено", "Разберись, как это устроено у нас в коде", "doc.text"),
                command("Собери выводы", "короткий документ", "Собери найденное в короткий документ", "list.bullet.rectangle")
            ]),
        "analyst": RoleChatStarter(
            roleKey: "analyst",
            greeting: "Назову цифры и покажу, откуда они. Чего не хватит — скажу сразу.",
            commands: [
                command("Посчитай метрики", "время по задачам за неделю", "Посчитай, сколько времени уходит на задачи за неделю", "chart.bar"),
                command("Сколько стоит сервер", "расходы по месяцу", "Посчитай, сколько стоит месяц работы сервера", "banknote"),
                command("Где больше всего тратится", "времени и денег", "Покажи, где тратится больше всего времени и денег", "chart.pie"),
                command("Сравни периоды", "эта неделя и прошлая", "Сравни эту неделю с прошлой: что изменилось в цифрах", "arrow.left.arrow.right")
            ]),
        "critic_verifier": RoleChatStarter(
            roleKey: "critic_verifier",
            greeting: "Дайте результат — проверю по критериям и вынесу вердикт: готово к приёмке или нет.",
            commands: [
                command("Проверь задачу", "выполнена ли полностью", "Проверь, выполнена ли задача полностью", "checkmark.shield"),
                command("Найди слабые места", "в этом решении", "Найди слабые места в этом решении", "exclamationmark.triangle"),
                command("Дай вердикт", "принимать или дорабатывать", "Дай вердикт: принимать или дорабатывать", "checkmark.seal"),
                command("Проверь соседнее", "ничего не сломано рядом", "Проверь, что ничего не сломано рядом", "arrow.triangle.branch")
            ]),
        "architect": RoleChatStarter(
            roleKey: "architect",
            greeting: "Разберу варианты и предложу решение: интерфейсы, данные, риски, откат.",
            commands: [
                command("Предложи архитектуру", "для новой функции", "Предложи архитектуру для новой функции", "square.3.layers.3d"),
                command("Как разбить на модули", "границы и зависимости", "Как лучше разбить это на модули, где границы", "square.grid.2x2"),
                command("Что сломается", "при таком изменении", "Что сломается при таком изменении", "exclamationmark.triangle"),
                command("Сравни два подхода", "и выбери один", "Сравни два технических подхода и выбери один", "arrow.left.arrow.right")
            ]),
        "builder": RoleChatStarter(
            roleKey: "builder",
            greeting: "Опишите задачу — сделаю код и проверю результат.",
            commands: [
                command("Исправь баг", "описание — что сломалось", "Исправь баг: ", "wrench.and.screwdriver"),
                command("Добавь эндпоинт", "новый маршрут на сервере", "Добавь новый эндпоинт на сервере", "server.rack"),
                command("Почини тесты", "красные — разберись почему", "Разберись, почему падают тесты, и почини", "bolt.fill"),
                command("Найди причину падения", "по логам и коду", "Найди причину падения по логам и коду", "magnifyingglass")
            ]),
        "qa": RoleChatStarter(
            roleKey: "qa",
            greeting: "Пройду сценарий в живом приложении и принесу баги со скриншотами и шагами.",
            commands: [
                command("Пройди сценарий", "создать и закрыть задачу", "Пройди сценарий: создай задачу и закрой её", "iphone"),
                command("Найди, где ломается", "в интерфейсе", "Найди, где ломается интерфейс", "exclamationmark.triangle"),
                command("Проверь чат с ролями", "открытие и ответ", "Проверь чат с ролями: открытие и ответ", "checkmark.circle"),
                command("Составь план проверки", "по новой фиче", "Составь план проверки по новой фиче", "checklist")
            ]),
        "designer": RoleChatStarter(
            roleKey: "designer",
            greeting: "Сделаю макет экрана и спецификацию поведения — по дизайн-системе проекта.",
            commands: [
                command("Нарисуй макет", "экрана или сцена", "Нарисуй макет экрана: ", "paintbrush"),
                command("Проверь пустое состояние", "и ошибки", "Проверь пустое состояние и состояние ошибки", "rectangle.dashed"),
                command("Придумай тексты", "для этого экрана", "Придумай тексты для этого экрана", "text.quote"),
                command("Оцени доступность", "интерфейса", "Оцени доступность этого интерфейса", "accessibility")
            ]),
        "secretary": RoleChatStarter(
            roleKey: "secretary",
            greeting: "Я рядом. Расскажите, что случилось, — разберу, заведу задачи и соберу сводку.",
            commands: [
                command("Разбери надиктовку", "в задачи", "Разбери надиктовку в задачи", "waveform"),
                command("Собери сводку за день", "что горит и что нет", "Собери сводку за день: что горит и что нет", "list.bullet.rectangle"),
                command("Напомни мне про…", "поставить напоминание", "Напомни мне про: ", "bell"),
                command("Поставь задачу в работу", "и назначь роли", "Поставь задачу в работу и назначь роли", "paperplane")
            ]),
        "code_orchestrator": RoleChatStarter(
            roleKey: "code_orchestrator",
            greeting: "Разложу задачу на этапы, назначу роли и соберу итог в один ответ.",
            commands: [
                command("Разложи на этапы", "и назначь роли", "Разложи задачу на этапы и назначь роли", "point.3.connected.trianglepath.dotted"),
                command("Кто свободен", "сейчас", "Кто из ролей сейчас свободен?", "person.2"),
                command("Собери итог по задаче", "по всем ветвям", "Собери итог по задаче: ", "tray.full"),
                command("Что застряло", "и где затык", "Что застряло и где затык?", "clock.arrow.circlepath")
            ]),
        "infra_engineer": RoleChatStarter(
            roleKey: "infra_engineer",
            greeting: "Скажите, что отвалилось на .110, — проверю сервисы и починю.",
            commands: [
                command("Что сломано на .110", "сервисы и интеграции", "Что сейчас не работает на .110: сервисы и интеграции", "server.rack"),
                command("Проверь нагрузку и место", "диски и процессы", "Проверь нагрузку на сервере и свободное место на дисках", "gauge.with.dots.needle.50percent"),
                command("Подними упавший сервис", "и проверь, что жив", "Подними упавший сервис и проверь, что он жив", "bolt.fill"),
                command("Разбери интеграцию", "которая падает", "Разберись с интеграцией, которая падает", "arrow.triangle.branch")
            ]),
        "claude_code": RoleChatStarter(
            roleKey: "claude_code",
            greeting: "Разбираю код в своём окружении: память, MCP и скиллы доступны.",
            commands: [
                command("Разбери модуль", "как он работает", "Разберись, как работает модуль: ", "cpu"),
                command("Найди реализацию", "фичи в коде", "Найди, где реализована фича: ", "magnifyingglass"),
                command("Исправь и открой PR", "с коммитом", "Исправь, закоммить и открой PR", "arrow.triangle.pull"),
                command("Изучи логи", "и объясни причину", "Изучи логи и объясни причину", "doc.text.magnifyingglass")
            ])
    ]

    /// Запасной стартовый экран для роли, которой нет в каталоге: текст и
    /// команды общие, без придуманного имени роли.
    public static let fallback = RoleChatStarter(
        roleKey: "",
        greeting: "Расскажите, что нужно сделать, — разберусь и предложу, с чего начать.",
        commands: [
            command("Опиши задачу", "что нужно сделать", "Опишите задачу: ", "square.and.pencil"),
            command("Составь план", "шаги и сроки", "Составь план работы по моей задаче", "list.number"),
            command("Что уже сделано", "похожее в истории", "Что по этой теме уже сделано?", "clock.arrow.circlepath"),
            command("Спроси у другой роли", "кто разбирается лучше", "Кто из ролей разбирается в этом лучше меня?", "person.2")
        ])

    /// Стартовый экран роли. Неизвестная роль — запасной, без имени роли.
    public static func starter(for roleKey: String?) -> RoleChatStarter {
        guard let roleKey, !roleKey.isEmpty else { return fallback }
        return all[roleKey] ?? fallback
    }
}
