import XCTest
import SnapshotTesting
import SwiftUI
@testable import TaskFlow

/// Кадры одного и того же ответа роли в пяти местах приложения —
/// карточка 19f57bc9, критерий приёмки 2 («один и тот же ответ с таблицей и
/// графиком в чате, ленте роли, комментарии, результате шага и итоге задачи —
/// выглядит одинаково»).
///
/// Почему снимки, а не UI-тест: владелец 20.10.2026 в 02:21 остановил прогоны
/// UI-теста по этой карточке, а кадр из прогона получался не тот — тест
/// открывал соседнюю карточку или обрывал ленту раньше таблицы и графика.
/// Снимок компонента рисуется целиком, без навигации по живым данным, и стоит
/// одного прогона.
///
/// Что в кадре настоящее:
/// - чат — сам `ChatBubble` с ответом роля;
/// - комментарий карточки — сам `TaskDescriptionRichPreview` (он и рисует
///   тело комментария) с шапкой «кто написал · когда», как в ленте;
/// - итог задачи — сама шторка `OutcomeTextSheet` (единственная правка в
///   продуктовом коде: убрано слово `private`, чтобы её можно было снять);
/// - переписка и результат шага — тело, которое рисует сам экран
///   (`RoleReplyMarkdown`), в обрамлении тех же строк («Вопрос»/«Ответ»,
///   «Результат» + кнопка копирования). Прямой снимок `List` внутри
///   `NavigationStack` пустой — это известное свойство офлайн-рендера,
///   поэтому для этих двух мест снято содержимое секции, а не окно.
final class RoleReplyPlacesSnapshotTests: XCTestCase {

    /// Эталоны записаны (20.10.2026) и лежат в `__Snapshots__/`; дальше тест
    /// сверяет с ними вид. Перезаписать: `record = true` на один прогон.
    private var record: Bool { false }

    // MARK: - Один и тот же ответ роли

    private let deviceConfig: ViewImageConfig = .iPhone13Pro

    /// Текстовый вид ответа: его сервер кладёт в результат шага, в итог задачи
    /// и в переписку ролей.
    private static let textReply = """
    Проверочный образец ответа роли (карточка 19f57bc9): график рисуется одним \
    компонентом во всех экранах.

    ## Что изменилось

    - Блок графика конверта и блок графика виджета зовут один RoleChartBlock
    - Точки читаются и как label/value, и как x/y
    - Один цвет на все графики ответа роли вместо teal и красного

    | Проверка | Результат |
    | --- | --- |
    | RoleReplyChartTests | 6/6 |
    | RoleReplyRenderTests | 4/4 |
    | RoleReplyPreviewTests | 6/6 |

    ```widget
    {"type": "chart", "title": "Рисунков графика ответа роли", "kind": "bar", "unit": "шт", \
    "points": [{"label": "Было", "value": 2}, {"label": "Стало", "value": 1}]}
    ```
    """

    /// Тот же ответ в конверте блоков — его сервер разбирает для чата и
    /// комментария (`ChatStructuredOutputView`).
    private static let envelopeReply = """
    ```tf-json
    {"schema_version":1,"ok":true,"output":[{"type":"text","text":"Проверочный образец ответа роли (карточка 19f57bc9): график рисуется одним компонентом во всех экранах."},{"type":"heading","text":"Что изменилось","level":2},{"type":"list","items":["Блок графика конверта и блок графика виджета зовут один RoleChartBlock","Точки читаются и как label/value, и как x/y","Один цвет на все графики ответа роли вместо teal и красного"]},{"type":"table","title":"Проверки","columns":["Проверка","Результат"],"rows":[["RoleReplyChartTests","6/6"],["RoleReplyRenderTests","4/4"],["RoleReplyPreviewTests","6/6"]]},{"type":"chart","title":"Рисунков графика ответа роли","kind":"bar","unit":"шт","points":[{"label":"Было","value":2},{"label":"Стало","value":1}]}],"artifacts":[],"plan_artifact":null,"error":null,"next_hint":"Пять кадров — в отчёте этапа.","needs_human":false}
    ```
    """

