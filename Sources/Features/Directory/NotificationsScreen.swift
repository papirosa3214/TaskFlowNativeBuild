import SwiftUI

// «Уведомления» — spec/SCREENS-2.md §13, `/notifications`. Список читаю из
// общего `NotificationStore` (Environment) — прогрет при старте приложения
// и живёт по WS-событию `notification:new`, единый источник истины.
//
// ⚠️ Мутации — НЕ через `NotificationStore.markRead`. Проверено чтением
// живого `server/src/routes/notifications.ts` (только чтение, спека сама
// путей не даёт): реальные роуты — `PATCH /notifications/:id/read` (БЕЗ
// тела), `POST /notifications/read-all`, `DELETE /notifications/:id`.
// `Core/Networking/APIClient+Notifications.swift.markNotificationRead` шлёт
// `PATCH /notifications/:id` С телом `{read:true}` — такого маршрута на
// сервере нет вовсе, запрос получит 404. Использую вместо него
// `directoryMarkNotificationRead`/`directoryMarkAllNotificationsRead` из
// `Support/DirectoryAPI.swift` (уже заведены параллельным исполнителем по
// той же причине) и после успеха перезагружаю стор целиком (`load()`,
// публичный метод) — стор не даёт точечно поправить один элемент
// (`notifications` — `private(set)`), а трогать чужой файл нельзя.
// `deleteNotification` в Core адресом верен — используется как есть.
//
// В отчёте оркестратору: `NotificationStore` стоит обзавестись реальными
// `markRead`/`markAllRead`/`delete` с точечным обновлением массива — иначе
// каждое действие здесь стоит полного рефетча уведомлений.
struct NotificationsScreen: View {
    @Environment(NotificationStore.self) private var notificationStore

    @State private var route: AppRoute?
    @State private var isMarkingAllRead = false
    @State private var markAllErrorMessage: String?
    @State private var rowErrors: [String: String] = [:]

    @State private var serviceTickets: [ServiceTicketSummary] = []
    @State private var serviceTicketDetails: [String: ServiceTicketDetail] = [:]
    @State private var serviceTicketsError: String?
    @State private var isLoadingServiceTickets = false
    @State private var resolutionSheetItem: ServiceTicketResolutionItem?
    @State private var resolutionSheetTaskId: String?
    @State private var openTaskError: String?
    @State private var systemState: SystemState?
    @State private var dayCounts: (total: Int, alarms: Int)?
    @State private var systemStateError: String?
    @State private var isLoadingSystemState = false
    @State private var showFeed = false
    /// Лента, открытая из «С тревогой», — только сводки с разбором.
    @State private var feedAlarmsOnly = false
    @State private var incidentFilter: IncidentFilter?

