import SwiftUI

/// Окно сессии в чате с ролью.
///
/// Владелец 03.11.2026: inset-карточки; шкала «Внешний вид» (заголовок /
/// подзаголовок / основной); размышления — только в выборе модели сверху;
/// пояснения разделов — `TFInfoHint`. Ленту чата не трогаем.
struct ChatSessionPanel: View {
    let chat: RoleChat
    @Bindable var choice: ChatModelChoice
    let workspace: ChatWorkspaceChoice
    let context: ChatContextSnapshot?
    let controls: ChatComposerControlStore
    let isWorking: Bool
    let onRefresh: () async -> Void
    let onRename: (String) async -> Void
    let onNewSession: () -> Void
    let onCompact: () async -> Void
    let onResetContext: () async -> Void
    let onClose: () async -> Void
    var onAttachmentSource: ((ChatAttachmentSource) -> Void)? = nil
    var workMode: Binding<RoleChatWorkMode>? = nil
    var executionMode: Binding<ChatExecutionMode>? = nil
    var canChangeExecutionMode: Bool = true
    var chatRoles: [String] = []
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var showsContext = false
    @State private var showsModelPicker = false
    @State private var confirmsReset = false
    @State private var actionRunning = false

    private var workModes: [RoleChatWorkMode] {
        ChatSessionWorkModePolicy.allModes
    }

    /// В групповых чатах один способ работы — по карточке: выбирать нечего, а
    /// действия над чатом есть в верхнем меню (владелец 05.11.2026).
    private var isGroup: Bool { chat.kind == "group" || chatRoles.count > 1 }

    private var allowsResearch: Bool {
        ChatSessionWorkModePolicy.allowsResearch(roles: chatRoles)
    }

    var body: some View {
        // Включаем шкалу ДО NavigationStack: sheet из чата иначе наследует
        // `.tfChatTypography()` (false) и сессия не слушает «Внешний вид».
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.sm) {
                    sessionCard {
                        TextField("Название", text: $title)
                            .tfText(.input)
                            .foregroundStyle(Color.tfText)
                            .padding(.horizontal, TFSpacing.md)
                            .padding(.vertical, 10)
                            .onSubmit { Task { await onRename(title) } }
                    }

                    sessionBlock(title: "Модель") {
                        sessionCard {
                            sessionButton(showsModelPicker = true) {
                                sessionLabeled("Модель чата",
                                               value: choice.effectiveTitle ?? "По умолчанию")
                            }
                            .accessibilityIdentifier("chat.session.model")

                            if choice.isSaving {
                                sessionDivider()
                                TFLoading(.inline)
                                    .padding(.horizontal, TFSpacing.md)
                                    .padding(.vertical, 10)
                            }
                            if let error = choice.errorText {
                                sessionDivider()
                                VStack(alignment: .leading, spacing: TFSpacing.xs) {
                                    Text(error)
                                        .tfText(.body)
                                        .foregroundStyle(Color.tfWarningText)
                                    Button("Повторить загрузку") { Task { await onRefresh() } }
                                        .tfText(.body)
                                        .foregroundStyle(Color.tfText)
                                }
                                .padding(.horizontal, TFSpacing.md)
                                .padding(.vertical, 10)
                            }
                        }
                    }

                    sessionBlock(
                        title: "Рабочее пространство",
                        hint: "Рабочая папка — каталог, в котором роль читает и пишет файлы этого разговора.\n\nКонтекст — сколько места занято в окне модели; по нажатию — разбор по частям."
                    ) {
                        sessionCard {
                            ChatWorkspaceMenu(choice: workspace) {
                                sessionLabeled("Рабочая папка",
                                               value: workspace.selected ?? "По умолчанию")
                            }
                            sessionDivider()
                            sessionButton(showsContext = true) { contextRow }
                                .accessibilityIdentifier("chat.session.context")
                        }
                    }

                    if let onAttachmentSource {
                        sessionBlock(title: "Вложения") {
                            HStack(spacing: TFSpacing.xs) {
                                ForEach(ChatSessionAttachment.allCases) { attachment in
                                    Button { onAttachmentSource(source(for: attachment)) } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: attachment.symbol)
                                                .tfTypeFont(size: TFIconSize.sm, weight: .semibold)
                                                .foregroundStyle(Color.tfDim)
                                                .frame(height: 22)
                                            Text(attachment.title)
                                                .tfText(.body)
                                                .foregroundStyle(Color.tfDim)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .tfSelectTile(selected: false)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("chat.session.attachment.\(attachment.rawValue)")
                                }
                            }
                        }
                    }

