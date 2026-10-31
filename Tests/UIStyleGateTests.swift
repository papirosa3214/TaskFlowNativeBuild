import XCTest
import Foundation
@testable import TaskFlow

/// Ворота оформления — LOCK-UI-DRIFT-GATE-20261016.
///
/// Владелец 16.10.2026, кадр с телефона: четыре отклонения от общих
/// компонентов (чёрный фон на двух экранах, синяя «Повторить» без
/// оформления, нижняя навигация под модальной формой, большие красные
/// кнопки на экранах подключений). Дословно: «Это нужно выявлять мне до
/// передачи сборки тебе. Тебе не должно приходиться обходить приложение и
/// собирать такие скриншоты».
///
/// Три проверки в цикле приёмки (AGENT-CYCLE.md §7):
///   1. проверка кода — этот тест и `Tools/ui-drift-scan.sh`;
///   2. визуальный обход экранов — `UITests/UIStyleGateUITests.swift`;
///   3. сравнение с утверждёнными образцами — просмотр изменившихся кадров
///      агентом до сдачи.
///
/// Тест работает по исходникам, а не по кадрам: он компилируется вместе с
/// приложением и ловит отклонение в том же запуске, что и сборка. Поэтому
/// проверка занимает секунды и не требует симулятора с кадрами.
final class UIStyleGateTests: XCTestCase {

    /// Корень исходников: рядом с папкой `Tests` в распакованной проверке.
    private static var sourcesRoot: URL? {
        // #filePath = <repo>/Tests/UIStyleGateTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <repo>
            .appendingPathComponent("Sources")
    }

    private func swiftFiles() throws -> [URL] {
        let root = try XCTUnwrap(Self.sourcesRoot, "не найден корень Sources рядом с Tests")
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        XCTAssertGreaterThan(files.count, 100, "Sources почти пуст — тест ничего не проверяет")
        return files
    }

