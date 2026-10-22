import SwiftUI

/// Uses the same owner-only settings as the web client. The saved key is never returned.
///
/// Владелец 22.10.2026 (кадр с телефона): карточка жила обычным `List` и
/// выпадала из остальных настроек — системные ячейки бледнее карточек
/// «Настроек», тумблеры на своём фоне, расход рассыпался лесенкой по центру,
/// а под ключом висело непонятное «10000» (тайм-аут в миллисекундах).
/// Теперь экран собран теми же блоками, что пункты настроек: заголовок
/// раздела + `TFCard` с строками `TFListRow` и разделителями. Тайм-аут из
/// вида убран — значение остаётся серверным и уходит при сохранении как есть.
/// Красную кнопку «Сохранить» владелец попросил убрать: она обычная серая.
struct JevSettingsScreen: View {
    @State private var settings: JevSettings?
    @State private var baseUrl = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: JevConnectionResult?
    @State private var confirmReset = false
    @State private var usageRevision = UUID().uuidString
    private let api = APIClient()

    private var dirty: Bool {
        guard let settings else { return false }
        return baseUrl != settings.baseUrl || model != settings.model
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.xl) {
                    TFErrorBanner(error)
                        .accessibilityIdentifier("jev-error")
                    if settings == nil && busy {
                        TFLoading(.block)
                    } else if settings == nil && error != nil {
                        TFButton("Повторить", variant: .secondary, isEnabled: !busy) {
                            Task { await load() }
                        }
                    }
                    if let settings {
                        connection(settings)
                        JevUsageSection(revision: usageRevision)
                        scenarios(settings)
                        if settings.hasApiKey {
                            TFButton("Удалить ключ и сбросить", icon: "trash", variant: .outline, isEnabled: !busy) {
                                confirmReset = true
                            }
                            .accessibilityIdentifier("jev-reset")
                        }
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tfNativeHeader("Оценщик JEV")
        .accessibilityIdentifier("jev-screen")
        .task { await load() }
        .confirmationDialog("Удалить ключ и сбросить настройки JEV? Все сценарии выключатся.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Удалить ключ и сбросить", role: .destructive) { Task { await reset() } }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// Адрес, модель и ключ — строки одной карточки, как поля в настройках
    /// профиля: `TFFieldGroup` с тонкими разделителями между строками.
    private func connection(_ settings: JevSettings) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Подключение")
            TFFieldGroup {
                HStack(spacing: TFSpacing.md) {
                    TextField("", text: $baseUrl,
                              prompt: Text("Адрес API").foregroundStyle(Color.tfDim))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("jev-url")
                    TextField("", text: $model,
                              prompt: Text("Модель").foregroundStyle(Color.tfDim))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("jev-model")
                }
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .padding(.horizontal, TFSpacing.lg)
                .frame(minHeight: TFField.height)
                TFFieldDivider()
                SecureField("", text: $apiKey,
                            prompt: Text(settings.hasApiKey ? "Ключ сохранён — новый заменит" : "Ключ API TypeSafe")
                                .foregroundStyle(Color.tfDim))
                    .tfText(.input)
                    .foregroundStyle(Color.tfText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, TFSpacing.lg)
                    .frame(minHeight: TFField.height)
                    .accessibilityLabel("Ключ API").accessibilityIdentifier("jev-key")
            }
            HStack(spacing: TFSpacing.sm) {
                TFButton("Сохранить", variant: .secondary, isEnabled: dirty && !busy) {
                    Task { await saveConnection() }
                }
                .accessibilityIdentifier("jev-save")
                .frame(maxWidth: .infinity)
                TFButton("", icon: "arrow.clockwise", variant: .secondary,
                         isEnabled: settings.hasApiKey && !dirty && !busy) {
                    Task { await test() }
                }
                .accessibilityIdentifier("jev-test")
                .accessibilityLabel("Проверить подключение")
            }
            if busy { ProgressView("Подождите…") }
            if let result {
                Text(result.message).tfText(.action).foregroundStyle(Color.tfSub)
                    .accessibilityIdentifier("jev-test-result")
            }
            Text("Ключ хранится на сервере. Проверка использует сохранённые настройки.")
                .tfText(.action).foregroundStyle(Color.tfSub)
        }
        .hintAnchor(HintAnchorID.jevConnection)
    }

