import SwiftUI

/// Action bar — нижняя панель с допустимым действием по `Resolution.action`.
/// UX-документ §2: фиксированная внизу, ≤ 56 пт. Если `action == none`
/// или `no_action` — панель показывает «Нет действия для этого шага».
public struct ActionBar: View {
    public let resolution: APIClient.CoordinationResolution?
    public let blockedByVersionMismatch: Bool
    public let onAction: (CoordinationAction) -> Void

    public init(
        resolution: APIClient.CoordinationResolution?,
        blockedByVersionMismatch: Bool = false,
        onAction: @escaping (CoordinationAction) -> Void
    ) {
        self.resolution = resolution
        self.blockedByVersionMismatch = blockedByVersionMismatch
        self.onAction = onAction
    }

    public var body: some View {
        HStack(spacing: TFSpacing.sm) {
            if blockedByVersionMismatch {
                versionWarning
            } else if let action = primaryAction {
                actionButton(for: action)
            } else {
                noActionLabel
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TFSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
        .background(Color.tfCard2)
        .overlay(
            Rectangle()
                .frame(height: TFBorder.width)
                .foregroundStyle(Color.tfSub.opacity(0.25)),
            alignment: .top
        )
        .accessibilityIdentifier("coord.action.bar")
    }

    private var primaryAction: CoordinationAction? {
        guard let cause = resolution?.causeEnum else { return nil }
        // `unknown` показывает кнопку «Обновить», которая идёт через
        // Reason strip. Здесь — только реальное действие.
        return cause.actionCode
    }

    @ViewBuilder
    private func actionButton(for action: CoordinationAction) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: TFSpacing.xs) {
                Image(systemName: symbol(for: action))
                    .font(.system(size: 14, weight: .semibold))
                Text(action.label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, TFSpacing.md)
            .frame(height: 40)
            .background(actionTint(action))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coord.action.btn")
        .accessibilityLabel(action.label)
    }

    private var versionWarning: some View {
        HStack(spacing: TFSpacing.xs) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(Color.orange)
            Text("Сервер обновился, обновите приложение")
                .font(.system(size: 12))
                .foregroundStyle(Color.tfText)
        }
    }

    private var noActionLabel: some View {
        Text("Нет действия для этого шага")
            .font(.system(size: 12))
            .foregroundStyle(Color.tfSub)
            .accessibilityIdentifier("coord.action.none")
    }

    private func actionTint(_ action: CoordinationAction) -> Color {
        switch action {
        case .start, .replaceAttempt, .acceptReview, .pickUpAfterReview:
            return Color.tfRed
        case .askOwner, .switchRole, .fixConfig, .switchProvider:
            return Color(red: 0.45, green: 0.28, blue: 0.72)
        default:
            return Color.tfSub
        }
    }

    private func symbol(for action: CoordinationAction) -> String {
        switch action {
        case .start: return "play.fill"
        case .waitPredecessor: return "hourglass"
        case .liftDependency: return "arrow.up.right.circle"
        case .askOwner: return "questionmark.bubble"
        case .switchRole: return "person.crop.circle.badge.exclamationmark"
        case .retryWithDelay: return "arrow.clockwise.circle"
        case .replaceAttempt: return "arrow.counterclockwise"
        case .switchProvider: return "arrow.triangle.swap"
        case .fixConfig: return "wrench.and.screwdriver"
        case .acceptReview: return "checkmark.seal"
        case .runFinalReview: return "eye.circle"
        case .pickUpAfterReview: return "arrow.uturn.forward.circle"
        case .noAction, .none: return "minus.circle"
        }
    }
}