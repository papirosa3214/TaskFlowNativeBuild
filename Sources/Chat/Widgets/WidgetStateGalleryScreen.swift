import SwiftUI

// Галерея нужна только в Debug (вызывается из TaskFlowApp под #if DEBUG) и
// берёт отладочные наборы вроде allCasesForPreview — в Release её нет.
#if DEBUG

/// ВРЕМЕННЫЙ экран для съёмки кадров состояний (пусто, загрузка) и проверки
/// шести действующих типов. Открывается переменной окружения
/// `TASKFLOW_WIDGET_GALLERY_PREVIEW`, в Debug, и удаляется после съёмки:
/// в рабочем коде клиента такого экрана быть не должно.
struct WidgetStateGalleryScreen: View {
    let kind: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                header
                ForEach(blocks, id: \.self) { json in
                    ChatWidgetView(json: json)
                }
                if kind == "loading" {
                    pending
                }
                if kind == "workplan" {
                    workPlanSamples
                }
            }
            .padding(TFSpacing.lg)
        }
        .tfScreenBackground()
        .preferredColorScheme(
            ProcessInfo.processInfo.environment["TASKFLOW_WIDGET_GALLERY_APPEARANCE"] == "light" ? .light : .dark
        )
    }

    /// Кадры серверных состояний чатового чек-листа и доставки сообщения
    /// (карточка b504958a): остановленный план, заблокированный пункт с
    /// причиной, сданный пункт с итогом и четыре состояния доставки.
    private var workPlanSamples: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            ChatWorkPlanRows(plans: workPlanPreviews, members: workPlanMembers, initiallyExpanded: true)
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text("Доставка сообщения роли").font(.caption).foregroundStyle(Color.tfDim)
                ForEach(ChatMessageDeliveryState.allCasesForPreview, id: \.self) { state in
                    ChatDeliveryBadge(state: state)
                }
            }
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text("Доставка своего сообщения").font(.caption).foregroundStyle(Color.tfDim)
                ForEach(ChatMessageDeliveryState.allCasesForPreview, id: \.self) { state in
                    TFCard(padding: 0, surface: .card, radius: nil) {
                        VStack(alignment: .leading, spacing: TFSpacing.xs) {
                            Text("Сделай вот это")
                                .font(.body)
                                .foregroundStyle(Color.tfText)
                            ChatDeliveryBadge(state: state)
                        }
                        .padding(TFSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text("Прерванный ответ роли").font(.caption).foregroundStyle(Color.tfDim)
                ChatInterruptionBadge(interruption: .ownerInterrupt, isPartial: true)
                ChatInterruptionBadge(interruption: .failed, isPartial: false)
            }
        }
    }

    private var workPlanMembers: [RoleChatMember] {
        [
            RoleChatMember(id: "role_builder", name: "Разработчик", avatarColor: nil,
                           avatarURL: nil, initials: "Р", roleKey: "builder"),
            RoleChatMember(id: "role_qa", name: "Критик-проверяющий", avatarColor: nil,
                           avatarURL: nil, initials: "К", roleKey: "qa"),
        ]
    }

    private var workPlanPreviews: [ChatWorkPlan] {
        [
            ChatWorkPlan(chatID: "preview", roleID: "role_builder", revision: 6,
                         items: [
                            .init(id: "read", title: "Прочитать контракт", state: .done,
                                  result: "Контракт зафиксирован, поля для клиента названы."),
                            .init(id: "impl", title: "Показать серверные состояния", state: .blocked,
                                  blockReason: "Нужен ответ владельца о цвете остановки"),
                            .init(id: "qa", title: "Проверить на симуляторе", state: .pending),
                         ],
                         updatedAt: "2026-10-25T05:00:00Z", currentItemID: "impl"),
            ChatWorkPlan(chatID: "preview", roleID: "role_qa", revision: 2,
                         items: [
                            .init(id: "check", title: "Проверить сдачу пункта", state: .stopped),
                            .init(id: "report", title: "Собрать пакет проверки", state: .pending),
                         ],
                         updatedAt: "2026-10-25T05:00:00Z", status: .stopped,
                         stopReason: .ownerStop, stoppedAt: "2026-10-25T05:00:00Z"),
        ]
    }

    private var header: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(Color.tfDim)
    }

    private var label: String {
        switch kind {
        case "legacy1": return "Действующие типы 1–3: погода, метрики, прогресс"
        case "legacy2": return "Действующие типы 4–6: чек-лист, карточка, график"
        case "empty1": return "Пусто 1: доска статусов, список, цепочка, лестница"
        case "empty2": return "Пусто 2: таймлайн, календарь, карта, сравнение"
        case "loading": return "Идущий ответ роли: блок ещё дописывается"
        default: return kind
        }
    }

    /// Настоящий путь отрисовки: незакрытый огороженный блок даёт сегмент
    /// `.pending(.widget)` — ровно то, что видит владелец, пока секретарь пишет.
    private var pending: some View {
        RoleReplyMarkdown(text: "Собрал сводку по неделе.\n\n```widget\n{\"type\": \"heatmap\", \"title\": \"Активность\", \"weeks\": 12, \"cells\": [")
    }

    private var blocks: [String] {
        switch kind {
        case "legacy1":
            return [weather, metrics, progress]
        case "legacy2":
            return [checklist, card, chart]
        case "empty1":
            return [emptyStatusBoard, emptyBarsList, emptyChain, emptyLadder]
        case "empty2":
            return [emptyTimeline, emptyCalendar, emptyHeatmap, emptyCompare]
        case "loading":
            return [emptyStatusBoard]
        default:
            return []
        }
    }

    // Действующие шесть типов — блоки из старого формата, без новых полей.

    private let weather = """
    {"type":"weather","location":"Москва","temperature":18,"high":21,"low":12,\
    "condition":"Переменная облачность","icon":"partly","humidity":64,"wind":"3 м/с",\
    "feels_like":17,"is_day":true,"forecast":[\
    {"day":"пн","high":20,"low":11,"icon":"rain"},{"day":"вт","high":18,"low":10,"icon":"cloudy"},\
    {"day":"ср","high":23,"low":13,"icon":"clear"},{"day":"чт","high":22,"low":14,"icon":"partly"},\
    {"day":"пт","high":19,"low":12,"icon":"rain"}]}
    """

    private let metrics = """
    {"type":"metrics","title":"За неделю","items":[\
    {"label":"Задач закрыто","value":34,"delta":"+6","trend":"up"},\
    {"label":"В работе","value":12},\
    {"label":"Просрочено","value":3,"delta":"-2","trend":"down"},\
    {"label":"Ответов ролей","value":128,"delta":"+14","trend":"up"}]}
    """

    private let progress = """
    {"type":"progress","title":"Релиз","items":[\
    {"label":"Сборка","value":100},\
    {"label":"Тесты","value":62,"note":"7 из 11 прогонов"},\
    {"label":"Ревью","value":20}]}
    """

    private let checklist = """
    {"type":"checklist","title":"Перед выкладкой","items":[\
    {"text":"Отключить фиче-флаг новых типов","done":true},\
    {"text":"Собрать приложение на телефоне","done":false},\
    {"text":"Посмотреть тёмную тему","done":false}]}
    """

    private let card = """
    {"type":"card","title":"Секретарь готов","subtitle":"Новые типы виджетов",\
    "body":"Блок пришёл от роли и нарисован клиентом, а не показан как текст.",\
    "rows":[{"label":"Типов в реестре","value":"14"},{"label":"Сборок","value":"3"}],\
    "link":{"title":"Открыть карточку","url":"https://192.168.1.110:5180/tasks/3e27dafe-ae7f-4449-8978-ba68d40f6aea"}}
    """

    private let chart = """
    {"type":"chart","title":"Ответов по дням","kind":"bar","unit":"шт","points":[\
    {"x":"пн","y":18},{"x":"вт","y":24},{"x":"ср","y":15},{"x":"чт","y":31},\
    {"x":"пт","y":22},{"x":"сб","y":9},{"x":"вс","y":12}]}
    """

    // Пустые состояния восьми новых типов: поля по контракту, данных нет.

    private let emptyStatusBoard = """
    {"type":"status_board","title":"Задачи по статусам","groups":[]}
    """

    private let emptyBarsList = """
    {"type":"bars_list","title":"Готовность по разделам","items":[]}
    """

    private let emptyChain = """
    {"type":"chain","title":"Путь согласования","links":[]}
    """

    private let emptyLadder = """
    {"type":"ladder","title":"Этапы релиза","steps":[]}
    """

    private let emptyTimeline = """
    {"type":"timeline","title":"Сроки по задачам","items":[],"past":[]}
    """

    private let emptyCalendar = """
    {"type":"calendar_grid","month":"2026-10","first_weekday":1,"today":"2026-10-15","cells":[]}
    """

    private let emptyHeatmap = """
    {"type":"heatmap","title":"Активность","weeks":12,"max":20,"unit":"задач","cells":[]}
    """

    /// Половина данных: стороны есть, значений нет — самый частый битый блок.
    private let emptyCompare = """
    {"type":"compare","title":"Цены","subject":"Тариф на месяц","unit":"₽",\
    "left":{"label":"Текущий"},"right":{"label":"Новый"}}
    """
}
#endif