    /// Какие поломки показать по тапу на счётчик (владелец 14.10.2026:
    /// цифры были некликабельные, провалиться было некуда).
    enum IncidentFilter: String, Identifiable, Hashable {
        case all, fixed, open
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Поломки"
            case .fixed: "Починено"
            case .open: "Не починено"
            }
        }
    }
    private let serviceClient = ServiceNotificationsClient()

    private let apiClient = APIClient()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.sm) {
                TFErrorBanner(systemStateError, variant: .inline)
                TFErrorBanner(openTaskError, variant: .inline)

                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        summaryRow("Уведомлений за сегодня", dayCounts.map { "\($0.total)" }) {
                            feedAlarmsOnly = false; showFeed = true
                        }
                        TFDivider()
                        summaryRow("Из них с тревогой", dayCounts.map { "\($0.alarms)" },
                                   tint: (dayCounts?.alarms ?? 0) > 0 ? .tfOrange : nil) {
                            feedAlarmsOnly = true; showFeed = true
                        }
                        TFDivider()
                        summaryRow("Поломок", systemState.map { "\($0.counts.total)" }) {
                            incidentFilter = .all
                        }
                        TFDivider()
                        summaryRow("Починено", systemState.map { "\($0.counts.fixed)" },
                                   tint: (systemState?.counts.fixed ?? 0) > 0 ? .tfGreen : nil) {
                            incidentFilter = .fixed
                        }
                        TFDivider()
                        summaryRow("Не починено", systemState.map { "\($0.counts.open)" },
                                   tint: (systemState?.counts.open ?? 0) > 0 ? .tfRed : nil) {
                            incidentFilter = .open
                        }
                    }
                }
                .accessibilityIdentifier("system-state.summary")

                if let state = systemState, !state.incidents.isEmpty {
                    sectionTitle("Поломки")
                    TFCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(state.incidents.enumerated()), id: \.element.id) { idx, incident in
                                incidentRow(incident)
                                if idx < state.incidents.count - 1 { TFDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.md)
            .padding(.bottom, TFSpacing.xl)
        }
        .refreshable { await loadSystemState() }
        .background(Color.tfBackground)
        // Владелец 12.10.2026: «это уже не уведомление, а состояние системы».
        // Первый экран — сводка за сегодня, поток уведомлений — внутри.
        .tfNativeHeader("Состояние системы")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Обновление — оттягиванием вниз, как везде; отдельной кнопки нет.
                Menu {
                    Button {
                        showFeed = true
                    } label: {
                        Label("Все уведомления", systemImage: "tray.full")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Ещё")
                .accessibilityIdentifier("system-state.menu")
            }
        }
        .taskCardNavigation(route: $route)
        .navigationDestination(isPresented: $showFeed) { feedPage }
        .navigationDestination(item: $incidentFilter) { incidentsPage($0) }
        .task { await loadSystemState() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).tfText(.meta).foregroundStyle(Color.tfSub)
            .padding(.horizontal, TFSpacing.md)
            .padding(.top, TFSpacing.sm)
    }

    private func summaryRow(_ title: String, _ value: String?, tint: Color? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).tfText(.row).foregroundStyle(Color.tfText)
                Spacer()
                Text(value ?? "—").tfText(.row).foregroundStyle(tint ?? Color.tfSub)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tfDim)
            }
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
        .accessibilityElement(children: .combine)
    }

    /// Поломки по счётчику: все, починенные или ещё не починенные.
    private func incidentsPage(_ filter: IncidentFilter) -> some View {
        let all = systemState?.incidents ?? []
        let items = switch filter {
        case .all: all
        case .fixed: all.filter(\.fixed)
        case .open: all.filter { !$0.fixed }
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.sm) {
                if items.isEmpty {
                    Text("Здесь пусто").tfText(.action).foregroundStyle(Color.tfSub)
                        .frame(maxWidth: .infinity).padding(.top, TFSpacing.xl)
                } else {
                    TFCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, incident in
                                incidentRow(incident)
                                if idx < items.count - 1 { TFDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.md)
        }
        .refreshable { await loadSystemState() }
        .background(Color.tfBackground)
        .tfNativeHeader(filter.title)
    }

    private func incidentRow(_ incident: SystemState.Incident) -> some View {
        Button {
            Task { await openTaskFromTicket(incident.id) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(incident.title).tfText(.row).foregroundStyle(Color.tfText)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(incident.statusLine).tfText(.action)
                    .foregroundStyle(phaseColor(incident.phase))
                if let work = incident.workLine {
                    Text(work).tfText(.meta).foregroundStyle(Color.tfDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(TFTapRowStyle())
    }

    private func phaseColor(_ phase: SystemState.Incident.Phase) -> Color {
        switch phase {
        case .fixed, .working: .tfGreen
        case .waiting: .tfBlue
        case .blocked: .tfOrange
        case .idle: .tfRed
        }
    }

    // Склад: всё, что сыпется, как есть — сводки сервисов и лента сервера.
    private var feedPage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TFSpacing.sm) {
                TFErrorBanner(notificationStore.errorMessage, variant: .inline)
                TFErrorBanner(markAllErrorMessage, variant: .inline)
                TFErrorBanner(serviceTicketsError, variant: .inline)
                TFErrorBanner(openTaskError, variant: .inline)
                if isLoadingServiceTickets && serviceTickets.isEmpty {
                    ProgressView("Загрузка уведомлений")
                }
                ForEach(feedAlarmsOnly ? serviceTickets.filter(\.hasTriage) : serviceTickets) { summary in
                    NotificationTicketCard(
                        summary: summary,
                        detail: serviceTicketDetails[summary.id],
                        onOpenTask: { taskId in Task { await openTaskFromTicket(taskId) } },
                        onTapResolutionItem: { item in
                            let fallbackTaskId = serviceTicketDetails[summary.id]?.diagnosticTaskId
                            guard let taskId = item.taskId ?? fallbackTaskId else { return }
                            resolutionSheetItem = item
                            resolutionSheetTaskId = taskId
                        }
                    )
                }
                if !feedAlarmsOnly && !visibleNotifications.isEmpty {
                    TFCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleNotifications.enumerated()), id: \.element.id) { idx, n in
                                notificationRow(n)
                                if idx < visibleNotifications.count - 1 { TFDivider() }
                            }
                        }
                    }
                }
                if serviceTickets.isEmpty && visibleNotifications.isEmpty && !isLoadingServiceTickets
                    && serviceTicketsError == nil {
                    // Пустое состояние было вообще без типографики — рисовалось
                    // системным 17 pt primary (LOCK-TYPOGRAPHY-SPEC, дефект Г).
                    // Кегль и цвет — из шкалы и палитры, как у соседних подписей.
                    Text("Уведомлений пока нет")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.md)
            .padding(.bottom, TFSpacing.xl)
        }
        .background(Color.tfBackground)
        .tfNativeHeader(feedAlarmsOnly ? "С тревогой" : "Все уведомления")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await markAllRead() }
                } label: {
                    Text("Прочитать все")
                }
                .disabled(isMarkingAllRead || allRead)
            }
        }
        .refreshable {
            await notificationStore.load()
            await loadServiceTickets()
        }
        .task {
            await notificationStore.load()
            await loadServiceTickets()
        }
        .sheet(item: $resolutionSheetItem) { item in
            ServiceTicketResolutionSheet(
                item: item,
                taskId: resolutionSheetTaskId ?? "",
                onSubmitted: {
                    resolutionSheetItem = nil
                    resolutionSheetTaskId = nil
                }
            )
        }
    }

    private var allRead: Bool { notificationStore.notifications.allSatisfy(\.read) }

    /// Владелец 27.09.2026: скрываем системный шум, который дублирует то, что
    /// уже видно в «Активности» или на самой доске задач — тут это только про
    /// то, что рисуется на экране, чтение/бейдж непрочитанных на сервере не
    /// трогаем:
    /// - `auto_diagnostic_card` — авто-создание карточки диагностики
    ///   (`inboxTriageWatcher.ts`), шум при любом сбое на .110;
    /// - `agent_watch` — сторож «висит без проекта/исполнителя», не по делу
    ///   в ленте уведомлений, видно и так на доске;
    /// - `commented` — «X прокомментировал: Y» (`subtasks.ts`/`agent-state.ts`),
    ///   уже видно в живой ленте задачи;
    /// - `agent_state` — «Задача заблокирована/на проверке» и т.п. смена
    ///   статуса, тоже уже видно в живой ленте.
    /// Вердикты и назначения также остаются в ленте активности.
    /// `completed` — владелец 27.09.2026 вернул обратно, показываем как есть.
    private static let hiddenNotificationTypes: Set<String> = [
        "auto_diagnostic_card", "agent_watch", "commented", "agent_state", "reviewed", "assigned",
    ]

    /// Только система (владелец 14.10.2026): «Состояние системы» — про
    /// работу .110, а не про задачи. Уведомление по задаче — одобрил, на
    /// проверке, просрочено, план подготовлен, сторож по задаче — сюда не
    /// идёт: работа видна в «Статистике» и в самой задаче. Поломка остаётся,
    /// хотя у неё есть служебная карточка.
    private var visibleNotifications: [ApiNotification] {
        notificationStore.notifications.filter {
            !Self.hiddenNotificationTypes.contains($0.type) && ($0.taskId == nil || $0.type == "incident")
        }
    }

    // MARK: - Строка уведомления

    private func notificationRow(_ n: ApiNotification) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: TFSpacing.md) {
                avatar(n)

                Button {
                    Task { await open(n) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.text ?? "").tfText(.row).foregroundStyle(Color.tfText)
                        if let title = n.taskTitle, !title.isEmpty {
                            Text(title).tfText(.action).foregroundStyle(Color.tfSub).lineLimit(1)
                        }
                        Text(dateLine(n)).tfText(.meta).foregroundStyle(Color.tfDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TFTapRowStyle())

                HStack(spacing: TFSpacing.xs) {
                    if !n.read {
                        Circle().fill(Color.tfRed).frame(width: 8, height: 8)
                    }
                    Button {
                        Task { await delete(n) }
                    } label: {
                        Image(systemName: "trash").font(.system(size: TFIconSize.sm)).foregroundStyle(Color.tfDim)
                            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                    }
                    .accessibilityLabel("Удалить")
                    .buttonStyle(TFTapScaleStyle())
                }
            }
            if let error = rowErrors[n.id] {
                TFErrorBanner(error, variant: .inline).padding(.leading, 36 + TFSpacing.md)
            }
        }
        .padding(.horizontal, TFSpacing.md)
        .padding(.vertical, TFSpacing.sm + 2)
    }

    @ViewBuilder
    private func avatar(_ n: ApiNotification) -> some View {
        let hasActor = n.actorId != nil && !(n.actorName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        if hasActor {
            Circle()
                .fill(n.actorColor.map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(n.actorInitials ?? "?").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
        } else {
            Circle()
                .fill(Color.tfCard2)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(Color.tfDim)
                }
        }
    }

    private func dateLine(_ n: ApiNotification) -> String {
        guard let date = n.createdAtDate else { return "" }
        return "\(DirectoryDate.relative(date)) · \(DirectoryDate.absolute(date))"
    }

    // MARK: - Действия

    private func open(_ n: ApiNotification) async {
        rowErrors[n.id] = nil
        if !n.read {
            do {
                try await apiClient.directoryMarkNotificationRead(id: n.id)
                await notificationStore.load()
            } catch {
                rowErrors[n.id] = "Не удалось отметить прочитанным"
            }
        }
        guard let taskId = n.taskId else { return }
        // Тап по уведомлению на уже удалённую задачу раньше вёл на мёртвый
        // экран «Задача не найдена» — тупик, владелец 27.09.2026. Проверяем
        // существование перед переходом; если задачи нет — остаёмся в списке
        // и показываем это прямо в строке (там уже сохранено `taskTitle`).
        do {
            _ = try await apiClient.task(id: taskId)
            route = .taskDetail(taskID: taskId)
        } catch {
            rowErrors[n.id] = "Задача удалена или недоступна"
        }
    }

    /// Переход по ссылке на задачу из сводки тикета. Та же проверка
    /// существования, что и в `open(_:)` для обычного уведомления
    /// (владелец 27.09.2026): не создана — остаёмся на странице и говорим
    /// об этом баннером, вместо перехода в карточку, которой нет.
    private func openTaskFromTicket(_ taskId: String) async {
        openTaskError = nil
        do {
            _ = try await apiClient.task(id: taskId)
            route = .taskDetail(taskID: taskId)
        } catch {
            openTaskError = "Задача удалена или не создана"
        }
    }

    private func delete(_ n: ApiNotification) async {
        rowErrors[n.id] = nil
        do {
            try await apiClient.deleteNotification(id: n.id)
            await notificationStore.load()
        } catch {
            rowErrors[n.id] = "Не удалось удалить уведомление"
        }
    }

    private func loadSystemState() async {
        guard !isLoadingSystemState else { return }
        isLoadingSystemState = true
        defer { isLoadingSystemState = false }
        systemStateError = nil
        do {
            systemState = try await apiClient.systemState(from: Calendar.current.startOfDay(for: Date()))
        } catch {
            systemStateError = "Не удалось загрузить состояние системы"
        }
        // Счётчики потока — с отдельного сервиса; его сбой не должен прятать
        // поломки, поэтому ошибка здесь только оставляет прочерки.
        dayCounts = try? await serviceClient.fetchDayCounts(date: ServiceTicketDate.localDayString())
    }

    private func loadServiceTickets() async {
        // `.task` (первичная загрузка) и `.refreshable` (pull-to-refresh) оба
        // зовут этот метод — без гварда они бы мутировали одни и те же
        // `@State`-массивы одновременно (найдено финальным ревью LOCK-227,
        // Minor: "нет in-flight guard").
        guard !isLoadingServiceTickets else { return }
        isLoadingServiceTickets = true
        defer { isLoadingServiceTickets = false }

        serviceTicketsError = nil
        // Локальный календарный день устройства, НЕ UTC — иначе ночью по
        // Москве (UTC+3) сегодняшние тикеты запрашиваются как "вчера" (см.
        // `ServiceTicketDate.localDayString`, Critical #1 финального ревью).
        let today = ServiceTicketDate.localDayString()
        do {
            let list = try await serviceClient.fetchInbox(date: today)
            serviceTickets = list
            for summary in list where serviceTicketDetails[summary.id] == nil {
                // Сбой ОДНОГО тикета не должен обрывать загрузку деталей для
                // всех остальных и показывать общий баннер ошибки поверх уже
                // отрисованного списка — карточка и так падает на fallback
                // `summary.snippet`, когда `detail` не пришёл (Important #2
                // финального ревью).
                do {
                    let raw = try await serviceClient.fetchRaw(path: summary.path)
                    if let detail = ServiceTicketMarkdownParser.parse(raw) {
                        serviceTicketDetails[summary.id] = detail
                    }
                } catch {
                    continue
                }
            }
        } catch {
            serviceTicketsError = "Не удалось загрузить сводки сторонних сервисов"
        }
    }

    private func markAllRead() async {
        guard !isMarkingAllRead, !allRead else { return }
        isMarkingAllRead = true
        markAllErrorMessage = nil
        defer { isMarkingAllRead = false }
        do {
            try await apiClient.directoryMarkAllNotificationsRead()
            await notificationStore.load()
        } catch {
            markAllErrorMessage = "Не удалось отметить все прочитанными"
        }
    }
}
