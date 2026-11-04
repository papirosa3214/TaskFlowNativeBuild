import SwiftUI

/// Два общих тумблера и статус лимитов (владелец 07.10.2026): автопереключение
/// при лимите, автовозврат на основную модель, «какой провайдер сейчас в лимите
/// и когда вернётся» с кнопкой «Вернуть сейчас». Тот же блок в вебе.
struct FailoverSettingsSection: View {
    @Bindable var viewModel: RoleModelsViewModel

    var body: some View {
        if let status = viewModel.failover {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                // Остаток лимита у провайдера — владелец 12.10.2026: «в лёгкую
                // можно видеть остатки на панели провайдера, а у нас не
                // отображается». Сервер теперь спрашивает остаток сам и
                // отдаёт его здесь; провайдеры, которые остаток не отдают,
                // в список не попадают.
                if !status.quotas.isEmpty {
                    TFSectionHeader("Остаток лимитов")
                    quotaCard(status.quotas)
                }
                TFSectionHeader("Автопереключение моделей")
                TFCard(padding: 0, bordered: true) {
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
                        ForEach(status.keyProblems ?? []) { problem in
                            TFDivider(inset: TFSpacing.lg)
                            keyRow(problem)
                        }
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
        // Эталонный переключатель проекта (уменьшенный, как в остальных настройках).
        HStack(spacing: TFSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tfText(.action).foregroundStyle(Color.tfText)
                Text(subtitle).tfText(.caption).foregroundStyle(Color.tfSub)
            }
            Spacer(minLength: TFSpacing.sm)
            TFToggle(isOn: Binding(get: { isOn }, set: onChange))
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
    }

    /// Остаток по каждому провайдеру, который его сообщает: зелёный — живой,
    /// оранжевый — в лимите, с точным временем сброса от провайдера.
    private func quotaCard(_ quotas: [ProviderQuotaState]) -> some View {
        TFCard(padding: 0, bordered: true) {
            VStack(spacing: 0) {
                ForEach(Array(quotas.enumerated()), id: \.element.id) { index, quota in
                    if index > 0 { TFDivider(inset: TFSpacing.lg) }
                    HStack(spacing: TFSpacing.md) {
                        Circle()
                            .fill(quota.limited ? Color.tfOrange : Color.tfGreen)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quota.provider).tfText(.action).foregroundStyle(Color.tfText)
                            Text(Self.quotaSubtitle(quota))
                                .tfText(.caption)
                                .foregroundStyle(quota.limited ? Color.tfOrange : Color.tfSub)
                        }
                        Spacer(minLength: TFSpacing.sm)
                    }
                    .padding(.horizontal, TFSpacing.lg)
                    .frame(minHeight: TFField.height)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("quota.\(quota.provider)")
                }
            }
        }
    }

    static func quotaSubtitle(_ quota: ProviderQuotaState) -> String {
        guard quota.known else { return "остаток не сообщает" }
        guard quota.limited else { return "лимит есть, работает" }
        if let minutes = quota.minutesToReset {
            return "в лимите, сброс через \(minutes) мин"
        }
        return "в лимите, время сброса неизвестно"
    }

    /// Нерабочий ключ (20.10.2026): лимит пройдёт сам, а ключ — нет, нужен повторный вход
    /// в «Провайдерах» ниже. До тех пор роли на этом провайдере падают.
    private func keyRow(_ problem: ProviderKeyProblem) -> some View {
        HStack(spacing: TFSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(RuntimeModel.providerTitle(problem.provider)): \(problem.reason)")
                    .tfText(.action).foregroundStyle(Color.tfText)
                Text("переподключите провайдера ниже — само не пройдёт")
                    .tfText(.caption).foregroundStyle(Color.tfOrange)
            }
            Spacer(minLength: TFSpacing.sm)
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: TFField.height)
        .accessibilityElement(children: .combine)
    }

    private func limitRow(_ limit: FailoverLimit) -> some View {
        HStack(spacing: TFSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(RuntimeModel.providerTitle(limit.provider)) в лимите").tfText(.action).foregroundStyle(Color.tfText)
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
