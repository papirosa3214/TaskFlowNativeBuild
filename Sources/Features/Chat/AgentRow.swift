import SwiftUI

// LOCK-176 (этапы 2–3 миграции): строка «Команды» теперь показывает
// ПРОФИЛЬ РОЛИ (`RoleProfile`), а не `ApiUser`. Что изменилось по существу:
//
// - исполнитель — роль; Pi/runtime, provider и API-токен в обычном UI не
//   показываются вовсе;
// - модель — это primary + упорядоченные fallback (политика роли), а не
//   «executionMode / provider / baseURL / credentialRef»;
// - добавлены текущая задача и проблемы роли;
// - старые правки инфраструктуры (подключение модели напрямую, API-ключ,
//   MCP/скиллы установкой) убраны: у роли их нет, а серверный фасад читает
//   prompt из файла, skills из `role_skills`, tools из профиля Pi — писать
//   их через старые `/api/agents/:id` значило бы править не тот источник.
//   Промпт, tools, скиллы и права показываются как есть с сервера.
//
// Менять можно ровно то, у чего есть серверная ручка: модель —
// `PUT /api/runtime/routing/:role`.

/// Цвет роли — визуальная метка. Неизвестные роли получают приглушённый,
/// чтобы список не разъезжался в радугу из-за одной новой роли на сервере.
private func roleAccent(_ role: String) -> Color {
    switch role {
    case "owner": .tfRed
    case "architect": .tfPurple
    case "orchestrator": .tfBlue
    case "builder": .tfBlue
    case "qa": .tfGreen
    case "researcher", "analyst": .tfTeal
    default: .tfDim
    }
}

/// Аватар роли: фото у роли не заведено, поэтому инициалы на цвете роли.
private struct RoleAvatarView: View {
    let initials: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct AgentRow: View {
    let profile: RoleProfile
    /// Можно ли менять модель роли (владелец + живой runtime).
    let editable: Bool
    let isExpanded: Bool
    let viewModel: AgentsViewModel
    let onTapRow: () -> Void

    @State private var isEditingModel = false

    var body: some View {
        VStack(spacing: 0) {
            rowContent
                .contentShape(Rectangle())
                .onTapGesture(perform: onTapRow)
            if isExpanded {
                expandedPanel
            }
        }
        .sheet(isPresented: $isEditingModel) {
            RoleModelEditorSheet(profile: profile, viewModel: viewModel)
        }
    }

    // MARK: - Свёрнутая строка

    private var rowContent: some View {
        HStack(spacing: TFSpacing.md) {
            RoleAvatarView(initials: initials, tint: roleAccent(profile.role), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.title)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                Text(subtitle)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: TFSpacing.sm)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(profile.displayStatus)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(modelLine)
                    .tfText(.caption)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fixedSize()
            }
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
        .background(Color.tfCard)
    }

    private var initials: String {
        let parts = profile.title.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var subtitle: String {
        if let task = profile.currentTask {
            return task.title
        }
        return profile.status == .ready ? "Свободна" : profile.displayStatus
    }

    private var statusColor: Color {
        switch profile.status {
        case .ready: .tfGreen
        case .working: .tfTeal
        case .blocked: .tfOrange
        case .unavailable: .tfDim
        case .unknown: .tfDim
        }
    }

    private var modelLine: String {
        let primary = profile.model.flatMap { $0.isEmpty ? nil : $0 } ?? "модель не задана"
        return primary
    }

    // MARK: - Раскрытая панель

    @ViewBuilder
    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            modelSection
            if let task = profile.currentTask {
                sectionLabel("Текущая задача")
                valueRow(
                    text: task.title,
                    detail: taskStateTitle(task.state),
                    icon: "play.circle",
                    accent: nil,
                    action: nil
                )
            }
            promptSection
            toolsSection
            skillsSection
            permissionsSection
            if profile.hasProblems {
                problemsSection
            }
        }
        .padding(TFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.tfStroke)
                .frame(height: TFBorder.width)
        }
    }

    private func taskStateTitle(_ state: String?) -> String? {
        switch state {
        case "in_progress": "в работе"
        case "blocked": "заблокирована"
        case "review": "на проверке"
        default: nil
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            sectionLabel("Модель")
            valueRow(
                text: modelLine,
                detail: profile.fallbacks.isEmpty
                    ? nil
                    : "fallback: \(profile.fallbacks.joined(separator: " → "))",
                icon: "cpu",
                accent: nil,
                action: editable ? { isEditingModel = true } : nil
            )
        }
    }

    @ViewBuilder
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            sectionLabel("Промпт")
            if profile.prompt.isEmpty {
                placeholderRow("Не задан", icon: "text.quote")
            } else {
                valueRow(
                    text: "Настроен · \(profile.prompt.count) символов",
                    detail: nil,
                    icon: "text.quote",
                    accent: nil,
                    action: nil
                )
            }
        }
    }

    @ViewBuilder
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            sectionLabel("Инструменты")
            if profile.tools.isEmpty {
                placeholderRow("Не заданы", icon: "wrench.and.screwdriver")
            } else {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    ForEach(profile.tools, id: \.self) { tool in
                        HStack(spacing: TFSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.tfGreen)
                            Text(tool)
                                .tfMonospaced(13, relativeTo: .footnote)
                                .foregroundStyle(Color.tfText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, TFSpacing.md)
                        .padding(.vertical, TFSpacing.sm)
                        .background(Color.tfCard)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            sectionLabel("Скиллы")
            if profile.skills.isEmpty {
                placeholderRow("Не установлены", icon: "wand.and.stars")
            } else {
                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                    ForEach(profile.skills, id: \.name) { skill in
                        HStack(alignment: .top, spacing: TFSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.tfGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .tfText(.body)
                                    .foregroundStyle(Color.tfText)
                                if let desc = skill.description, !desc.isEmpty {
                                    Text(desc)
                                        .tfText(.caption)
                                        .foregroundStyle(Color.tfSub)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, TFSpacing.md)
                        .padding(.vertical, TFSpacing.sm)
                        .background(Color.tfCard)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            sectionLabel("Права")
            if let perms = profile.permissions, !perms.isEmpty {
                valueRow(text: perms, detail: nil, icon: "lock.shield", accent: nil, action: nil)
            } else {
                placeholderRow("Нет особых прав", icon: "lock.shield")
            }
        }
    }

    private var problemsSection: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            sectionLabel("Проблемы")
            ForEach(profile.problems, id: \.self) { problem in
                HStack(alignment: .top, spacing: TFSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.tfOrange)
                    Text(problem)
                        .tfText(.action)
                        .foregroundStyle(Color.tfSub)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, TFSpacing.sm)
                .background(Color.tfCard)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
            }
        }
    }

    // MARK: - Мелкие элементы панели

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .tfText(.caption)
            .tracking(0.5)
            .foregroundStyle(Color.tfDim)
    }

    @ViewBuilder
    private func placeholderRow(_ text: String, icon: String) -> some View {
        HStack(spacing: TFSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.sm))
                .foregroundStyle(Color.tfDim)
                .frame(width: 22)
            Text(text)
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
            Spacer(minLength: 0)
            Text("не задано")
                .tfText(.caption)
                .foregroundStyle(Color.tfDim)
                .padding(.horizontal, TFSpacing.sm)
                .padding(.vertical, 2)
                .background(Color.tfCard2)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.pill))
        }
        .padding(TFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tfCard)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
    }

    @ViewBuilder
    private func valueRow(
        text: String,
        detail: String?,
        icon: String,
        accent: Color?,
        action: (() -> Void)?
    ) -> some View {
        let content = HStack(spacing: TFSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: TFIconSize.sm))
                .foregroundStyle(accent ?? Color.tfDim)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
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
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Редактор модели роли