    @ViewBuilder private func scenarios(_ settings: JevSettings) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader("Где использовать")
            if !settings.hasApiKey {
                Text("Сначала сохраните ключ — без него галочки не включаются.")
                    .tfText(.action).foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.screenHorizontal)
            }
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    scenario("Выбор шаблона плана", id: "plan",
                             enabled: settings.planProfileEnabled,
                             description: "Когда карточке предлагается командный план, JEV выбирает готовый состав: один исполнитель, исследование, поставка или полный цикл. Без него шаблон выбирается по словам в названии.") { .init(planProfileEnabled: $0) }
                    TFDivider(inset: rowDividerInset)
                    scenario("Роли для подзадач", id: "roles",
                             enabled: settings.subtaskRoleEnabled,
                             description: "JEV читает карточку целиком и решает, какой роли отдать подзадачу и стоит ли выносить её отдельно. Мелкие пункты остаются исполнителю карточки. Если JEV не уверен, роль подбирается как раньше, по смыслу текста.") { .init(subtaskRoleEnabled: $0) }
                    TFDivider(inset: rowDividerInset)
                    scenario("Отбор памяти для роли", id: "recall",
                             enabled: settings.memoryRecallEnabled,
                             description: "Перед ходом роли JEV проверяет до 15 найденных записей: уверенно ненужные убирает, полезные ставит вперёд. Закреплённые не трогает. Ждёт не дольше 3 секунд — иначе память идёт как раньше.") { .init(memoryRecallEnabled: $0) }
                    TFDivider(inset: rowDividerInset)
                    scenario("Проверка записи в память", id: "write",
                             enabled: settings.memoryWriteEnabled,
                             description: "Проверяет, что факт, урок или предпочтение роли — знание на будущее. Уверенно ненужные записи не сохраняются, роль получает объяснение. Ваши собственные записи не проверяются.") { .init(memoryWriteEnabled: $0) }
                    TFDivider(inset: rowDividerInset)
                    scenario("Навыки под задачу", id: "skills",
                             enabled: settings.skillsEnabled,
                             description: "У ролей с числом навыков больше шести JEV отбирает нужные карточке и текущему шагу. Если ничего не выбрал или не ответил, роль получает все навыки.") { .init(skillsEnabled: $0) }
                }
            }
        }
    }

    /// Строка тумблера в ритме «Настроек»: название и тумблер в одной строке,
    /// пояснение — абзацем под ней у левого края. `TFListRow` здесь не годится:
    /// его подпись обрезается одной строкой, а пояснения сценариев длинные.
    private func scenario(_ title: String, id: String, enabled: Bool, description: String,
                          patch: @escaping (Bool) -> JevSettingsPatch) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(spacing: TFSpacing.md) {
                Text(title).tfText(.action).foregroundStyle(Color.tfText)
                Spacer(minLength: 0)
                TFToggle(isOn: Binding(get: { enabled }, set: { value in Task { await save(patch(value), updateDraft: false) } }))
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("jev-scenario-\(id)")
            }
            Text(description)
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .disabled(busy || settings?.hasApiKey != true)
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg }

    private func apply(_ value: JevSettings, updateDraft: Bool) {
        settings = value
        usageRevision = UUID().uuidString
        if updateDraft {
            baseUrl = value.baseUrl; model = value.model
            apiKey = ""
        }
    }
    @MainActor private func load() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { apply(try await api.jevSettings(), updateDraft: true) }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    @MainActor private func saveConnection() async {
        // Тайм-аут из вида убран, но серверное значение сохраняется: карточка
        // его не меняет, а не прислать его — значит сбросить чужую настройку.
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        await save(.init(baseUrl: baseUrl, model: model,
                         timeoutMs: settings?.timeoutMs ?? 10_000,
                         apiKey: key.isEmpty ? nil : key), updateDraft: true)
    }
    @MainActor private func save(_ patch: JevSettingsPatch, updateDraft: Bool) async {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        defer { busy = false }
        do { apply(try await api.saveJevSettings(patch), updateDraft: updateDraft) }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func test() async {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        defer { busy = false }
        do { result = try await api.testJevConnection() }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func reset() async {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        defer { busy = false }
        do { apply(try await api.resetJevSettings(), updateDraft: true) }
        catch { self.error = error.localizedDescription }
    }
}