    private func chatMessage(_ text: String) -> ApiChatMessage {
        ApiChatMessage(id: "m-role-reply", channel: .agents, fromUserId: "role_architect",
                       toUserId: nil, taskId: "19f57bc9", kind: nil, text: text,
                       createdAt: "2026-10-20 05:10:00", fromUserName: "Архитектор",
                       fromUserColor: nil, fromUserAvatarUrl: nil, fromUserInitials: "А",
                       toUserName: nil, toUserColor: nil, taskTitle: nil, attachments: nil)
    }

    /// Подпись места над кадром: владелец должен видеть, где снято.
    private func place<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Text(title)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.md)
        .background(Color.tfBackground)
    }

    /// Кадр по размеру экрана телефона (iPhone 13 Pro, 390×844): так видно,
    /// сколько ответа помещается на экране.
    private func snap(_ name: String, @ViewBuilder content: () -> some View) {
        assertSnapshot(of: content(), as: .image(layout: .device(config: deviceConfig)),
                       named: name, record: record)
    }

    /// Кадр по всей высоте содержимого: в кадре по размеру устройства длинный
    /// ответ обрезался бы, и графика внизу не было бы видно.
    private func snapFits(_ name: String, @ViewBuilder content: () -> some View) {
        assertSnapshot(of: content(), as: .image(layout: .sizeThatFits), named: name, record: record)
    }

    // MARK: - Пять мест

    /// 1. Чат — пузырь ответа роли.
    func test01ChatMessage() {
        snap("01-Чат — пузырь ответа роли") {
            place("1. Чат — ответ роли в ленте") {
                ChatBubble(message: chatMessage(Self.textReply), mine: false, toMe: false)
            }
        }
    }

    /// 2. Комментарий карточки — конверт блоков, как его разбирает сервер.
    func test02TaskComment() {
        snap("02-Комментарий карточки") {
            place("2. Комментарий карточки — ответ роли") {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Архитектор").tfText(.body).fontWeight(.medium)
                        Spacer()
                        Text("5 мин").tfText(.meta).foregroundStyle(Color.tfSub)
                    }
                    TaskDescriptionRichPreview(text: Self.envelopeReply)
                }
            }
        }
    }

    /// 3. Переписка ролей — тело `RoleCoordinationCard` (свёрнутая группа на
    ///    экране раскрывается тапом, состояние снимку не подставить).
    func test03RoleCorrespondence() {
        snap("03-Переписка ролей") {
            place("3. Переписка ролей — вопрос и ответ") {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    Text("Вопрос").tfText(.meta)
                    RoleReplyMarkdown(text: "Сможешь одним и тем же ответом показать таблицу и график во всех пяти местах?")
                    Text("Ответ").tfText(.meta)
                    RoleReplyMarkdown(text: Self.textReply)
                }
            }
        }
    }

    /// 4. Результат шага — секция «Результат» шторки шага плана.
    func test04StepResult() {
        snap("04-Результат шага") {
            place("4. Результат шага плана") {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    HStack {
                        Text("Результат").tfText(.meta).foregroundStyle(Color.tfSub)
                        Spacer()
                        Image(systemName: "doc.on.doc")
                    }
                    RoleReplyMarkdown(text: Self.textReply)
                }
            }
        }
    }

    /// 5. Итог задачи — сама шторка с полным текстом итога роли.
    func test05TaskOutcomeSheet() {
        snapFits("05-Итог задачи") {
            place("5. Итог задачи — шторка «Итог роли»") {
                // Шторка длиннее экрана, а её `ScrollView` по размеру устройства
                // отдаёт только видимый кусок — график внизу обрезался бы.
                // Фиксированная высота делает снимок всей шторки целиком.
                OutcomeTextSheet(title: "Архитектор — Итог роли", markdown: Self.textReply)
                    .frame(width: 402, height: 1200)
            }
        }
    }

    /// Отдельно конверт блоков без обёртки чата: доказательство, что путь
    /// конверта рисует тот же график, что и текстовый путь.
    func test06StructuredEnvelope() {
        let json = Self.envelopeReply
            .replacingOccurrences(of: "```tf-json\n", with: "")
            .replacingOccurrences(of: "\n```", with: "")
        snap("06-Конверт блоков ответа") {
            place("Тот же ответ конвертом блоков (путь чата и комментария)") {
                ChatStructuredOutputView(json: json)
            }
        }
    }
}
