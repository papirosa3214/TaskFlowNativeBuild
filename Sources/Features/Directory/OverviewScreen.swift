import SwiftUI

// «Обзор» — spec/SCREENS-1.md §5.3, `/overview`, стартовый экран. Числа и
// цвета сняты с живого `src/screens/OverviewScreen.tsx` (спека сама не
// расписывает точные цвета/иконки сетки 2×2 — только состав).
//
// Состояний загрузки/ошибки НАРОЧНО нет (спека прямо это оговаривает):
// счётчики читаются из уже прогретого `TaskStore.tasks`, пока кэш пуст —
// молча показывают 0.
struct OverviewScreen: View {
    @State private var summaryOpen = false
    @State private var depth: CGFloat = 0
    @State private var dragOrigin: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openIncidents: Int?
    @State private var busyRoles: Int?
    /// Сколько рутин активны — значение справа в строке «Мои рутины».
    @State private var routinesActive: Int?
    var body: some View {
        // Владелец 12.10.2026: разделы «прилипали» к карте — отступ 24 вместо 12.
        VStack(spacing: TFSpacing.xl) {
            CompletionHeatmap(depth: reduceMotion ? 0 : depth)
            navigationSection
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.top, TFSpacing.xs)
        .padding(.bottom, TFSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    if dragOrigin == nil { dragOrigin = depth }
                    depth = min(1, max(0, (dragOrigin ?? depth) + value.translation.height / 130))
                }
                .onEnded { value in
                    guard dragOrigin != nil else { return }
                    let projected = (dragOrigin ?? depth) + value.predictedEndTranslation.height / 130
                    dragOrigin = nil
                    withAnimation(.spring(duration: 0.26, bounce: 0)) {
                        depth = projected >= 0.5 ? 1 : 0
                    }
                }
        )
        .sheet(isPresented: $summaryOpen) { WeeklySummarySheet() }
        .task { await loadRowValues() }
        .background(Color.tfBackground)
        // Штатная SwiftUI-шапка. Кнопка поиска переехала из
        // самодельного TFScreenHeader в `.toolbar { .topBarTrailing }` —
        // дубль заголовка «Обзор» (системный + наш поверх) ушёл.
        //
        // ⚠️ Раньше здесь ещё стояли `.toolbarBackground(.ultraThinMaterial,
        // for: .navigationBar)` + `.toolbarBackgroundVisibility(.automatic,
        // for:)` — этот экран пропустили при чистке остальных (см.
        // `TFNativeHeader.swift`), и это была ручная имитация того, что
        // iOS 26 и так рисует сама («scroll edge effect»): именно из-за неё
        // при скролле вверх на «Обзоре» дёргался серый фон в шапке (жалоба
        // владельца 03.09.2026 — «когда наверх закидываю, меняется фон» —
        // тот же баг, что чинили в самом начале на «Проектах»). `tfNativeHeader`
        // без ручного `toolbarBackground` — тот же приём, что и везде.
        .tfNativeHeader("Обзор", displayMode: .inline)
    }

    // MARK: - Сводка недели

    // Была фиолетово-красным градиентом иконка + коралловый тег "SECOND
    // BRAIN" — просьба владельца 03.09.2026: «сводка недели осталась
    // чёрно-бело-цветной» на фоне причёсанного остального «Обзора» (LOCK
    // причёсывания под стиль «Моделей и голосов»). Нейтрально, как соседние
    // навигационные строки.
    //
    // 12.10.2026 (LOCK-OVERVIEW-YELLOW-DISPLAY): иконка убрана совсем, как и
    // подзаголовок-пояснение, заголовок стал жёлтым капсом (образец владельца).
    private var weeklySummaryCard: some View {
        Button { summaryOpen = true } label: {
            navigationRowBody(title: "Сводка недели")
        }.buttonStyle(.plain).accessibilityIdentifier("overview.weekly-summary")
    }

    // Владелец 12.10.2026: без общей подложки — строки лежат на фоне, между
    // ними линия. Справа живое значение; где значения нет — стрелка.
    private var navigationSection: some View {
        VStack(spacing: 0) {
            weeklySummaryCard
            TFDivider()
            NavigationLink {
                RoleLoadScreen()
            } label: {
                navigationRowBody(title: "Загрузка ролей", value: busyRoles.map { $0 > 0 ? "работает: \($0)" : "свободны" })
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("overview.role-load")
            TFDivider()
            navigationRow(route: .knowledge, title: "База знаний")
            TFDivider()
            navigationRow(route: .notifications, title: "Состояние системы",
                          value: openIncidents.map { $0 > 0 ? "не починено: \($0)" : "в порядке" },
                          tint: (openIncidents ?? 0) > 0 ? .tfRed : nil)
            TFDivider()
            navigationRow(route: .activity, title: "Статистика")
            TFDivider()
            navigationRow(route: .routines, title: "Мои рутины", value: routinesActiveText)
            TFDivider()
            navigationRow(route: .settings, title: "Настройки")
        }
    }

    private func navigationRowBody(title: String, value: String? = nil, tint: Color? = nil) -> some View {
        HStack(spacing: TFSpacing.md) {
            Text(title)
                .tfSectionDisplay(style: .taskTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let value {
                Text(value).tfText(.action).foregroundStyle(tint ?? Color.tfSub).lineLimit(1)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            }
        }
        .padding(.vertical, TFSpacing.md)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// Значения справа — по возможности: сбой запроса оставляет стрелку.
    private func loadRowValues() async {
        let client = APIClient()
        if let state = try? await client.systemState(from: Calendar.current.startOfDay(for: Date())) {
            openIncidents = state.counts.open
        }
        if let load: RoleLoad = try? await client.request(.get, "/coordination/role-load",
                                                         query: [URLQueryItem(name: "window", value: "24h")]) {
            busyRoles = Set(load.active_now.compactMap(\.role_key)).count
        }
        if let list: ApiSchedulesResponse = try? await client.request(.get, "/schedules") {
            routinesActive = list.schedules.filter { $0.status == "active" }.count
        }
    }

    /// Значение справа у строки «Мои рутины»: сколько рутин активны сейчас.
    private var routinesActiveText: String? {
        guard let routinesActive else { return nil }
        return routinesActive > 0 ? "\(routinesActive) активных" : "нет активных"
    }

    private func navigationRow(route: AppRoute, title: String, value: String? = nil, tint: Color? = nil) -> some View {
        NavigationLink(value: route) {
            navigationRowBody(title: title, value: value, tint: tint)
        }
        .buttonStyle(.plain)
    }
}
