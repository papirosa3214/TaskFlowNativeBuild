import SwiftUI
import UIKit

// Заголовок экрана — тем же капсом, что и заголовки разделов «Обзора», и по
// центру (12.10.2026, поручение владельца: «все заголовки наверху… тем же
// самым шрифтом, все заглавные… чтобы всё было однородно»).
//
// ПОЧЕМУ ТЕКСТ В TOOLBAR, А НЕ `UINavigationBar.appearance()`.
//
// Сначала было сделано правильно по документации: `UINavigationBarAppearance
// .titleTextAttributes` через прокси `UINavigationBar.appearance()`. На iOS 27
// этот путь НЕ РАБОТАЕТ, и молча, без ошибки сборки:
//
//   * чтение атрибутов сразу после записи возвращает ПУСТОЙ словарь — то
//     есть прокси их вообще не хранит;
//   * «Обход живых навбаров» тоже не помогает: рекурсивный обход
//     `UIWindow.subviews` находит НОЛЬ `UINavigationBar` — на iOS 27 SwiftUI
//     рисует шапку сам, UIKit-навбара в иерархии нет;
//   * проверка «красным» доказала то же самое: заголовок остался серым и с
//     системным шрифтом, и с PT Sans Narrow.
//
// Значит атрибуты просто некуда положить: `navigationTitle` на iOS 27 рисует
// SwiftUI своим шрифтом. Единственный штатный слот, который рисует SwiftUI и
// которым можно задать шрифт — `ToolbarItem(placement: .principal)`. Слот
// системный, фон и блюр остаются прежними (свою шапку не рисуем), меняется
// ТОЛЬКО текст заголовка.
enum TFNavBarTitleFont {
    /// Family — та же гарнитура, что у `.tfSectionDisplay` (PT Sans Narrow,
    /// выбрана владельцем 12.10.2026). В файле family = «PT Sans Narrow», а
    /// Regular/Bold — начертания (name ID 2).
    static let family = "PT Sans Narrow"

    /// Трекинг тот же, что у заголовков разделов: узкая гарнитура рассыпается
    /// на длинных русских словах.
    static let tracking = TFFont.sectionDisplayTracking

    /// Текст заголовка для слота `.principal`.
    ///
    /// Регистр — здесь: у навбара нет атрибута «капс».
    /// Цвет белый (`tfText`), как у заголовков разделов: владелец 12.10.2026
    /// вернул белый и разделам, и шапке после смены гарнитуры на
    /// PT Sans Narrow — с серым капс выглядел вялым.
    static func title(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.custom(family, size: 17).weight(.bold))
            .tracking(tracking)
            .foregroundStyle(Color.tfText)
    }
}

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
    /// Заголовок капсом той же гарнитуры, что и заголовки разделов «Обзора»,
    /// по центру (12.10.2026).
    ///
    /// Текст кладётся в штатный слот `.principal`, потому что на iOS 27
    /// `navigationTitle` рисуется своим системным шрифтом, а атрибуты
    /// `UINavigationBarAppearance` до SwiftUI-заголовка не доходят — подробно
    /// в `TFNavBarTitleFont`. `navigationTitle` остаётся пустым, чтобы не было
    /// дубля текста; параметр `displayMode` оставлен для совместимости вызовов
    /// и не влияет на отрисовку. Режим при этом задаём всегда `.inline`: без
    /// него система оставляла под шапкой пустое место под большой заголовок —
    /// зазор на всех экранах (жалоба владельца 12.10.2026).
    func tfNativeHeader(_ title: String, displayMode: ToolbarTitleDisplayMode = .inline) -> some View {
        self
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TFNavBarTitleFont.title(title)
                }
            }
    }

    /// Единый размер tappable-области для управляющих элементов «Планирования».
    /// Само содержимое остаётся нативными `Menu`/`Picker` в toolbar.
    func tfPlannerToolbarControl() -> some View {
        frame(width: 32, height: 32)
    }
}

struct TFPlannerToolbarIcon: View {
    let systemName: String
    var tint: Color = .tfSub
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: weight))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
    }
}

// Мягкое размытие у верхней кромки прокрутки — то же, что уже стояло в
// почасовой сетке и на доске дня. 15.09.2026: после обновления iOS система
// перестала выбирать мягкий край сама, и под шапкой везде появилась резкая
// граница. Точечные вызовы в двух местах остались единственными, где было
// плавно, — здесь тот же приём выносится в один кирпич на все экраны.
// Своего ничего не рисуем; на iOS до 26 эффекта просто нет.
extension View {
    @ViewBuilder
    func tfSoftTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
