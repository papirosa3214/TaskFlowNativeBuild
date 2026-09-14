import SwiftUI
import UIKit
import PhotosUI
import SDWebImageSwiftUI

// MARK: - Состояние раскрытия карточки агента
//
// Тап по строке (LOCK-146) — раскрывает под строкой панель со всей
// информацией из `ApiUser` (роль, тип, активность, лимиты, время создания,
// последний визит, создатель, флаг системного бота, три аватарки) +
// редактируемое поле API-токена под глазиком + реальные серверные секции
// «Модель», «Промпт», «Инструменты (Composio / MCP)», «Скиллы», «Права».
//
// «…» с меню «Изменить»/«Удалить» (LOCK-083) переехало из строки
// в раскрытую панель — раньше оно висело в каждой строке, что по слову
// владельца «выглядит, как кнопка изменить пропала» (потому что глаз
// на ней не задерживался), и дублировало свайп. В раскрытой панели то же
// меню стоит в правом верхнем углу и работает идентично.
//
// Свайп-«Изменить»/«Удалить» остался — это быстрый жест для тех, кто уже
// знает. Он открыт только у `editable` строк (owner + `type == "ai"`).
enum AgentRowMode {
    /// Свёрнутая строка — основная инфа + свайп.
    case collapsed
    /// Раскрытая строка — снизу приклеена панель с детальной информацией.
    /// Тап по самой строке или по другой строке закрывает.
    case expanded
}

