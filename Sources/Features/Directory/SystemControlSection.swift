import SwiftUI
import Observation
import os

// Управление системой на «Обзоре» — две ручки владельца рядом.
//
// Владелец 14.09.2026, дословно: «это по сути вся система, она либо
// включена, либо выключена, и соответственно её режим — либо ручной, либо
// автомат». Поэтому здесь нет ни «будильника» (`taskflow-trigger`), ни
// «службы», ни «intake»: внутренние слова на экран не выносятся, владелец
// видит состояние и режим.
//
// ПОЧЕМУ ОБЕ ВМЕСТЕ И ПОЧЕМУ НА «ОБЗОРЕ». Раньше включение жило в
// «Настройки → Сервер» строкой «Будильник (служба)», а режима постановки в
// приложении не было вовсе — он существовал только серверной ручкой. Порознь
// они вводят в заблуждение: «Автомат» при выключенной системе выглядит
// работающим, хотя карточка уйдёт исполнителю, а звать его будет некому.
// Рядом на стартовом экране это видно одним взглядом.
//
// Обе ручки owner-only на сервере (`/api/agent-service`,
// `/api/task-intake/settings` отвечают 403 остальным), поэтому не владельцу
// секция не показывается вовсе — мёртвых переключателей в интерфейсе быть
// не должно. Транспорт — `APIClient+SystemControl.swift` в `Core`.

@MainActor
@Observable
final class SystemControlViewModel {
    private let api: APIClient
    private let log = Logger(subsystem: "TaskFlow", category: "system-control")

    /// Состояние обеих ручек читается ОТДЕЛЬНО и может быть неизвестным.
    /// Это не педантизм: показать выключённый тумблер там, где мы просто не
    /// дозвонились до сервера, — соврать владельцу. Он решит, что систему
    /// кто-то остановил, и полезет включать уже включённое.
    private(set) var isSystemOn = false
    private(set) var isSystemStateKnown = false
    private(set) var isTogglingSystem = false

    private(set) var mode: TaskIntakeMode = .manual
    private(set) var isModeKnown = false
    private(set) var isSavingMode = false

    /// Показывается только на собственное действие владельца. Неудачное
    /// чтение состояния его не касается — он ничего не трогал, и ругаться
    /// на него за молчащий сервер незачем.
    var errorMessage: String?

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func load() async {
        // `try?` здесь был бы проглоченной ошибкой: в логе пусто, на экране
        // «выключено», и разбираться потом не с чем.
        do {
            isSystemOn = try await api.fetchSystemRunState().active
            isSystemStateKnown = true
        } catch {
            log.error("не удалось прочитать состояние системы: \(error.localizedDescription, privacy: .public)")
        }
        do {
            mode = try await api.fetchTaskIntakeSettings().mode
            isModeKnown = true
        } catch {
            log.error("не удалось прочитать режим постановки: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setSystemOn(_ on: Bool) async {
        guard isSystemStateKnown, on != isSystemOn, !isTogglingSystem else { return }
        let confirmed = isSystemOn
        isSystemOn = on
        isTogglingSystem = true
        errorMessage = nil
        defer { isTogglingSystem = false }
        do {
            isSystemOn = try await api.setSystemRunning(on).active
        } catch {
            // Откат ровно к подтверждённому значению: оптимистичный показ
            // допустим только тогда, когда отказ его честно отменяет.
            isSystemOn = confirmed
            errorMessage = on ? "Не удалось включить систему" : "Не удалось выключить систему"
            log.error("переключение системы отклонено: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setMode(_ newMode: TaskIntakeMode) async {
        guard isModeKnown, newMode != mode, !isSavingMode else { return }
        let confirmed = mode
        mode = newMode
        isSavingMode = true
        errorMessage = nil
        defer { isSavingMode = false }
        do {
            mode = try await api.updateTaskIntakeMode(newMode).mode
        } catch {
            mode = confirmed
            errorMessage = "Не удалось сменить режим"
            log.error("смена режима отклонена: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct SystemControlSection: View {
    @State private var viewModel = SystemControlViewModel()

    // Строки собраны ровно теми же кирпичами, что и «Пользовательские
    // настройки» (`SettingsScreen.toggleRow`): `TFListRow` с plain-иконкой
    // 40×40, `titleStyle: .action`, `verticalPadding: TFSpacing.xs` и
    // `TFToggle` в `trailing`. Голый системный `Toggle` с меткой, который
    // стоял здесь сначала, был полноразмерным и синим — в приложении
    // тумблеры уменьшены до 0.82 и красные (`TFToggle`), поэтому строка
    // выбивалась и высотой, и цветом из всех соседних.
    var body: some View {
        TFCard(padding: 0) {
            VStack(spacing: 0) {
                TFListRow(
                    icon: "power", iconStyle: .plain,
                    title: "Система",
                    subtitle: systemSubtitle,
                    trailing: AnyView(TFToggle(isOn: systemBinding)
                        .disabled(!viewModel.isSystemStateKnown || viewModel.isTogglingSystem)),
                    titleStyle: .action,
                    verticalPadding: TFSpacing.xs
                )
                TFDivider(inset: rowDividerInset)
                TFListRow(
                    icon: "slider.horizontal.3", iconStyle: .plain,
                    title: "Режим",
                    subtitle: modeSubtitle,
                    trailing: AnyView(TFToggle(isOn: automaticBinding)
                        .disabled(!viewModel.isModeKnown || viewModel.isSavingMode)),
                    titleStyle: .action,
                    verticalPadding: TFSpacing.xs
                )
                if viewModel.errorMessage != nil {
                    TFErrorBanner(viewModel.errorMessage)
                        .padding(.horizontal, TFSpacing.lg)
                        .padding(.bottom, TFSpacing.sm)
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 40 + TFSpacing.md }

    // Заголовок строки ПОСТОЯННЫЙ («Система», «Режим»), состояние живёт в
    // подписи и в самом тумблере: меняющийся заголовок читался бы двояко —
    // это текущее положение или то, что случится по нажатию.
    //
    // Подписи короткие намеренно: `TFListRow` режет subtitle в одну строку
    // (`lineLimit(1)`), длинная фраза оборвалась бы многоточием.

    /// Пока состояние не прочитано — говорим об этом прямо. Показать
    /// «Остановлена» там, где мы просто не дозвонились до сервера, — соврать
    /// владельцу: он решит, что систему кто-то выключил, и полезет включать.
    private var systemSubtitle: String {
        guard viewModel.isSystemStateKnown else { return "Нет связи с сервером" }
        return viewModel.isSystemOn ? "Работает" : "Остановлена"
    }

    /// Подпись говорит, что случится с надиктовкой: «Ручной» и «Автомат»
    /// сами по себе о последствии не сообщают.
    private var modeSubtitle: String {
        guard viewModel.isModeKnown else { return "Нет связи с сервером" }
        return viewModel.mode == .automatic ? "Автомат, без подтверждения" : "Ручной, ждёт вашего флага"
    }

    private var systemBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isSystemOn },
            set: { on in Task { await viewModel.setSystemOn(on) } }
        )
    }

    private var automaticBinding: Binding<Bool> {
        Binding(
            get: { viewModel.mode == .automatic },
            set: { isAutomatic in Task { await viewModel.setMode(isAutomatic ? .automatic : .manual) } }
        )
    }
}
