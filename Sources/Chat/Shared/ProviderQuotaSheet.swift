import SwiftUI

/// Остаток лимитов у провайдеров — по кнопке прямо из чата (владелец
/// 12.10.2026: «в чате прикрути иконку, чтобы я мог нажать и сразу увидеть
/// лимиты все»).
///
/// Показывает провайдеров, которые остаток сообщают (MiniMax, OpenCode Go).
/// Те, кто не сообщает, сюда не попадают: молчаливая строка «не знаю» хуже
/// отсутствия.
struct ProviderQuotaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: FailoverStatus?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.md) {
                    if let errorText {
                        Text(errorText).tfText(.action).foregroundStyle(Color.tfRed)
                    } else if let status, !status.quotas.isEmpty {
                        quotaRows(status.quotas)
                    } else {
                        Text("Остаток никто не сообщает — лимиты определяются по факту отказа провайдера.")
                            .tfText(.action).foregroundStyle(Color.tfSub)
                    }
                }
                .padding(TFSpacing.lg)
            }
            .tfScreenBackground()
            .tfNativeHeader("Лимиты провайдеров", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Обновить лимиты")
                }
            }
            .task { await load() }
        }
    }

    private func quotaRows(_ quotas: [ProviderQuotaState]) -> some View {
        VStack(spacing: TFSpacing.sm) {
            ForEach(quotas) { quota in
                TFCard {
                    HStack(spacing: TFSpacing.md) {
                        Circle()
                            .fill(quota.limited ? Color.tfOrange : Color.tfGreen)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(quota.provider).tfText(.body).foregroundStyle(Color.tfText)
                            Text(FailoverSettingsSection.quotaSubtitle(quota))
                                .tfText(.action)
                                .foregroundStyle(quota.limited ? Color.tfOrange : Color.tfSub)
                            if let detail = quota.detail, !detail.isEmpty {
                                Text(detail).tfText(.meta).foregroundStyle(Color.tfDim)
                            }
                        }
                        Spacer(minLength: TFSpacing.sm)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("chat.quota.\(quota.provider)")
            }
        }
    }

    private func load() async {
        do {
            status = try await APIClient().failoverStatus()
            errorText = nil
        } catch {
            errorText = "Не удалось получить лимиты: \(error.localizedDescription)"
        }
    }
}