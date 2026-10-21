import SwiftUI

// Пастельная иллюстрация пустого списка «Сегодня» в Планировании.
// По просьбе владельца 18.10.2026: чисто картинка фоном, без подписей,
// без заголовка, без иконок. TodayListView выбирает картинку по активной
// вкладке списка (inbox/attention/today). Старые вызовы без аргумента
// оставлены на дефолте —
// пёс с чек-листом, покрывает основной случай `trueEmpty` для всего экрана.
//
// `allowsHitTesting(false)` обязателен: иллюстрация лежит под ScrollView
// как фон, и без этого флага она глотала бы тапы в своей зоне, из-за чего
// свайп переключения вкладок «из Сегодня вправо» не срабатывал на пустой
// ленте (тот же симптом, что уже описан у ZStack-подложки в TodaySectionView).
struct TodayEmptyIllustration: View {
    let image: Image

    init(image: Image = Image("EmptyPlannerToday")) {
        self.image = image
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            // Кремовые заливки (#EDE8DE) на тёмном фоне слепят: в тёмной теме
            // белое приглушено до нашего серого `tfSub` (владелец 20.10.2026).
            .colorMultiply(colorScheme == .dark ? Color.tfSub : .white)
            .padding(.horizontal, TFSpacing.xl)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}