                    if !isGroup, let executionMode {
                        // Пояснение — вопросик у заголовка, как в рутинах
                        // (владелец 03.11.2026: не «здоровые» подписи под плитками).
                        sessionBlock(
                            title: "Способ выполнения",
                            hint: "В чате — ответы остаются в этом разговоре. Роль не создаёт подзадачи и не меняет карточку сама.\n\nПо карточке — роль ведёт задачу: дробит шаги, отмечает прогресс и обновляет состояние карточки."
                        ) {
                            HStack(spacing: TFSpacing.xs) {
                                ForEach(ChatExecutionMode.allCases, id: \.self) { mode in
                                    executionModeBlock(mode, selection: executionMode)
                                }
                            }
                        }
                    }

                    if !isGroup, let workMode {
                        sessionBlock(
                            title: "Режим работы",
                            hint: "Работа — обычное выполнение поручения.\n\nПланирование — сначала собирает план шагов, без спешки к итогу.\n\nЦель — держит фокус на результате: что должно получиться.\n\nИсследование — глубокий поиск и разбор (у Исследователя и Помощника)."
                        ) {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: TFSpacing.xs),
                                GridItem(.flexible(), spacing: TFSpacing.xs)
                            ], spacing: TFSpacing.xs) {
                                ForEach(workModes, id: \.self) { mode in
                                    workModeBlock(mode, selection: workMode)
                                }
                            }
                        }
                    }

                    if !isGroup {
                        sessionBlock(
                            title: "Настройки сессии",
                            hint: "Новая сессия — отдельный разговор с чистым контекстом.\n\nСжать контекст — ужать историю, чтобы освободить место в окне модели.\n\nСбросить контекст — сообщения остаются на экране, модель начинает новый контекст.\n\nЗакрыть сессию — убрать разговор из списка, если он не постоянный."
                        ) {
                            sessionCard {
                                sessionAction("Новая сессия", symbol: "plus.bubble") {
                                    dismiss()
                                    onNewSession()
                                }
                                sessionDivider()
                                sessionAction("Сжать контекст",
                                              symbol: "arrow.down.right.and.arrow.up.left") {
                                    Task { await perform(onCompact) }
                                }
                                sessionDivider()
                                sessionAction("Сбросить контекст", symbol: "arrow.counterclockwise") {
                                    confirmsReset = true
                                }
                                if !chat.isPermanentRoom {
                                    sessionDivider()
                                    sessionAction("Закрыть сессию", symbol: "archivebox") {
                                        Task { await perform(onClose); dismiss() }
                                    }
                                }
                            }
                        }
                        Text("Новая сессия создаёт отдельный разговор. Сброс контекста оставляет историю.")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .padding(.horizontal, TFSpacing.xs)
                    }
                }
                .padding(.horizontal, TFSpacing.lg)
                .padding(.vertical, TFSpacing.sm)
            }
            .tfScreenBackground()
            .tint(.primary)
            .disabled(choice.isSaving || actionRunning)
            // Без заголовка и кнопки: шторка закрывается свайпом (владелец 05.11.2026).
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsContext) {
                ChatContextSheet(snapshot: context, roleName: nil, loadError: controls.errorText,
                                 onRefresh: { Task { await onRefresh() } })
            }
            .sheet(isPresented: $showsModelPicker) {
                ChatModelPickerSheet(choice: choice)
                    .environment(\.tfTypeSettingsEnabled, true)
            }
            .confirmationDialog("Сбросить контекст этой сессии?",
                                isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Сбросить контекст") { Task { await perform(onResetContext) } }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("История останется в чате. Помощник начнёт новый контекст.")
            }
        }
        // Шторка сессии — не лента чата: снова включаем шкалу из настроек.
        .environment(\.tfTypeSettingsEnabled, true)
        .task { title = chat.title ?? "" }
    }

    // MARK: - Строки

    private var contextRow: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Контекст")
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                Spacer(minLength: TFSpacing.sm)
                Text(context?.summary ?? "Нет замера")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .multilineTextAlignment(.trailing)
            }
            if let snapshot = context, snapshot.fraction != nil {
                ChatContextBar(snapshot: snapshot).frame(height: 8)
            }
        }
        .padding(.horizontal, TFSpacing.md)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func executionModeBlock(_ mode: ChatExecutionMode,
                                    selection: Binding<ChatExecutionMode>) -> some View {
        let isSelected = selection.wrappedValue == mode
        return Button {
            selection.wrappedValue = mode
        } label: {
            VStack(spacing: TFSpacing.xs) {
                Image(systemName: mode.symbol)
                    .tfTypeFont(size: TFIconSize.sm, weight: .semibold)
                    .foregroundStyle(isSelected ? Color.tfText : Color.tfDim)
                    .frame(height: 20)
                Text(mode.title)
                    .tfText(.body)
                    .foregroundStyle(isSelected ? Color.tfText : Color.tfDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, TFSpacing.xs)
            .padding(.vertical, TFSpacing.sm)
            .tfSelectTile(selected: isSelected)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark")
                    .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                    .foregroundStyle(Color.tfText)
                    .padding(TFSpacing.sm)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(!isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canChangeExecutionMode)
        .accessibilityIdentifier("chat.session.executionMode.\(mode.rawValue)")
        .accessibilityHint(mode.summary)
    }

    private func workModeBlock(_ mode: RoleChatWorkMode,
                               selection: Binding<RoleChatWorkMode>) -> some View {
        let isSelected = selection.wrappedValue == mode
        let isEnabled = mode != .deepResearch || allowsResearch
        // Выбранная — тон из настроек; остальные серые «выключенные»
        // (владелец 03.11.2026). Недоступная — тоже dim.
        let ink: Color = (isSelected && isEnabled) ? Color.tfText : Color.tfDim
        return Button {
            selection.wrappedValue = mode
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.symbol)
                    .tfTypeFont(size: TFIconSize.sm, weight: .semibold)
                    .foregroundStyle(ink)
                    .frame(height: 20)
                Text(mode.title)
                    .tfText(.body)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if mode == .deepResearch && !allowsResearch {
                    Text("Только у Исследователя и Помощника")
                        .tfText(.action)
                        .foregroundStyle(Color.tfDim)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, TFSpacing.xs)
            .padding(.vertical, TFSpacing.sm)
            .tfSelectTile(selected: isSelected && isEnabled)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark")
                    .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                    .foregroundStyle(Color.tfText)
                    .padding(TFSpacing.sm)
                    .opacity(isSelected && isEnabled ? 1 : 0)
                    .accessibilityHidden(!(isSelected && isEnabled))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier("chat.session.workMode.\(mode.rawValue)")
    }

    // MARK: - Каркас

    private func sessionBlock<Content: View>(
        title: String,
        hint: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(spacing: TFSpacing.xs) {
                Text(title)
                    .tfText(.title)
                    .foregroundStyle(Color.tfSub)
                if let hint {
                    TFInfoHint(hint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TFSpacing.xs)
            content()
            if let footer {
                Text(footer)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .padding(.horizontal, TFSpacing.xs)
            }
        }
    }

    private func sessionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tfFieldDark, in: RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous)
                    .strokeBorder(Color.tfFieldBorder, lineWidth: TFBorder.width)
            )
    }

    private func sessionLabeled(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
            Spacer(minLength: TFSpacing.sm)
            Text(value)
                .tfText(.body)
                .foregroundStyle(Color.tfSub)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, TFSpacing.md)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func sessionButton<Label: View>(
        _ action: @autoclosure @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) { label() }
            .buttonStyle(.plain)
    }

    private func sessionAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .tfText(.body)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TFSpacing.md)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Разделитель внутри карточки: одинаковый отступ с обеих сторон,
    /// чтобы линия не «висела» только у левого края (владелец 03.11.2026).
    private func sessionDivider() -> some View {
        // Разделитель — серый `tfStroke`, чуть светлее фона; красная только
        // окантовка карточки (владелец 03.11.2026).
        Rectangle()
            .fill(Color.tfStroke)
            .frame(height: TFBorder.width)
            .padding(.horizontal, TFSpacing.md)
    }

    private func perform(_ action: () async -> Void) async {
        guard !actionRunning else { return }
        actionRunning = true
        defer { actionRunning = false }
        await action()
    }

    private func source(for attachment: ChatSessionAttachment) -> ChatAttachmentSource {
        switch attachment {
        case .photo: .photo
        case .file: .file
        case .camera: .camera
        }
    }
}

