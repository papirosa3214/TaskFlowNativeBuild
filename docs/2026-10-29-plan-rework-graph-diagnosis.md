# Диагностика возврата в графе командного плана

Дата: 29.10.2026. Только диагностика. Карточка `cac65b0c-5ad1-4730-a46b-cb444a03794b`, план `tcp_e2e17022-160b-4922-899a-4ccefaef60b6`, approved, version 4. Сервер HEAD `90b8edfbabc862ba363978607078f5f2121846a8`, iOS HEAD `41ec9659b4db2c997501dd08fcebd48a6a47bb50`.

## Вывод

1. Геометрия подтверждена: отдельный маршрут возврата строит прямоугольник с портами сверху/снизу, вместо боковых точек окружности. Жёлтый цвет и пунктир сохранять.
2. Неверный адресат **именно «Доработки 1» на скриншоте не подтверждён**. Критик действительно вернул шаг QA, а не один из пяти шагов builder. Нижний портрет — критик, предпоследний — QA. Это проверено по исходным avatar-qa.png и avatar-critic-verifier.png, а не по сходству лиц.
3. На актуальном плане обнаружен другой доказанный смысловой дефект: последующая доработка разработчику сворачивается в узел QA. Это смешение двух значений rework_of_key на сервере и безусловной трактовки этого поля клиентом как «та же исполнительская позиция».

## Фактический адресат и история

Запись reviews `b8cc8a4d-b960-4dd4-b7e2-872ac7218048`, 2026-10-29 02:46:33 UTC (05:46:33 МСК), reviewer `role_critic_verifier`, verdict `changes_requested`. Замечания: отсутствие боевой выкладки, неподтверждённые реальные провайдеры, несохранение выбора провайдера, отсутствие учёта расхода ручного чата.

- `final_review_0c057925` → `qa_fix_3c91f1fd`: реальная связь критика с доработкой.
- `qa_fix_3c91f1fd`: role_key=qa, iteration=1, rework_of_key=qa_6; подзадача `65a9e72f-e024-4a33-bbb9-acdfe3b8aec8`, заголовок «Доработка 1: Проверка вживую…». Значит фактическое исходное место — `qa_6` (подзадача `4e1892d4-4190-4d04-8f8d-fd574269c88c`).
- Позже QA создал `builder_fix_2`: role_key=builder, iteration=2, rework_of_key=qa_fix_3c91f1fd; подзадача `980a2bd2-fc30-49e3-9e71-593934eef4de`. В результате указаны исправления расхода/лимитов и сохранения провайдера, коммит infra-panel `9343082`.
- Следом `qa_recheck_2`: role_key=qa, iteration=2, rework_of_key=qa_fix_3c91f1fd; подзадача `e24a2158-34e1-4df3-8db6-b5860bcacf9b`, на момент чтения blocked.
- `critic_recheck_f8f46b92` ожидает повторной проверки.

Скриншот IMG_9349.PNG просмотрен целиком. На нём пять builder, QA и критик; жёлтая стрелка от нижнего критика к QA. Номер 06:25 на кадре не доказывает версию клиентского бинарника или точное время получения payload. Текущие данные позднее кадра; не приравниваем эти состояния.

## API и источник данных

Данные прочитаны по SSH непосредственно из `server/taskflow.db`, без TaskFlow MCP. `server/src/routes/task-collaboration-plans.ts:79–122` (presentSingle) читает nodes по rowid, передаёт slot_key, role_key, iteration и rework_of_key без переназначения роли. Edges передаются по конкретным from_slot_key/to_slot_key. Поэтому различие уже присутствует в модели, а не возникает при сопоставлении по имени.

Ограничение: сырой HTTP payload авторизованного GET не получен. Попытка с сохранённым значением users.api_token дала 401 (значение не выводилось); ключ TASKFLOW_AGENT_TOKEN в vault не найден. Представление API проверено по актуальному коду сериализатора и данным его SELECT, но это не выдаётся за захваченный сетевой ответ телефона.

## Доказанный механизм свёртки