// Аватар агента с произвольным пикселем — веб использует 36px (строка) и
// 48px (форма правки), ни один не входит в `TFAvatar.Size` (18/20/30/32).
// Дублирует ПРАВИЛА `TFAvatar` (фото — rounded-lg contain, инициалы — круг)
// намеренно точно, а не «похоже»: числа обязаны совпасть дословно. Стоило
// бы завести в `TFAvatar` вариант с произвольным `CGFloat` — вне моей
// папки, см. отчёт.
//
// `AnimatedImage` (SDWebImageSwiftUI) вместо голого `AsyncImage` — просьба
// владельца 03.09.2026: «аватарки перестали анимированными быть» —
// `AsyncImage` декодирует только первый кадр, GIF/WebP статикой. Живые
// картинки-«питомцы» уже присылаются сервером по трём разным путям
// (`avatarUrl`/`avatarUrlWorking`/`avatarUrlBlocked`, см. `AgentRow.
// resolvedAvatarPath` ниже) — сама подстановка «какая картинка когда»
// не моя, это уже было; здесь только возвращена способность её проиграть.
private struct AgentAvatarView: View {
    let urlPath: String?
    let initials: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        if let urlPath, let url = URL(string: APIClient.baseURL.absoluteString + urlPath) {
            AnimatedImage(url: url, placeholder: { initialsCircle })
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Строка «Команда» — 1:1 `AgentRow` из `src/screens/AgentsScreen.tsx`:
/// приоритет аватарки (blocked > working > дефолт), бейдж роли, «онлайн» +
/// остаток лимита, чем занят прямо сейчас, свайп «Удалить»/«Изменить»
/// (только владелец и `type == "ai"`), инлайн-форма правки на месте строки,
/// раскрытие по тапу — панель с полной информацией (LOCK-146).
struct AgentRow: View {
    let agent: ApiUser
    let editable: Bool
    /// Сворачивается ли ряд прямо сейчас. Источник правды — `AgentsViewModel`,
    /// прокинуто через `init` экрана: на каждом ряду экран решает,
    /// `expandedAgentID == agent.id`. Это даёт «один развёрнутый ряд на экран»
    /// без подписок на `viewModel.expandedAgentID` в каждой строке.
    let isExpanded: Bool
    let viewModel: AgentsViewModel
    let onTapRow: () -> Void
    let onRequestDelete: (ApiUser) -> Void

    @State private var isEditing = false
    @State private var editName = ""
    @State private var isSaving = false
    @State private var photoSelection: PhotosPickerItem?

    @State private var offsetX: CGFloat = 0
    @State private var animateOffset = false
    @State private var dragStartOffset: CGFloat = 0
    // Замок оси и счёт скорости переехали в HorizontalPanRecognizer —
    // распознаватель отдаёт готовое смещение и скорость в px/с.

    // Ширина сведена с остальными списками (было 88pt против 84pt).
    private let actionWidth: CGFloat = TFRowActionWidth
    /// Своё имя в общем реестре раскрытых строк (`TFSwipeRowRegistry`).
    @State private var rowID = UUID()

    var body: some View {
        // Раскрыта всегда одна строка: как только реестр называет другую
        // (или прокрутка гасит всё), эта закрывается сама.
        Group {
            if isEditing {
                editForm
            } else {
                VStack(spacing: 0) {
                    swipeRow
                    if isExpanded {
                        expandedPanel
                    }
                }
            }
        }
        .onChange(of: TFSwipeRowRegistry.shared.openRowID) { _, openID in
            if openID != rowID, offsetX != 0 { close() }
        }
        .sheet(isPresented: $isEditingModel) {
            modelEditorSheet
        }
        .sheet(isPresented: $isEditingPrompt) {
            promptEditorSheet
        }
        .sheet(isPresented: $showMcpPicker) {
            mcpPickerSheet
        }
        .sheet(isPresented: $showSkillPicker) {
            skillPickerSheet
        }
    }

    // MARK: - Раскрытая панель

    /// Полная информация по агенту. Данные — из `viewModel.details[agent.id]`
    /// (грузится через `GET /api/agents/:id/details` при первом раскрытии,
    /// дальше читается из кэша). До загрузки показывается индикатор и
    /// сообщение об ошибке, если она была.
    @ViewBuilder
    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            // Шапка панели: «…» с тем же меню, что раньше висело в строке.
            HStack {
                Text("Подробности")
                    .tfText(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tfText)
                Spacer()
                if editable {
                    Menu {
                        Button { startEdit() } label: { Label("Изменить", systemImage: "pencil") }
                        Button(role: .destructive) { onRequestDelete(agent) } label: { Label("Удалить", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Color.tfDim)
                            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Изменить или удалить агента")
                }
            }

            // Секция «Агент» — из локальной `ApiUser` (приходит со списком,
            // не нужно ждать деталей).
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                sectionLabel("Агент")
                detailGrid
            }

            // Загрузка деталей. Грузим ровно один раз на раскрытие.
            if viewModel.detailsLoadingID == agent.id {
                HStack(spacing: TFSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Загружаем детали…")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(TFSpacing.md)
                .background(Color.tfCard)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
            } else if let details = viewModel.details(for: agent.id) {
                // API-токен
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    sectionLabel("API-ключ")
                    tokenField(details: details)
                }
                // Модель
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    sectionLabel("Модель")
                    modelRow(details: details)
                }
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    sectionLabel("Промпт")
                    promptRow(details: details)
                }
                // Инструменты (Composio / MCP)
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    sectionLabel("Инструменты (Composio)")
                    mcpList(details: details)
                }
                // Скиллы
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    sectionLabel("Скиллы")
                    skillsList(details: details)
                }
                // Права
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    sectionLabel("Права")
                    permissionsRow(details: details)
                }
            } else if let msg = viewModel.detailsErrorMessage {
                placeholderRow(msg, icon: "exclamationmark.triangle")
            } else {
                placeholderRow("Нет данных", icon: "questionmark.circle")
            }
        }
        .padding(TFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard2)
        .overlay(alignment: .top) {
            // Тонкая линия-водораздел между строкой и панелью.
            Rectangle()
                .fill(Color.tfStroke)
                .frame(height: TFBorder.width)
        }
        // Запускаем загрузку деталей ровно один раз на показ панели.
        // `.task(id:)` отменяется при свёртывании, но поскольку у нас
        // кэш — это не страшно; на следующем раскрытии VM отдаст кэш.
        .task(id: agent.id) {
            await viewModel.loadDetails(agentId: agent.id)
        }
    }

    // MARK: - Секции раскрытой панели

    /// Способ получения модели: зарегистрированный внешний агент либо
    /// прямой вызов API-провайдера.
    private func modelRow(details: AgentDetails) -> some View {
        valueRow(
            text: connectionSummary(details),
            icon: details.executionMode == .directAPI ? "network" : "cpu",
            accent: nil,
            action: editable ? { editModel(details: details) } : nil
        )
    }

    @State private var executionModeDraft: AgentExecutionMode = .agentRuntime
    @State private var providerDraft = ""
    @State private var modelDraft = ""
    @State private var baseURLDraft = ""
    @State private var credentialRefDraft = ""
    @State private var isEditingModel = false

    private func editModel(details: AgentDetails) {
        executionModeDraft = details.executionMode ?? .agentRuntime
        providerDraft = details.modelProvider ?? ""
        modelDraft = details.model ?? ""
        baseURLDraft = details.modelBaseURL ?? ""
        credentialRefDraft = details.modelCredentialRef ?? ""
        isEditingModel = true
    }

    private func connectionSummary(_ details: AgentDetails) -> String {
        let model = details.model.flatMap { $0.isEmpty ? nil : $0 } ?? "модель не указана"
        if details.executionMode == .directAPI {
            let provider = details.modelProvider.flatMap { $0.isEmpty ? nil : $0 }
                ?? "провайдер не указан"
            return "Напрямую по API · \(provider) · \(model)"
        }
        return "Текущий агент · \(model)"
    }

    private var canSaveConnection: Bool {
        guard executionModeDraft == .directAPI else { return true }
        return !providerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !credentialRefDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modelEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Способ подключения", selection: $executionModeDraft) {
                        ForEach(AgentExecutionMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(executionModeDraft == .agentRuntime
                         ? "Агент работает через уже зарегистрированный внешний runtime."
                         : "Сервер обращается к LLM-провайдеру напрямую; сырой ключ здесь не хранится.")
                }

                if executionModeDraft == .directAPI {
                    Section("Провайдер") {
                        TextField("Например, OpenAI", text: $providerDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Base URL — необязательно", text: $baseURLDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                }

                Section {
                    TextField("Например, claude-sonnet-4-5", text: $modelDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Идентификатор модели")
                } footer: {
                    Text(executionModeDraft == .agentRuntime
                         ? "Можно оставить пустым, если модель выбирает сам runtime."
                         : "Точное имя модели у выбранного API-провайдера.")
                }

                if executionModeDraft == .directAPI {
                    Section {
                        TextField("Например, OPENAI_API_KEY", text: $credentialRefDraft)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Секрет в vault")
                    } footer: {
                        Text("Укажите имя существующего секрета на сервере. Сам API-ключ в приложение и базу не записывается.")
                    }
                }
            }
            .navigationTitle("Подключение модели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isEditingModel = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let clean: (String) -> String? = { value in
                            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            return value.isEmpty ? nil : value
                        }
                        Task {
                            if await viewModel.updateConnection(
                                agentId: agent.id,
                                mode: executionModeDraft,
                                provider: clean(providerDraft),
                                model: clean(modelDraft),
                                baseURL: clean(baseURLDraft),
                                credentialRef: clean(credentialRefDraft)
                            ) {
                                isEditingModel = false
                            }
                        }
                    }
                    .disabled(!canSaveConnection)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @State private var promptDraft = ""
    @State private var isEditingPrompt = false

    @ViewBuilder
    private func promptRow(details: AgentDetails) -> some View {
        if let prompt = details.prompt, !prompt.isEmpty {
            valueRow(
                text: "Настроен · \(prompt.count) символов",
                icon: "text.quote",
                accent: nil,
                action: editable ? { editPrompt(current: prompt) } : nil
            )
        } else {
            placeholderRow(
                "Не задан — используется промпт runtime или роли",
                icon: "text.quote",
                action: editable ? { editPrompt(current: nil) } : nil
            )
        }
    }

    private func editPrompt(current: String?) {
        promptDraft = current ?? ""
        isEditingPrompt = true
    }

    private var promptEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $promptDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 240)
                } footer: {
                    Text("Пустое значение возвращает внешний или ролевой промпт по умолчанию.")
                }
            }
            .navigationTitle("Промпт агента")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isEditingPrompt = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let value = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            if await viewModel.updatePrompt(
                                agentId: agent.id,
                                prompt: value.isEmpty ? nil : value
                            ) {
                                isEditingPrompt = false
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Список подключённых MCP-серверов + кнопка «Добавить» (owner) с
    /// выпадающим списком каталога. Для не-владельца — только просмотр.
    @ViewBuilder
    private func mcpList(details: AgentDetails) -> some View {
        if details.mcpServers.isEmpty {
            placeholderRow(
                "Не подключено — нажмите, чтобы выбрать MCP-сервер",
                icon: "puzzlepiece.extension",
                action: editable ? { showMcpPicker = true } : nil
            )
        } else {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                ForEach(details.mcpServers) { server in
                    HStack(spacing: TFSpacing.sm) {
                        Image(systemName: server.enabled ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(server.enabled ? Color.tfGreen : Color.tfDim)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .tfText(.body)
                                .foregroundStyle(Color.tfText)
                            Text(server.provider)
                                .tfText(.caption)
                                .foregroundStyle(Color.tfDim)
                        }
                        Spacer()
                        if editable {
                            Button {
                                Task { await viewModel.disconnectMcp(
                                    agentId: agent.id, serverId: server.id
                                ) }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Color.tfCoral)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, TFSpacing.md)
                    .padding(.vertical, TFSpacing.sm)
                    .background(Color.tfCard)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
                }
                if editable {
                    Button { showMcpPicker = true } label: {
                        Label("Добавить MCP-сервер", systemImage: "plus.circle")
                            .tfText(.row)
                            .foregroundStyle(Color.tfBlue)
                            .padding(.horizontal, TFSpacing.md)
                            .padding(.vertical, TFSpacing.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @State private var showMcpPicker = false

    private var mcpPickerSheet: some View {
        NavigationStack {
            List(viewModel.mcpCatalog) { entry in
                let isConnected = viewModel.details(for: agent.id)?
                    .mcpServers.contains(where: { $0.id == entry.id }) == true
                Button {
                    Task {
                        if await viewModel.connectMcp(agentId: agent.id, serverId: entry.id) {
                            showMcpPicker = false
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: TFSpacing.md) {
                        Image(systemName: isConnected ? "checkmark.circle.fill" : "puzzlepiece.extension")
                            .foregroundStyle(isConnected ? Color.tfGreen : Color.tfBlue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                            Text(entry.provider)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let description = entry.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .disabled(isConnected)
            }
            .overlay {
                if viewModel.mcpCatalog.isEmpty {
                    ContentUnavailableView(
                        "Каталог MCP пуст",
                        systemImage: "puzzlepiece.extension",
                        description: Text("Сервер пока не вернул доступные подключения.")
                    )
                }
            }
            .navigationTitle("MCP-серверы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { showMcpPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Список установленных скиллов — тот же приём, что у MCP.
    @ViewBuilder
    private func skillsList(details: AgentDetails) -> some View {
        if details.skills.isEmpty {
            placeholderRow(
                "Не установлено — нажмите, чтобы выбрать",
                icon: "wand.and.stars",
                action: editable ? { showSkillPicker = true } : nil
            )
        } else {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                ForEach(details.skills) { skill in
                    HStack(spacing: TFSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.tfGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name)
                                .tfText(.body)
                                .foregroundStyle(Color.tfText)
                            if let desc = skill.description {
                                Text(desc)
                                    .tfText(.caption)
                                    .foregroundStyle(Color.tfSub)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if editable {
                            Button {
                                Task { await viewModel.uninstallSkill(
                                    agentId: agent.id, skillId: skill.id
                                ) }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Color.tfCoral)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, TFSpacing.md)
                    .padding(.vertical, TFSpacing.sm)
                    .background(Color.tfCard)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
                }
                if editable {
                    Button { showSkillPicker = true } label: {
                        Label("Установить скилл", systemImage: "plus.circle")
                            .tfText(.row)
                            .foregroundStyle(Color.tfBlue)
                            .padding(.horizontal, TFSpacing.md)
                            .padding(.vertical, TFSpacing.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @State private var showSkillPicker = false

    private var skillPickerSheet: some View {
        NavigationStack {
            List(viewModel.skillCatalog) { entry in
                let isInstalled = viewModel.details(for: agent.id)?
                    .skills.contains(where: { $0.id == entry.id }) == true
                Button {
                    Task {
                        if await viewModel.installSkill(agentId: agent.id, skillId: entry.id) {
                            showSkillPicker = false
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: TFSpacing.md) {
                        Image(systemName: isInstalled ? "checkmark.circle.fill" : "wand.and.stars")
                            .foregroundStyle(isInstalled ? Color.tfGreen : Color.tfBlue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                            if let description = entry.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .disabled(isInstalled)
            }
            .overlay {
                if viewModel.skillCatalog.isEmpty {
                    ContentUnavailableView(
                        "Каталог скиллов пуст",
                        systemImage: "wand.and.stars",
                        description: Text("Сервер пока не вернул доступные скиллы.")
                    )
                }
            }
            .navigationTitle("Скиллы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { showSkillPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Права — набор тумблеров (только владельцу; viewer/agent — read-only).
    @ViewBuilder
    private func permissionsRow(details: AgentDetails) -> some View {
        if editable {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                permissionToggle("Создавать задачи", keyPath: \.canCreateTasks, details: details)
                permissionToggle("Удалять задачи", keyPath: \.canDeleteTasks, details: details)
                permissionToggle("Управлять проектами", keyPath: \.canManageProjects, details: details)
                permissionToggle("Приглашать агентов", keyPath: \.canInviteAgents, details: details)
                permissionToggle("Менять настройки", keyPath: \.canChangeSettings, details: details)
            }
            .padding(TFSpacing.md)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        } else {
            valueRow(text: details.permissions.summary, icon: "lock.shield", accent: nil, action: nil)
        }
    }

    /// Один тумблер в секции «Права». Передаём `Binding` через get/set,
    /// чтобы изменения отправлялись на сервер по `.onChange` и обновляли
    /// `details` после ответа.
    private func permissionToggle(
        _ label: String,
        keyPath: WritableKeyPath<AgentPermissions, Bool>,
        details: AgentDetails
    ) -> some View {
        let current = details.permissions[keyPath: keyPath]
        return Toggle(isOn: Binding(
            get: { details.permissions[keyPath: keyPath] },
            set: { newValue in
                var updated = details.permissions
                updated[keyPath: keyPath] = newValue
                Task {
                    _ = await viewModel.updatePermissions(
                        agentId: agent.id, permissions: updated
                    )
                }
            }
        )) {
            Text(label)
                .tfText(.action)
                .foregroundStyle(Color.tfText)
        }
        .tint(Color.tfBlue)
        // `_ = current` заглушка — `details` ниже по иерархии используется
        // SwiftUI'ом для подписки; без явного обращения компилятор может
        // посчитать capture неиспользуемым.
        .onAppear { _ = current }
    }

    /// Заголовок маленькой секции внутри панели — капс/приглушённый,
    /// тот же приём, что у `TFSectionHeader`, но без горизонтального
    /// отступа экрана (панель сама управляет паддингом).
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .tfText(.caption)
            .tracking(0.5)
            .foregroundStyle(Color.tfDim)
    }

    /// Сетка «ключ — значение» по агенту: собираем всё, что есть в `ApiUser`,
    /// в один столбец пар. Пустые/неизвестные поля скрываем, чтобы не было
    /// «—/—/—/—» мусора.
    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            detailRow("Имя", value: agent.name)
            detailRow("ID", value: agent.id, monospaced: true)
            if let email = agent.email, !email.isEmpty {
                detailRow("Email", value: email)
            }
            detailRow("Тип", value: agent.type == .ai ? "ИИ-агент" : "Человек")
            detailRow("Роль", value: roleBadgeLabel)
            if let creator = agent.createdBy {
                detailRow("Создатель", value: creator, monospaced: true)
            }
            if agent.isSystemBotFlag {
                detailRow("Системный бот", value: "да")
            }
            if let seen = agent.lastSeenDate {
                detailRow("Последний визит", value: RelativeTime.relative(from: seen))
            }
            if let created = agent.createdAtDate {
                detailRow("Создан", value: RelativeTime.relative(from: created))
            }
            if let activity = agent.activity, !activity.isEmpty {
                detailRow("Активность", value: humanActivity(activity))
            }
            detailRow("Статус", value: agent.online == true ? "Онлайн" : "Офлайн")
            detailRow("Лимит", value: limitsText)
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
    }

    private func detailRow(_ key: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TFSpacing.sm) {
            Text(key)
                .tfText(.meta)
                .foregroundStyle(Color.tfDim)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .tfText(.body)
                // `active:` поверх `.tfText` — при `false` шрифт не навязывается,
                // и остаётся ступень `.body`. Порядок важен: `.font` в конце
                // цепочки перекрывает ранее заданный.
                .tfMonospaced(13, relativeTo: .footnote, active: monospaced)
                .foregroundStyle(Color.tfText)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Строка-заглушка для секций, по которым сервер ничего не отдаёт
    /// («Модель», «Инструменты», «Скиллы»). Серый бейдж «Не настроено»
    /// явно говорит владельцу: «тут пусто не случайно, ждём сервер».
    /// Опциональный `action` — тап по строке (только для editable-агентов
    /// с активной кнопкой «выбрать»).
    @ViewBuilder
    private func placeholderRow(
        _ text: String,
        icon: String,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(spacing: TFSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.sm))
                .foregroundStyle(Color.tfDim)
                .frame(width: 22)
            Text(text)
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
            Spacer()
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            } else {
                Text("не настроено")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
                    .padding(.horizontal, TFSpacing.sm)
                    .padding(.vertical, 2)
                    .background(Color.tfCard2)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
            }
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Готовое значение строкой (как `placeholderRow`, но без бейджа
    /// «не настроено» — значение есть). `action` опционален (например,
    /// для редактирования модели).
    @ViewBuilder
    private func valueRow(
        text: String,
        icon: String,
        accent: Color?,
        action: (() -> Void)?
    ) -> some View {
        let content = HStack(spacing: TFSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.sm))
                .foregroundStyle(accent ?? Color.tfDim)
                .frame(width: 22)
            Text(text)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
            Spacer()
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tfDim)
            }
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// Поле API-токена. Если сервер отдал ключ в этой сессии (создание или
    /// rotate) — показываем под глазиком с маской. Иначе — редактируемое
    /// поле «введите свой» + кнопки «Сохранить» / «Выпустить новый».
    /// `details` нужен для отображения `apiTokenSetAt` («обновлён …»).
    @ViewBuilder
    private func tokenField(details: AgentDetails) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            if let realToken = viewModel.realToken(for: agent.id) {
                HStack(spacing: TFSpacing.sm) {
                    Text(viewModel.isTokenRevealed(agent.id) ? realToken : "•••• •••• ••••")
                        .tfMonospaced(13, relativeTo: .footnote)
                        .foregroundStyle(Color.tfText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { viewModel.toggleTokenReveal(agent.id) } label: {
                        Image(systemName: viewModel.isTokenRevealed(agent.id) ? "eye.slash" : "eye")
                            .foregroundStyle(Color.tfDim)
                            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.isTokenRevealed(agent.id) ? "Скрыть ключ" : "Показать ключ")
                }
                if let set = details.apiTokenSetAtDate {
                    Text("Обновлён \(RelativeTime.relative(from: set))")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                }
            } else {
                // Нет токена в памяти: либо он не приходил с сервера (агент
                // уже был до текущей сессии), либо владелец вручную сбросил.
                // Даём ввести свой и кнопку «Выпустить новый».
                TFTextField("нет токена — введите свой", text: tokenBinding, icon: "key.fill")
                HStack(spacing: TFSpacing.sm) {
                    Button {
                        Task { _ = await viewModel.saveTokenDraft(agent.id) }
                    } label: {
                        Text("Сохранить")
                            .tfText(.row)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: 36)
                            .background(Color.tfRedSolid)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                    .disabled(viewModel.tokenDraft(for: agent.id).trimmingCharacters(in: .whitespaces).isEmpty)

                    Button {
                        Task { _ = await viewModel.rotateAgentToken(agent.id) }
                    } label: {
                        Text("Выпустить новый")
                            .tfText(.row)
                            .foregroundStyle(Color.tfSub)
                            .padding(.horizontal, TFSpacing.lg)
                            .frame(height: 36)
                            .background(Color.tfCard)
                            .overlay(RoundedRectangle(cornerRadius: TFRadius.lg).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
                    }
                    .buttonStyle(TFTapScaleStyle())
                }
                Text("Сервер уже хранит ключи хешем и наружу их больше не отдаёт — либо введите свой, либо выпустите новый. После сохранения ключ появится под глазиком в этой же строке.")
                    .tfText(.caption)
                    .foregroundStyle(Color.tfDim)
            }
        }
    }

    /// Связка `TFTextField` с черновиком токена в VM. Биндим через свой
    /// `Binding`, чтобы любые изменения в поле обновляли VM и наоборот.
    private var tokenBinding: Binding<String> {
        Binding(
            get: { viewModel.tokenDraft(for: agent.id) },
            set: { viewModel.updateTokenDraft(agent.id, value: $0) }
        )
    }

    /// Серверные `activity` сейчас — это «working» / «blocked» / null (см.
    /// `ApiUser.activity`). Расшифровка в человеческое описание, чтобы в
    /// карточке не светился голый enum.
    private func humanActivity(_ raw: String) -> String {
        switch raw {
        case "working": return "В работе"
        case "blocked": return "Заблокирован"
        case "review": return "На проверке"
        default: return raw
        }
    }

    // MARK: - Строка (показ)

    private var swipeRow: some View {
        ZStack {
            if editable {
                HStack(spacing: 0) {
                    actionButton(icon: "trash", label: "Удалить", color: .tfSwipeDelete) {
                        close()
                        onRequestDelete(agent)
                    }
                    .frame(width: actionWidth)
                    Spacer(minLength: 0)
                    actionButton(icon: "pencil", label: "Изменить", color: .tfSwipeEdit) {
                        close()
                        startEdit()
                    }
                    .frame(width: actionWidth)
                }
            }

            rowContent
                .background(Color.tfCard)
                .offset(x: offsetX)
                // Свайп на UIKit-распознавателе (HorizontalPan.swift): SwiftUI-жест
                // внутри ScrollView отбирает вертикальную прокрутку у списка.
                .gesture(
                    HorizontalPan(
                        // Неизменяемые строки (свои агенты) не свайпаются — как
                        // в вебе, где хук просто не подключался. Отключаем
                        // внутри замыканий: у моста `gesture(_:isEnabled:)` нет,
                        // эта перегрузка только для настоящих `Gesture`.
                        onBegin: {
                            guard editable else { return }
                            dragStartOffset = offsetX
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        },
                        onChange: { dx in if editable { drag(dx) } },
                        onEnd: { dx, velocity in if editable { settle(dx: dx, velocity: velocity) } }
                    )
                )
        }
        .clipShape(Rectangle())
    }

    private var rowContent: some View {
        HStack(spacing: TFSpacing.md) {
            AgentAvatarView(
                urlPath: resolvedAvatarPath,
                initials: agent.initials ?? "?",
                tint: Color(hex: agent.avatarColor ?? TFHexDefault.unassigned),
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                if agent.online == true, let action = agent.lastAction {
                    Text(action + (agent.lastActionTitle.map { " «\($0)»" } ?? ""))
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: TFSpacing.sm)
            // Бейдж роли + «онлайн»/лимит раньше жались в один горизонтальный
            // ряд с аватаркой и именем — на длинных сочетаниях («Оркестратор»
            // + «Офлайн» + «без лимита») ряду не хватало ширины, и SwiftUI
            // рвал слова посередине («Офлай[перенос]н») — жалоба владельца
            // 03.09.2026: «буквы складывались в разнобой». Колонка справа,
            // каждая строка — сама по себе, ничего больше не делит ширину.
            VStack(alignment: .trailing, spacing: 4) {
                roleBadge
                HStack(spacing: 6) {
                    Circle()
                        .fill(agent.online == true ? Color.tfGreen : Color.tfDim)
                        .frame(width: 7, height: 7)
                    Text(agent.online == true ? "Онлайн" : "Офлайн")
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(limitsText)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                    .fixedSize()
            }

            // «…» с меню «Изменить»/«Удалить» ПЕРЕНЕСЕНО в раскрытую панель
            // (`expandedPanel`, LOCK-146) — раньше стояло в каждой строке,
            // дублируя свайп. В свёрнутом виде меню нет, чтобы не размывать
            // «что можно сделать тапом»; «Изменить»/«Удалить» открываются
            // раскрытием строки (тап) или свайпом.
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
        .contentShape(Rectangle())
        // Тап по строке → toggleExpand. На «editable» строке одновременно
        // может сработать свайп — он приоритетнее: HorizontalPan не отдаёт
        // тап, если движение уже началось.
        .onTapGesture { onTapRow() }
    }

    // Была сплошная заливка (белый текст на цветном фоне) — просьба владельца
    // 03.09.2026: «не прям цветную, а фоном» — тот же приглушённый приём, что
    // у `TFAccentTag`/`TFLabelPill` (цветной текст на `color.opacity(0.18)`).
    private var roleBadge: some View {
        Text(roleBadgeLabel)
            .tfText(.meta)
            .foregroundStyle(roleBadgeColor)
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, 2)
            .background(roleBadgeColor.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
    }

    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: TFIconSize.sm))
                Text(label).tfText(.caption)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Производные

    private var resolvedAvatarPath: String? {
        if agent.activity == "blocked", let blocked = agent.avatarUrlBlocked { return blocked }
        if agent.activity == "working", let working = agent.avatarUrlWorking { return working }
        return agent.avatarUrl
    }

    private var roleBadgeColor: Color {
        if agent.role == .owner { return .tfRed }
        if agent.role == .orchestrator { return .tfBlue }
        if agent.type == .ai { return .tfPurple }
        return .tfOrange
    }

    private var roleBadgeLabel: String {
        if agent.role == .owner { return "Владелец" }
        if agent.role == .orchestrator { return "Оркестратор" }
        if agent.type == .ai { return "Агент" }
        return "Наблюдатель"
    }

    private var limitsText: String {
        guard let limits = agent.limits else { return "без лимита" }
        guard let remaining = limits.remaining else { return "Остаток: неизвестно" }
        switch remaining {
        case .number(let n):
            return n == n.rounded() ? "Остаток: \(Int(n))" : "Остаток: \(n)"
        case .text(let s):
            return "Остаток: \(s)"
        }
    }

    // MARK: - Свайп (числа — spec/SCREENS-2.md §0.6 + `src/lib/useRowSwipe.ts`)

    private func close() {
        animateOffset = true
        offsetX = 0
        TFSwipeRowRegistry.shared.didClose(rowID)
    }

    private func drag(_ dx: CGFloat) {
        // hasLeft/hasRight веба здесь не нужны отдельно: жест вообще не
        // подключается, если строка не `editable` (см. `swipeRow`), а у
        // editable-строки открыты оба направления.
        let raw = dragStartOffset + dx
        var pos = raw
        if raw > actionWidth {
            let over = raw - actionWidth
            pos = actionWidth + (over * 30) / (30 + over)
        } else if raw < -actionWidth {
            let over = -raw - actionWidth
            pos = -actionWidth - (over * 30) / (30 + over)
        }
        animateOffset = false
        offsetX = pos
    }

    /// Скорость приходит от UIKit в px/с — с веб-порогами (280/250) она
    /// сравнима напрямую, в отличие от прежнего самодельного счёта по
    /// `value.location` и `Date()`.
    private func settle(dx: CGFloat, velocity: CGFloat) {
        animateOffset = true
        if dragStartOffset == 0 {
            if offsetX < -36 || velocity < -280 {
                offsetX = -actionWidth
            } else if offsetX > 36 || velocity > 280 {
                offsetX = actionWidth
            } else {
                offsetX = 0
            }
        } else if dragStartOffset < 0 {
            let keep = !(dx > 25 || velocity > 250)
            offsetX = keep ? -actionWidth : 0
        } else {
            let keep = !(dx < -25 || velocity < -250)
            offsetX = keep ? actionWidth : 0
        }
        if offsetX == 0 {
            TFSwipeRowRegistry.shared.didClose(rowID)
        } else {
            TFSwipeRowRegistry.shared.didOpen(rowID)
        }
    }

    // MARK: - Форма правки (инлайн, на месте строки)

    private func startEdit() {
        editName = agent.name
        viewModel.renameErrorMessage = nil
        viewModel.avatarErrorMessage = nil
        isEditing = true
    }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: TFSpacing.md) {
            HStack(spacing: TFSpacing.md) {
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    AgentAvatarView(
                        urlPath: resolvedAvatarPath,
                        initials: agent.initials ?? "?",
                        tint: Color(hex: agent.avatarColor ?? TFHexDefault.unassigned),
                        size: 48
                    )
                }
                .onChange(of: photoSelection) { _, item in
                    Task { await handlePickedPhoto(item) }
                }
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Text("Заменить фото")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfText)
                            .padding(.horizontal, TFSpacing.sm)
                            .padding(.vertical, 4)
                            .background(Color.tfCard2)
                            .overlay {
                                RoundedRectangle(cornerRadius: TFRadius.md).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
                    }
                    if agent.avatarUrl != nil {
                        Button("Убрать фото") {
                            Task { await viewModel.removeAvatar(agentId: agent.id) }
                        }
                        .buttonStyle(TFTapFadeStyle())
                        .font(TFFont.action)
                        .foregroundStyle(Color.tfSub)
                    }
                }
            }

            TextField("Имя агента", text: $editName)
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .padding(.horizontal, TFSpacing.md)
                .frame(height: 44)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))

            TFErrorBanner(viewModel.renameErrorMessage, variant: .block)
            TFErrorBanner(viewModel.avatarErrorMessage, variant: .block)

            HStack(spacing: TFSpacing.sm) {
                TFButton("Отмена", variant: .secondary) {
                    isEditing = false
                }
                TFButton(isSaving ? "Сохраняем…" : "Сохранить", variant: .primary, isEnabled: !editName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving) {
                    Task { await save() }
                }
            }
        }
        .padding(TFSpacing.lg)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        if await viewModel.renameAgent(id: agent.id, name: editName) {
            isEditing = false
        }
    }

    /// Байты из фотобиблиотеки могут быть HEIC — перекодируем в JPEG сами,
    /// чтобы реальные байты совпадали с заявленным `mime` (сервер сверяет
    /// `Content-Type` со своим белым списком, HEIC там нет).
    private func handlePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let raw = try? await item.loadTransferable(type: Data.self) else { return }
        guard let uiImage = UIImage(data: raw), let jpegData = uiImage.jpegData(compressionQuality: 0.9) else { return }
        await viewModel.uploadAvatar(agentId: agent.id, data: jpegData, mime: "image/jpeg")
        photoSelection = nil
    }
}
