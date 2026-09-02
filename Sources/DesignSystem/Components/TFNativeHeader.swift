import SwiftUI

// Штатная шапка экрана — один модификатор вместо повторения одного и того
// же набора на каждом экране (было причиной расхождений: где-то забыли
// toolbarBackground, где-то остался дубль текста заголовка рядом со старым
// TFScreenHeader). Заменяет самодельные TFScreenHeader/FrostedGlass/
// SettingsHeaderChrome/DirectoryCompactHeader — AUD-001, AUD-002.
//
// `toolbarTitleDisplayMode(_:)` — iOS 17+, кросс-платформенный аналог
// `navigationBarTitleDisplayMode` (тот депрекейтнут на iOS 27, но пока
// сосуществует — см. TaskFlow__swiftui-navbar-api-2026-09-02.md).
//
// Фон/блюр навбара НЕ задаём сами: на iOS 26 (наш deploymentTarget) система
// сама рисует scroll edge effect — тот самый размывающий эффект, который
// включается по скроллу и остаётся легибельным поверх любого контента
// (WWDC25 «What's new in SwiftUI»: «a scroll view renders an automatic edge
// effect» — без единой строчки кода). Раньше здесь стояли
// `.toolbarBackground(.ultraThinMaterial, for:)` и
// `.toolbarBackgroundVisibility(.automatic, for:)` — это была наша ручная
// имитация того, что система уже даёт по умолчанию: в примерах Apple
// `toolbarBackground` с Material вообще не встречается, только со сплошным
// цветом. Владелец 02.09.2026 отдельно указал: заменить самодельное на
// native — значит убрать самодельное, а не имитировать его native-вызовами.
extension View {
    func tfNativeHeader(_ title: String, displayMode: ToolbarTitleDisplayMode = .large) -> some View {
        self
            .navigationTitle(title)
            .toolbarTitleDisplayMode(displayMode)
    }
}