    private func source(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Правило 1. Фон экрана

    /// Экраны из кадра владельца: «Параметры сервера» и «Диагностика»
    /// показывали чёрное поле вместо фона приложения. Оба строятся на
    /// сыром `List`, который рисует СВОЙ системный фон, — отсюда и чёрное.
    func testServerSettingsAndDiagnosticsUseAppBackground() throws {
        let cases: [(String, String)] = [
            ("Sources/Features/Settings/ServerSettingsScreen.swift", "Параметры сервера"),
            ("Sources/Features/Settings/AppDiagnosticsScreen.swift", "Диагностика"),
        ]
        let root = try XCTUnwrap(Self.sourcesRoot?.deletingLastPathComponent())

        for (relative, title) in cases {
            let text = try source(of: root.appendingPathComponent(relative))
            XCTAssertTrue(
                text.contains(".tfScreenBackground()"),
                "\(title): на экране нет .tfScreenBackground() — вместо фона приложения будет чёрное поле"
            )
            // Список без гашения системного фона — ровно тот дефект из кадра.
            XCTAssertTrue(
                text.contains("List {"),
                "\(title): ожидался List — проверка перестала быть про тот экран"
            )
        }
    }

    /// Общий модификатор обязан гасить системный фон списка И класть под
    /// содержимое `tfBackground`. Без первого `List` перекроет фон своим
    /// системным, без второго под ним будет просвет.
    func testScreenBackgroundModifierHidesSystemListBackground() throws {
        let root = try XCTUnwrap(Self.sourcesRoot?.deletingLastPathComponent())
        let text = try source(of: root.appendingPathComponent("Sources/DesignSystem/Components/TFScreenBackground.swift"))

        XCTAssertTrue(text.contains("scrollContentBackground(.hidden)"),
                      "модификатор не гасит системный фон списка — чёрное поле вернётся")
        XCTAssertTrue(text.contains("tfBackground"),
                      "модификатор не кладёт фон приложения под содержимое")
    }

    /// Класс, а не симптом: тот же дефект был минимум на пяти экранах
    /// настроек. Ни один КОРНЕВОЙ список настроек не должен остаться без
    /// общего фона.
    ///
    /// Файл-шторка (сам по себе окно) исключением не считается: фон у неё
    /// задаёт материал. Список исключений — тот же, что в скане, чтобы две
    /// проверки не расходились.
    func testNoSettingsListShipsWithoutAppBackground() throws {
        let dir = try XCTUnwrap(Self.sourcesRoot)
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Settings")

        // Эти файлы — окна, а не корневые экраны: их показывает `.sheet`,
        // и фон под ними задаёт материал окна, а не приложения.
        let windows: Set<String> = ["EscalationStepEditor.swift"]

        var offenders: [String] = []
        for url in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where url.pathExtension == "swift" {
            let text = try source(of: url)
            guard text.contains("List {") || text.contains("Form {") else { continue }
            guard !windows.contains(url.lastPathComponent) else { continue }
            let showsItsOwnSheet = text.contains(".sheet") || text.contains(".fullScreenCover")
            guard !text.contains("tfScreenBackground"), !showsItsOwnSheet else { continue }
            offenders.append(url.lastPathComponent)
        }
        XCTAssertEqual(offenders, [], "экраны настроек с корневым списком без общего фона: \(offenders)")
    }

    // MARK: - Правило 2. Кнопки приложения серые, а не красные/синие

    /// Владелец (кадр): «Reddit и другие новые экраны подключений — большие
    /// красные кнопки вместо принятых серых». Причина одна: `TFButton` без
    /// `variant:` по умолчанию `.primary`, а это красная заливка.
    func testConnectActionsAreGreyNotRed() throws {
        let root = try XCTUnwrap(Self.sourcesRoot?.deletingLastPathComponent())
        let cases: [(String, String)] = [
            ("Sources/Features/Settings/GmailIntegrationCard.swift", "\"Добавить и авторизовать\""),
        ]
        for (relative, title) in cases {
            let text = try source(of: root.appendingPathComponent(relative))
            guard let range = text.range(of: title) else {
                XCTFail("\(relative): не нашёл кнопку \(title) — проверка устарела")
                continue
            }
            let call = text[range.lowerBound...].prefix(300)
            XCTAssertTrue(
                call.contains("variant: .secondary"),
                "\(relative): кнопка \(title) без variant: → .primary (красная заливка). Нужен .secondary"
            )
        }
        // Экран подключений Composio: подключение стало тумблером в списке
        // сервисов (29.10.2026, `855a0844`), отдельной кнопки «Подключить
        // аккаунт» больше нет. Остальные кнопки этого экрана обязаны иметь
        // явный `variant:` — иначе одна из них молча станет красной.
        let composio = try source(of: root.appendingPathComponent("Sources/Features/Settings/ComposioIntegrationsScreen.swift"))
        var index = composio.startIndex
        while let found = composio.range(of: "TFButton(", range: index..<composio.endIndex) {
            let end = composio.index(found.upperBound, offsetBy: 260, limitedBy: composio.endIndex) ?? composio.endIndex
            let call = String(composio[found.lowerBound..<end])
            index = found.upperBound
            guard !call.contains("variant") else { continue }
            // Подтверждение сохранения — единственное исключение: красная
            // заливка подтверждения согласована.
            XCTAssertTrue(
                call.contains("Сохранить") || call.contains("Сохраняем"),
                "кнопка экрана подключений Composio без variant: — станет красной: \(call.prefix(80))"
            )
        }
    }

    /// Подтверждение сохранения в профиле.
    ///
    /// С 22.10.2026 (перенос сохранённой работы по прямому поручению
    /// владельца, `docs/2026-10-22-preserved-work-integration.md`: «серые
    /// кнопки сохранения (JEV, профиль, шаблоны)») кнопка «Сохранить» в
    /// профиле — серая, как в JEV и шаблонах. До 22.10.2026 профиль был
    /// шторкой, и кнопка сохранения была первичной (красной).
    func testSaveConfirmationUsesAgreedVariant() throws {
        let root = try XCTUnwrap(Self.sourcesRoot?.deletingLastPathComponent())
        let text = try source(of: root.appendingPathComponent("Sources/Features/Settings/EditProfileScreen.swift"))
        XCTAssertTrue(
            text.contains("\"Сохранить\", variant: .secondary"),
            "подтверждение сохранения в профиле — серая кнопка приложения (.secondary)"
        )
    }

    /// Класс дефекта: `TFButton` без `variant` в любом файле настроек или
    /// подключений — красная заливка по умолчанию. Единственное исключение,
    /// о котором скан знает, — подтверждение действия.
    func testNoActionButtonSilentlyDefaultsToRed() throws {
        let dir = try XCTUnwrap(Self.sourcesRoot)
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Settings")
        let confirmations = ["Сохранить", "Сохраняем", "Создать"]
        var offenders: [String] = []

        for url in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where url.pathExtension == "swift" {
            let text = try source(of: url)
            var index = text.startIndex
            while let found = text.range(of: "TFButton(", range: index..<text.endIndex) {
                let end = text.index(found.upperBound, offsetBy: 260, limitedBy: text.endIndex) ?? text.endIndex
                let call = String(text[found.lowerBound..<end])
                index = found.upperBound
                guard !call.contains("variant") else { continue }
                let isConfirmation = confirmations.contains { word in
                    call.contains("\(word)")
                }
                if !isConfirmation { offenders.append("\(url.lastPathComponent): \(call.prefix(80))") }
            }
        }
        XCTAssertEqual(offenders, [], "TFButton без variant: — красная заливка по умолчанию: \(offenders)")
    }

    // MARK: - Правило 3. Ошибка загрузки оформлена, а не вставлена в поток

    /// Владелец (кадр): «Настройки → машины — ошибка загрузки и синяя
    /// “Повторить” вставлены внизу секции без нормального оформления».
    /// Текст ошибки шёл обычным `Text`, действие — системной `Button`.
    func testMachinesLoadFailureUsesSharedErrorAndButton() throws {
        let root = try XCTUnwrap(Self.sourcesRoot?.deletingLastPathComponent())
        let text = try source(of: root.appendingPathComponent("Sources/Features/Settings/RemoteMachinesScreen.swift"))

        XCTAssertTrue(text.contains("TFErrorBanner"),
                      "ошибка загрузки машин должна идти через общий TFErrorBanner, а не голым Text")
        XCTAssertTrue(text.contains("TFButton(\"Повторить\", icon: \"arrow.clockwise\", variant: .secondary)"),
                      "«Повторить» должна быть кнопкой приложения (.secondary), а не системной синей Button")
        XCTAssertFalse(text.contains("Button(\"Повторить\")"),
                       "системная синяя кнопка «Повторить» осталась в разделе машин")
    }

    // MARK: - Правило 4. Нижняя навигация не остаётся под модальной формой

    /// Владелец (кадр): «Быстрое создание задачи — нижняя навигация
    /// остаётся за формой, поднимается с клавиатурой и просвечивает».
    /// Причина: прозрачный `fullScreenCover` (LOCK-140), под которым всё
    /// остаётся видимым. Поэтому таббар на время панели не рисуется.
    func testTabBarHiddenWhileQuickAddPanelIsOpen() throws {
        let root = try XCTUnwrap(Self.sourcesRoot?.deletingLastPathComponent())
        let text = try source(of: root.appendingPathComponent("Sources/App/Navigation/RootShellView.swift"))

        // Панель открыта ровно тогда, когда `quickAddDraft` не nil — и на это
        // же состояние обязан реагировать таббар.
        XCTAssertTrue(
            text.contains("if quickAddDraft != nil {") && text.contains("EmptyView()"),
            "таббар не скрывается на время панели быстрого создания"
        )
        // Фон панели прозрачный намеренно (LOCK-140) — скан не должен решать,
        // что его надо перекрасить: чинится видимость, а не оверлей.
        XCTAssertTrue(
            text.contains(".presentationBackground(.clear)"),
            "панель быстрого создания перестала быть прозрачной — проверка изменилась"
        )
    }

    // MARK: - Проверка кода целиком (скан запускается из теста)

    /// Скан живёт в `Tools/ui-drift-scan.sh` и запускается из цикла приёмки.
    /// Здесь проверяем то, что скан может упустить: что он вообще есть и
    /// исполняем, иначе «проверка кода» молча ничего не делает.
    ///
    /// Запуск сканa из теста намеренно НЕ делаем: юнит-тест живёт в
    /// песочнице симулятора, где `Process` недоступен, и такой запуск
    /// всегда падал бы в skip и прикрыл бы регрессию.
    func testDriftScanScriptExistsAndIsExecutable() throws {
        let repo = try XCTUnwrap(Self.sourcesRoot?.deletingLastPathComponent())
        let scan = repo.appendingPathComponent("Tools/ui-drift-scan.sh")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scan.path),
            "нет Tools/ui-drift-scan.sh — проверка кода не запускается вовсе"
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: scan.path),
            "Tools/ui-drift-scan.sh не исполняемый — скан нельзя запустить"
        )

        let text = try source(of: scan)
        // Четыре правила из кадра владельца — все должны быть в скане,
        // иначе часть дефектов снова дойдёт до телефона.
        XCTAssertTrue(text.contains("tfScreenBackground"), "в скане нет правила про фон экрана")
        XCTAssertTrue(text.contains("TFButton"), "в скане нет правила про кнопки без variant")
        XCTAssertTrue(text.contains("Повторить"), "в скане нет правила про синюю системную кнопку")
        XCTAssertTrue(text.contains("Color.black"), "в скане нет правила про сплошной чёрный")
        // Классификация NEW/KNOWN: без неё скан превращается в формальность.
        XCTAssertTrue(text.contains("KNOWN") && text.contains("NEW"),
                      "скан не различает новые и зафиксированные отклонения")
        // Отсечение системных диалогов: без него скан выдаёт ложные
        // находки, и владелец получает задачу на бесполезную правку.
        XCTAssertTrue(text.contains("in_system_dialog"),
                      "скан не отличает кнопку в .alert от кнопки в потоке экрана")
        // Второй известный класс пропуска: экран под .tint(tfText).
        XCTAssertTrue(text.contains("TINTED_SCREENS"),
                      "скан не знает про тинированные экраны, где системные кнопки серые")
        // Правило о находке обязано быть в самом скане, а не только в цикле:
        // агент читает вывод скана в момент находки, а AGENT-CYCLE.md — позже.
        XCTAssertTrue(text.contains("находка ложная") || text.contains("ложная"),
                      "в скане нет правила о ложных находках — находку можно пропустить молча")
    }
}
