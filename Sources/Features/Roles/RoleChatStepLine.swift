import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

/// «Разработчик печатает…» с анимированными точками — показывается только
/// по сигналу сервера, пока роль действительно готовит ответ (22.09.2026).
struct RoleChatTypingLine: View {
    let names: [String]

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Text(text)
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    TypingDot(delay: Double(i) * TFAnimation.typingDotPhaseShift)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var text: String {
        if names.count == 1 { return "\(names[0]) печатает" }
        return "\(names.dropLast().joined(separator: ", ")) и \(names.last ?? "") печатают"
    }
}

/// Подпись/иконка по имени инструмента с сервера — сервер имя не
/// интерпретирует, это целиком презентационная таблица клиента.
enum RoleStepPresentation {
    static func label(forTool tool: String) -> String { RoleActionPresentation.forTool(tool).title }
    static func symbol(forTool tool: String) -> String { RoleActionPresentation.forTool(tool).symbol }
}

/// Строка «роль делает шаг прямо сейчас» — замена `RoleChatTypingLine`
/// в 1:1-чате, когда для роли пришёл `tool`. По мотивам референсного
/// AgentActivityFeed (26.09.2026, брейнсторм с владельцем).
struct RoleStepLine: View {
    let name: String
    let tool: String

    var body: some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: RoleStepPresentation.symbol(forTool: tool))
                .tfTypeFont(size: 13, weight: .medium)
                .foregroundStyle(Color.tfSub)
                .symbolEffect(.pulse, options: .repeating)
            Text("\(name): \(RoleStepPresentation.label(forTool: tool))")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(RoleStepPresentation.label(forTool: tool))")
    }
}