`Sources/Features/Task/Detail/PlanReworkCollapse.swift:42–102`: root проходит всю цепочку reworkOfKey без проверки роли; latest выбирает максимальную iteration, при равенстве оставляет первый узел.

Для текущих данных фактическая функция, запущенная через swift на Mac без приложения/симулятора, вернула:

```text
slots = builder_1, builder_2, builder_3, builder_4, builder_5, qa_6, final_review_0c057925
latest[qa_6] = builder_fix_2
latest[final_review_0c057925] = critic_recheck_f8f46b92
returns = final_review_0c057925 → qa_6, round 1
```

`builder_fix_2` и `qa_recheck_2` оба имеют iteration=2. Поскольку builder записан раньше, QA recheck не заменяет его в latest. `CollaborationPlanView.swift:591–605` берёт портрет/roleKey исходного place=qa_6, а состояние — latest=builder_fix_2. Получается портрет QA со статусом developer; сам developer fix отсутствует среди slots. Его связи qa_fix→builder_fix→qa_recheck схлопываются в петли qa_6→qa_6 и отбрасываются. Это не поиск по role id/index: ключи слотов точные, ошибка — в семантике root.

Сервер `server/src/runtime/planMutations.ts:371–410`, op rework, создаёт fix с выбранной role_key (по умолчанию builder), но rework_of_key=from.slot_key, где from — проверяющий QA/critic. Там поле обозначает источник возврата. Для критического final-review пути `planReviewLifecycle.ts:543+` клонируется конкретный исправляемый узел: там поле обозначает предыдущую попытку исполнителя. Одинаковое поле имеет два разных смысла.

Нельзя достоверно объявить, что builder_fix_2 относится именно к builder_1, builder_2 или другому исходному разработчику: текущая запись содержит ссылку на QA, точный исполнительский slot не указан. Роль builder и текст замечаний недостаточны для такого выбора.

## Геометрия

`CollaborationPlanView.swift:1009–1015` для reworkReturns вызывает chainReturnLink. В `:1429–1462` вертикальная ветка берёт start/end через ±nodeHeight/2 и x центра, затем три прямых отрезка через sideX=min(x)-nodeWidth. Это буквально прямоугольник между верхней/нижней точками. Обрезки по касательной окружности в этой ветке нет. Для горизонтальной ветки есть квадратичная дуга с боковыми портами. participantConnection (:1371+) имеет нормализованные радиальные порты и касательную стрелки, но использует добавочный зазор +12; простая подмена без проверки не гарантирует соединения с границей круга.

## Предлагаемая точечная правка (не выполнена)

- Разделить «кто вернул» и «какую попытку заменяет» в контракте. Сворачивать только известные повторные попытки того же исполнительского slot. Для межролевого rework без точного target slot сохранять отдельное место builder_fix_2; не угадывать первый/последний builder. Одной проверки role_key недостаточно для двух разных задач одной роли.
- Передавать при возврате точный slot исправляемого этапа (если возврат действительно относится к существующему этапу). Для исторических неоднозначных записей показать самостоятельный шаг, а не придумывать адресат.
- Вертикальный возврат: боковые порты окружностей, обход слева и плавные повороты либо кривая с портами по касательной; наконечник по последнему направлению маршрута. Сохранить round=1 yellow и dash=[5,4].

## Нужные RED → GREEN проверки

1. Чистый Swift/Foundation тест на приведённом fixture: межролевой builder_fix_2 не исчезает в qa_6; QA latest=qa_recheck_2; статус builder не подменяет QA. На текущей функции ожидается RED.
2. Пять builder с разными slot/subtask id: возврат к конкретному builder_N попадает только в него; перестановка узлов не меняет адресата.
3. Повторные попытки того же slot, два круга, лимит, отсутствие петель/дубликатов — сохранить существующие PlanReworkCollapseTests. Они покрывают одинаковую роль по цепочке и не ловят текущий межролевой случай.
4. Отдельный тест равной iteration: неоднозначность не решается порядком массива и чужая роль не побеждает QA recheck.
5. Серверный целевой тест op rework: источник reviewer и точный исправляемый slot различаются и сериализуются однозначно; запуск только с --maxWorkers=4.
6. Чистая геометрия без SwiftUI/симулятора: вертикальные и горизонтальные центры, боковые порты на радиусе, нет прохода через круги, наконечник совпадает с касательной, нет обрезки при близкой левой границе. Проверять координаты, а не текст исходника. Сначала RED на текущих вертикальных портах.

