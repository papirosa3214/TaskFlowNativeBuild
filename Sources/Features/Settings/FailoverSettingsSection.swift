import SwiftUI

/// Два общих тумблера и статус лимитов (владелец 07.10.2026): автопереключение
/// при лимите, автовозврат на основную модель, «какой провайдер сейчас в лимите
/// и когда вернётся» с кнопкой «Вернуть сейчас». Тот же блок в вебе.
struct FailoverSettingsSection: View {
    @Bindable var viewModel: RoleModelsViewModel

    var body: some View {
        if let status = viewModel.failover {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                TFSectionHeader("Автопереключение моделей")
                TFCard(padding: 0) {
                    VStack(spacing: 0) {
                        toggleRow(
                            title: "Автопереключение при лимите",
                            subtitle: "упёрлась в лимит — идёт на следующую модель цепочки",
                            isOn: status.autoSwitch
                        ) { value in Task { await viewModel.setFailover(autoSwitch: value) } }
                        TFDivider(inset: TFSpacing.lg)
                        toggleRow(
                            title: "Автовозврат на основную",
                            subtitle: "лимит сбросился — снова основная модель",
                            isOn: status.autoReturn
                        ) { value in Task { await viewModel.setFailover(autoReturn: value) } }
                        ForEach(status.limits) { limit in
                            TFDivider(inset: TFSpacing.lg)
                            limitRow(limit)
                        }
                    }
                }
            }
        }
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tfText(.action).foregroundStyle(Color.tfText)
                Text(subtitle).tfText(.caption).foregroundStyle(Color.tfSub)
            }
        }
        .tint(Color.tfRed)
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
    }

    private func limitRow(_ limit: FailoverLimit) -> some View {
        HStack(spacing: TFSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(limit.provider) в лимите").tfText(.action).foregroundStyle(Color.tfText)
                Text(limit.held ? "вернётся только по вашей кнопке" : "вернётся после \(Self.clock(limit.until))")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfOrange)
            }
            Spacer(minLength: TFSpacing.sm)
            Button("Вернуть сейчас") { Task { await viewModel.release(limit.provider) } }
                .tfText(.action)
                .foregroundStyle(Color.tfRed)
                .frame(minHeight: 44)
                .disabled(viewModel.busy != nil)
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
    }

    /// Время из UTC-строки SQLite («2026-10-07 01:45:00») — часы по Москве, без «через N минут».
    static func clock(_ utc: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = parser.date(from: utc) else { return utc }
        let out = DateFormatter()
        out.locale = Locale(identifier: "ru_RU")
        out.timeZone = TimeZone(identifier: "Europe/Moscow")
        out.dateFormat = Calendar.current.isDate(date, inSameDayAs: Date()) ? "HH:mm" : "d MMM, HH:mm"
        return out.string(from: date)
    }
}
