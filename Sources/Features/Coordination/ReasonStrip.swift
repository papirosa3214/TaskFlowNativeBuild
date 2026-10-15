import SwiftUI

/// Reason strip — однострочное объяснение «почему не двигается» + assignee.
/// Тап раскрывает детальный sheet с полным `Resolution`.
///
/// UX-документ (§2): фиксированная высота ≤ 64 пт, сворачивается в чип,
/// детали в modal bottom sheet 75% экрана.
public struct ReasonStrip: View {
    public let resolution: APIClient.CoordinationResolution?
    public let loadState: CoordinationState.LoadState
    public let lastUpdatedAt: Date?
    public let onShowDetails: () -> Void
    public let onRefresh: () -> Void

    public init(
        resolution: APIClient.CoordinationResolution?,
        loadState: CoordinationState.LoadState,
        lastUpdatedAt: Date?,
        onShowDetails: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.resolution = resolution
        self.loadState = loadState
        self.lastUpdatedAt = lastUpdatedAt
        self.onShowDetails = onShowDetails
        self.onRefresh = onRefresh
    }

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Button(action: onShowDetails) {
            HStack(spacing: TFSpacing.sm) {
                causeIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let assignee = resolution?.assignee {
                    AssigneeChip(assignee: assignee)
                }
                if isStale {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.orange)
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.tfSub)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coord.reason.refresh")
                .accessibilityLabel("Обновить")
            }
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.sm)
            .background(Color.tfCard2)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coord.reason.strip")
        .accessibilityLabel("Причина: \(titleText). \(subtitleText)")
    }

    private var titleText: String {
        if let cause = resolution?.causeEnum { return cause.title }
        switch loadState {
        case .idle: return "Загружаем…"
        case .loading: return "Загружаем…"
        case .loaded: return "Нет активных причин"
        case .failed: return "Не удалось получить статус"
        case .versionMismatch(let d): return d
        }
    }

    private var subtitleText: String {
        if let hint = resolution?.causeEnum.hint { return hint }
        if let updated = lastUpdatedAt {
            return "обновлено " + Self.relativeTime(updated)
        }
        return "Тап для деталей"
    }

    private var causeIcon: some View {
        let tint = resolution?.causeEnum.tint ?? .unknownGray
        return Image(systemName: tint.symbol ?? "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint.color(for: colorScheme))
            .frame(width: 28, height: 28)
            .background(tint.color(for: colorScheme).opacity(0.12))
            .clipShape(Circle())
    }

    private var isStale: Bool {
        if case .failed = loadState { return true }
        if case .versionMismatch = loadState { return true }
        return false
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Чип исполнителя в Reason strip. `kind=person` → `@имя`,
/// `kind=role` → название роли.
public struct AssigneeChip: View {
    public let assignee: APIClient.CoordinationAssignee

    public init(assignee: APIClient.CoordinationAssignee) {
        self.assignee = assignee
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.tfText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.tfCard)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.tfSub.opacity(0.35), lineWidth: 0.5))
    }

    private var label: String {
        switch assignee.kind {
        case "person": return "@\(shortName(assignee.key))"
        case "role": return assignee.key.capitalized
        default: return assignee.key
        }
    }

    private func shortName(_ id: String) -> String {
        // На карточке владельца виден короткий id. Если есть префикс
        // (UUID/число), обрезаем до 6 символов.
        String(id.prefix(6))
    }
}