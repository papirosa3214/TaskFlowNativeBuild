import SwiftUI

/// Двойная зелёная галочка рядом с «На проверке»: Критик проверил и одобрил
/// сдачу (владелец 07.10.2026). Нет галочек — Критик её не проверял.
public struct TFCriticApprovedMark: View {
    public init() {}

    public var body: some View {
        ZStack {
            Image(systemName: "checkmark").offset(x: -2.5)
            Image(systemName: "checkmark").offset(x: 2.5)
        }
        .tfTypeFont(size: TFIconSize.xs - 3, weight: .bold)
        .foregroundStyle(Color.tfGreen)
        .padding(.horizontal, 2.5)
        .accessibilityLabel("Критик проверил")
        .accessibilityIdentifier("task.review.criticApproved")
    }
}
