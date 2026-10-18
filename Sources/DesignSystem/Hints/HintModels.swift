import Foundation

/// Режим подсказок (владелец 16.10.2026): пошаговое обучение поверх
/// настоящего интерфейса. Сценарий — список шагов; шаг привязан к элементу
/// через `.hintAnchor(_:)` и может ветвиться по выбору владельца.
/// Новая функция — новая подсказка: шаги добавляются в `HintScenarios`.
struct HintScenario: Identifiable, Equatable {
    let id: String
    let title: String
    /// Шаг, с которого сценарий начинается.
    let start: String
    let steps: [String: HintStep]
}

struct HintStep: Equatable {
    /// Элемент, который подсвечивается. Нет на экране — карточка подсказки
    /// всё равно видна и говорит, где его открыть.
    let anchor: String?
    let title: String
    let text: String
    /// Ветки «выберешь это — будет так-то». Пусто — одна кнопка «Дальше».
    var branches: [HintBranch] = []
    /// Куда идти по «Дальше» или по нажатию на подсвеченный элемент.
    /// nil — сценарий закончен.
    var next: String? = nil
    /// Нажатие на подсвеченный элемент само ведёт к `next`.
    var advancesOnTap: Bool = false
    /// Имя Markdown-файла в ресурсах приложения, доступного из этой подсказки.
    var documentationResource: String? = nil
}

struct HintBranch: Equatable, Identifiable {
    var id: String { title }
    let title: String
    /// Шаг, к которому ведёт выбор; nil — закончить сценарий.
    let next: String?
}