/// Primary + упорядоченные fallback. Порядок fallback'ов — порядок
/// эскалации, поэтому список перемещаемый, а не сортируемый.
private struct RoleModelEditorSheet: View {
    let profile: RoleProfile
    let viewModel: AgentsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var primary: String = ""
    @State private var fallbacks: [String] = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.modelsLoading {
                    HStack { ProgressView(); Text("Загружаем модели…").foregroundStyle(.secondary) }
                }
                if let msg = viewModel.modelsErrorMessage {
                    Text(msg).foregroundStyle(Color.tfRed)
                }

                Section {
                    Picker("Основная", selection: $primary) {
                        ForEach(primaryChoices, id: \.self) { id in
                            Text(label(for: id)).tag(id)
                        }
                    }
                } header: {
                    Text("Primary")
                } footer: {
                    Text("Модель, с которой роль начинает работу.")
                }

                Section {
                    ForEach(fallbacks, id: \.self) { id in
                        Text(label(for: id))
                    }
                    .onMove { from, to in fallbacks.move(fromOffsets: from, toOffset: to) }
                    .onDelete { offsets in fallbacks.remove(atOffsets: offsets) }

                    Menu {
                        ForEach(addableChoices, id: \.self) { id in
                            Button(label(for: id)) { fallbacks.append(id) }
                        }
                    } label: {
                        Label("Добавить fallback", systemImage: "plus.circle")
                    }
                    .disabled(addableChoices.isEmpty)
                } header: {
                    Text("Fallback")
                } footer: {
                    Text("Порядок — порядок эскалации: если primary не справился, роль переходит к следующей сверху вниз.")
                }
            }
            .navigationTitle("Модель роли")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        isSaving = true
                        Task {
                            let ok = await viewModel.updateModelPolicy(
                                role: profile.role, primary: primary, fallbacks: fallbacks
                            )
                            isSaving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(isSaving || primary.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await viewModel.loadModelsIfNeeded()
            primary = profile.model ?? primaryChoices.first ?? ""
            fallbacks = profile.fallbacks
        }
    }

    /// Все id моделей каталога, primary-кандидаты. Если каталог пуст, но у
    /// роли задана модель — она всё равно должна быть в списке.
    private var primaryChoices: [String] {
        var ids = orderedModelIDs
        if let current = profile.model, !current.isEmpty, !ids.contains(current) {
            ids.insert(current, at: 0)
        }
        return ids
    }

    private var addableChoices: [String] {
        orderedModelIDs.filter { $0 != primary && !fallbacks.contains($0) }
    }

    private var orderedModelIDs: [String] {
        var seen = Set<String>()
        return viewModel.models.compactMap { model in
            seen.insert(model.id).inserted ? model.id : nil
        }
    }

    private func label(for id: String) -> String {
        viewModel.models.first { $0.id == id }.map { model in
            model.displayName == model.id ? id : "\(model.displayName) · \(id)"
        } ?? id
    }
}
