import SwiftUI

/// Чем кончился ход роли, пока владелец не открыл комнату (владелец
/// 27.10.2026): зелёная — ответ пришёл, жёлтая — ход отвалился, красная —
/// кончился лимит. Одна точка на строке списка и на аватарке боковой панели.
struct RoomTurnOutcomeDot: View {
    let outcome: RoomTurn.Outcome
    var diameter: CGFloat = 10
    /// Обводка цветом фона — когда точка лежит на аватарке.
    var ringed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .overlay { if ringed { Circle().strokeBorder(Color.tfBackground, lineWidth: 2) } }
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch outcome {
        case .answered: Color.tfGreen
        case .failed: Color.tfYellow
        case .limit: Color.tfRedSolid
        }
    }

    var label: String {
        switch outcome {
        case .answered: "Ответ пришёл"
        case .failed: "Ход отвалился, ответа нет"
        case .limit: "Кончился лимит"
        }
    }
}
