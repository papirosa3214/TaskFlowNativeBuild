import SwiftUI

// «Обзор» — spec/SCREENS-1.md §5.3, `/overview`, стартовый экран. Числа и
// цвета сняты с живого `src/screens/OverviewScreen.tsx` (спека сама не
// расписывает точные цвета/иконки сетки 2×2 — только состав).
//
// Состояний загрузки/ошибки НАРОЧНО нет (спека прямо это оговаривает):
// счётчики читаются из уже прогретого `TaskStore.tasks`, пока кэш пуст —
// молча показывают 0.
struct OverviewScreen: View {
    @Environment(TaskStore.self) private var taskStore

    /// Поиск открывается кнопкой в шапке, а не пунктом навигации, поэтому
    /// ему нужен свой флаг: `NavigationLink(value:)` требует собственный
    /// тап-лейбл, а здесь тап уже съеден кнопкой шапки.
    @State private var searchOpen = false

    @State private var summaryOpen = false
    var body: some View {
        ScrollView {
            // Тот же вертикальный ритм, что у секций «Настроек»: сводки
            // отделены друг от друга, а связанные переходы собраны в одну
            // карточку-список.
            VStack(spacing: TFSpacing.xl) {
                CompletionHeatmap()
                weeklySummaryCard
                navigationSection
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.top, TFSpacing.lg)
            .padding(.bottom, TFSpacing.xl)
        }
        .sheet(isPresented: $summaryOpen) { WeeklySummarySheet() }
        .refreshable {
            await taskStore.load(silent: true)
        }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    searchOpen = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Поиск")
                .accessibilityLabel("Поиск")
                .accessibilityIdentifier("overview.search")
            }
        }
        // Кнопка в шапке — обработчик без своего Label-контейнера, поэтому
        // переход не через `NavigationLink(value:)` (тому нужен собственный
        // тап-лейбл), а через локальный `navigationDestination(isPresented:)`
        // на свой же экран поиска — тот же пункт таблицы маршрутов
        // (`SearchScreen`, INTEGRATION.md), просто без похода через общий
        // `routeDestination` в `Sources/App/`.
        // Экран поиска берём из общей фабрики маршрутов, а не создаём тип
        // напрямую: пока экран не написан, фабрика отдаёт заглушку, и
        // «Обзор» от этого не ломается.
        .navigationDestination(isPresented: $searchOpen) { routeDestination(.search) }
    }

    // MARK: - Сводка недели

    // Была фиолетово-красным градиентом иконка + коралловый тег "SECOND
    // BRAIN" — просьба владельца 03.09.2026: «сводка недели осталась
    // чёрно-бело-цветной» на фоне причёсанного остального «Обзора» (LOCK
    // причёсывания под стиль «Моделей и голосов»). Нейтрально, как соседние
    // навигационные строки.
    private var weeklySummaryCard: some View {
        Button {
            summaryOpen = true
        } label: {
            HStack(spacing: TFSpacing.md) {
                // 32×32 — тот же размер, что у иконок navCard ниже (было
                // 36×36, лишний повод для разной высоты строк).
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.tfDim)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: TFSpacing.sm) {
                        Text("Сводка недели")
                            .tfText(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tfText)
                            .lineLimit(1)
                        TFAccentTag("SECOND BRAIN", color: .tfDim)
                    }
                    Text("Победы, хвосты и фокус на цели недели")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            }
            .padding(TFSpacing.lg)
        }
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.xl))
        .buttonStyle(TFTapRowStyle())
        .accessibilityIdentifier("overview.weekly-summary")
    }

    private var navigationSection: some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink {
                    RoleLoadScreen()
                } label: {
                    TFListRow(icon: "chart.bar.xaxis", iconStyle: .plain, title: "Загрузка ролей", subtitle: "Заходы, текущая занятость и открытые слоты", trailing: AnyView(chevron), titleStyle: .body, verticalPadding: TFSpacing.md)
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
                trailing: AnyView(chevron),
                titleStyle: .body,
                verticalPadding: TFSpacing.md
            )
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13))
            .foregroundStyle(Color.tfDim)
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 40 + TFSpacing.md }

    // Кнопка поиска в шапке — тоже переход по маршруту, но actions
    // TFScreenHeader ждёт обработчик, не value-ссылку, поэтому здесь
    // отдельный @State-флаг + скрытый NavigationLink(isActive:) современный
    // эквивалент — value-based navigationDestination тоже слушает push
    // программно через тот же механизм с помощью `NavigationLink(value:)`,
    // но у кнопки шапки нет своего Label-контейнера для него, поэтому
    // прокладываем переход через отдельный invisible link.
    @State private var searchPushed = false
    private func navigateToSearch() { searchPushed = true }


}