В рамках диагностики тесты не добавлялись. Выполнен только отдельный запуск текущей Foundation-функции с фактическим fixture; это воспроизведение, не RED→GREEN исправления. Исходники, карточка, роли не менялись; роли не запускались, симулятор/UI-тесты/установка не использовались. Артефакт оставлен в docs, без коммита и push.

## Снимок данных для повторения

```json
{
  "nodes": [
    {
      "slot_key": "builder_1",
      "role_key": "builder",
      "iteration": 0,
      "rework_of_key": null
    },
    {
      "slot_key": "builder_2",
      "role_key": "builder",
      "iteration": 0,
      "rework_of_key": null
    },
    {
      "slot_key": "builder_3",
      "role_key": "builder",
      "iteration": 0,
      "rework_of_key": null
    },
    {
      "slot_key": "builder_4",
      "role_key": "builder",
      "iteration": 0,
      "rework_of_key": null
    },
    {
      "slot_key": "builder_5",
      "role_key": "builder",
      "iteration": 0,
      "rework_of_key": null
    },
    {
      "slot_key": "qa_6",
      "role_key": "qa",
      "iteration": 0,
      "rework_of_key": null
    },
    {
      "slot_key": "final_review_0c057925",
      "role_key": "critic_verifier",
      "iteration": 0,
      "rework_of_key": null
    },
    {
      "slot_key": "qa_fix_3c91f1fd",
      "role_key": "qa",
      "iteration": 1,
      "rework_of_key": "qa_6"
    },
    {
      "slot_key": "critic_recheck_f8f46b92",
      "role_key": "critic_verifier",
      "iteration": 1,
      "rework_of_key": "final_review_0c057925"
    },
    {
      "slot_key": "builder_fix_2",
      "role_key": "builder",
      "iteration": 2,
      "rework_of_key": "qa_fix_3c91f1fd"
    },
    {
      "slot_key": "qa_recheck_2",
      "role_key": "qa",
      "iteration": 2,
      "rework_of_key": "qa_fix_3c91f1fd"
    }
  ],
  "edges": [
    {
      "from_slot_key": "builder_1",
      "to_slot_key": "builder_4"
    },
    {
      "from_slot_key": "builder_2",
      "to_slot_key": "builder_3"
    },
    {
      "from_slot_key": "builder_3",
      "to_slot_key": "builder_1"
    },
    {
      "from_slot_key": "builder_4",
      "to_slot_key": "qa_6"
    },
    {
      "from_slot_key": "builder_4",
      "to_slot_key": "qa_fix_3c91f1fd"
    },
    {
      "from_slot_key": "builder_5",
      "to_slot_key": "qa_6"
    },
    {
      "from_slot_key": "builder_5",
      "to_slot_key": "qa_fix_3c91f1fd"
    },
    {
      "from_slot_key": "builder_fix_2",
      "to_slot_key": "qa_recheck_2"
    },
    {
      "from_slot_key": "final_review_0c057925",
      "to_slot_key": "qa_fix_3c91f1fd"
    },
    {
      "from_slot_key": "qa_6",
      "to_slot_key": "final_review_0c057925"
    },
    {
      "from_slot_key": "qa_fix_3c91f1fd",
      "to_slot_key": "builder_fix_2"
    },
    {
      "from_slot_key": "qa_recheck_2",
      "to_slot_key": "critic_recheck_f8f46b92"
    }
  ]
}
```

## После диагностической фазы

По последующему поручению выполнены исправления: [результат и проверки](2026-10-29-plan-rework-graph-fix.md). Ограничения выше описывают момент исходной диагностики.
