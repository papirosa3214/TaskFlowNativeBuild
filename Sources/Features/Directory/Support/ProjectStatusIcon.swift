import SwiftUI

// Значок статуса проекта («В работе», «На проверке», «Заблокировано»,
// «Пропали»). Живёт в «Справочниках», рядом с `ProjectCard`, который его
// рисует. Раньше он был объявлен в `AgentStatusGrid.swift` — рядом с
// мёртвой сеткой плиток «Обзора»; при удалении того файла значок переехал
// сюда, потому что карточка проекта живая и значок нужен ей.
struct ProjectStatusIcon: View {
    enum Kind { case running, review, blocked, stale }
    let kind: Kind

    /// Значок статуса — по кеглю строки, в которой он живёт, а не отдельной
    /// рамкой 21pt (владелец 11.10.2026: «глазки и треугольники совсем
    /// здоровые»). Раньше значок был больше собственного текста с цифрой и
    /// в строке карточки проекта читался как самостоятельный элемент.
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch kind {
            case .running:
                // Владелец 11.10.2026: «крутилку замени на то, что и было, типа
                // плей в кружочке». На этом месте стоял
                // `TFSubtaskStatusRing(.running)` — вращающиеся 12 точек.
                // Тот же значок «в работе», что уже стоит в фильтре проектов
                // (`ProjectFilter.inWork`): play.circle.fill.
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.tfTeal)
            case .review:
                // Фигура и цвет как у `TFSubtaskStatusRing(.review)`, но своего
                // кегля: тот жёстко зашит на 21pt (`TFCheckbox.swift:138`) и
                // перебивал внешний `.frame`, из-за чего в строке карточки
                // значок был больше цифры рядом. Сам `TFSubtaskStatusRing` не
                // трогаем — он общий для чекбоксов подзадач.
                Image(systemName: "eye")
                    .foregroundStyle(Color.tfBlue)
            case .blocked:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.tfOrange)
            case .stale:
                ZStack {
                    Image(systemName: "triangle")
                    Image(systemName: "xmark").font(.system(size: size * 0.4, weight: .bold)).offset(y: size * 0.1)
                }.foregroundStyle(Color.tfRed)
            }
        }
        .font(.system(size: size))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
