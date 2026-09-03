import SwiftUI

// `ProjectTasksScreen`/`LabelTasksScreen` рисуют перед заголовком цветной
// значок (кружок цвета проекта / иконка тега цвета метки, `ScreenHeader`
// в вебе получает JSX-узел, а не строку) — `TFScreenHeader` (DesignSystem,
// чужой файл) принимает только `String title`, добавить туда слот я не могу.
// Свой локальный дубль geometрии `.compact`-варианта (высота 48, паддинг
// экрана, `.ultraThinMaterial`) — тот же приём дублирования, что у всего
// раздела Directory/Support, плюс слот `accessory` перед текстом.
// В отчёте — оркестратору: возможно, стоит завести такой слот и в самом
// `TFScreenHeader`, чтобы не плодить вторую шапку.
//
// Кнопка «назад» — `DirectoryBackButton()` (сосед по этой же папке,
// `NotificationsScreen.swift`/`ActivityScreen.swift` уже используют её как
// канонический ответ на то, что `TFScreenHeader` стрелку сама не рисует).
struct DirectoryCompactHeader: View {
    let title: String
    var actions: [TFHeaderAction] = []
    var accessory: (() -> AnyView)?

    var body: some View {
        // Было ZStack с заголовком по центру ВСЕГО экрана, без учёта ширины
        // кнопок вокруг — у длинного названия проекта/метки текст наезжал на
        // «+» справа (просьба владельца 03.09.2026: «с шапкой что-то не то»,
        // видно на любом проекте с названием подлиннее). Теперь заголовок —
        // во флекс-зоне между двумя зеркальными по ширине (`TFHitTarget.min`)
        // зонами кнопок: `lineLimit(1)` при нехватке места обрезает многоточием,
        // а не залезает на «+». Как побочный эффект центрирование уже не
        // идеально-абсолютное при 2+ иконках справа — сегодня везде максимум
        // одна, этого достаточно.
        HStack(spacing: TFSpacing.sm) {
            DirectoryBackButton()
                .frame(width: TFHitTarget.min, alignment: .leading)

            HStack(spacing: 6) {
                accessory?()
                Text(title)
                    .tfText(.title)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: TFSpacing.headerActionsGap) {
                ForEach(actions) { action in
                    TFIconButton(action.icon, size: 18, action: action.handler)
                }
            }
            .frame(width: TFHitTarget.min, alignment: .trailing)
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
        .frame(height: 48)
        // `.top` + заход под статус-бар — как у эталонной шапки «Уведомлений».
        // Было `.bottom`: градиент перевёрнут, и полоса не накрывала статус-бар.
        // Штатный фон навбара — вызывающий код добавляет
        // .toolbarBackground(.ultraThinMaterial, for: .navigationBar) +
        // .toolbarBackgroundVisibility(.automatic, for: .navigationBar).
        // (FrostedGlass удалён — см. коммит 9 в native-app.)
        // safeAreaInset, не навбар — явный `.background(.ultraThinMaterial)`,
        // полупрозрачный blur (frosted glass, как в вебе). Иначе шапка
        // сольётся с tfBackground экрана (Claude_Bot приёмка 02.09.2026).
        .background(.ultraThinMaterial)
    }
}
