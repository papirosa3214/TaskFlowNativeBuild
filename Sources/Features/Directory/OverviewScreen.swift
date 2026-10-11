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
    var body: some View {
        VStack(spacing: TFSpacing.xl) {
            CompletionHeatmap(depth: reduceMotion ? 0 : depth)
            navigationSection
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .padding(.top, TFSpacing.lg)
        .padding(.bottom, TFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
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
    private var weeklySummaryCard: some View {
        Button { summaryOpen = true } label: {
            TFListRow(icon: "brain.head.profile", iconStyle: .plain, title: "Сводка недели", subtitle: "Победы, хвосты и фокус на цели недели", titleStyle: .body, verticalPadding: TFSpacing.md)
        }.buttonStyle(.plain).accessibilityIdentifier("overview.weekly-summary")
    }

    private var navigationSection: some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                weeklySummaryCard
                TFDivider(inset: rowDividerInset)
                NavigationLink {
                    RoleLoadScreen()
                } label: {
                    TFListRow(icon: "chart.bar.xaxis", iconStyle: .plain, title: "Загрузка ролей", subtitle: "Заходы, текущая занятость и открытые слоты", titleStyle: .body, verticalPadding: TFSpacing.md)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("overview.role-load")
                TFDivider(inset: rowDividerInset)
                navigationRow(route: .knowledge, icon: "books.vertical", title: "База знаний", subtitle: "Документы, папки и поиск по всем проектам")
                TFDivider(inset: rowDividerInset)
                navigationRow(route: .notifications, icon: "bell", title: "Уведомления", subtitle: "История событий и напоминаний")
                TFDivider(inset: rowDividerInset)
                navigationRow(route: .activity, icon: "waveform.path.ecg", title: "Активность и статистика", subtitle: "Графики продуктивности и выполненные задачи")
                TFDivider(inset: rowDividerInset)
                navigationRow(route: .settings, icon: "gearshape", title: "Настройки", subtitle: "Профиль, ИИ, сервер и внешний вид")
            }
        }
    }

    private func navigationRow(route: AppRoute, icon: String, title: String, subtitle: String) -> some View {
        NavigationLink(value: route) {
            TFListRow(
                icon: icon,
                iconStyle: .plain,
                title: title,
                subtitle: subtitle,
                titleStyle: .body,
                verticalPadding: TFSpacing.md
            )
        }
        .buttonStyle(.plain)
    }



    private var rowDividerInset: CGFloat { TFSpacing.lg + 40 + TFSpacing.md }

}
