import SwiftUI

/// Содержимое системного popover у кнопки сессии: без собственных карточек и фона.
struct ChatSessionPanel: View {
    let chat: RoleChat
    @Bindable var choice: ChatModelChoice
    let workspace: ChatWorkspaceChoice
    let context: ChatContextSnapshot?
    let controls: ChatComposerControlStore
    let isWorking: Bool
    let onRefresh: () async -> Void
    var onAttachmentSource: ((ChatAttachmentSource) -> Void)? = nil
    var workMode: Binding<RoleChatWorkMode>? = nil
    var chatRoles: [String] = []
    @State private var showsContext = false
    @State private var showsModelPicker = false
    @State private var contextDetent: PresentationDetent = .medium

    var body: some View {
        VStack(spacing: 0) {
            Button { showsModelPicker = true } label: {
                HStack {
                    Text(choice.effectiveTitle ?? "Модель")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if choice.isSaving { ProgressView().controlSize(.small) } // design-system-guard: ignore — владелец 07.11: системное окно без фирменной стилизации
                    else { Image(systemName: "chevron.right").foregroundStyle(.secondary) } // design-system-guard: ignore — владелец 07.11: системное окно без фирменной стилизации
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Модель: " + (choice.effectiveTitle ?? "Нет данных"))
            .accessibilityIdentifier("chat.session.model")

            if let error = choice.errorText {
                Text(error).font(.caption).foregroundStyle(.red) // design-system-guard: ignore — владелец 07.11: системное окно без фирменной стилизации
                Button("Повторить загрузку") { Task { await onRefresh() } }
            }
            Divider()

            ChatWorkspaceMenu(choice: workspace) {
                HStack {
                    Text(workspace.selected ?? workspace.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary) // design-system-guard: ignore — владелец 07.11: системное окно без фирменной стилизации
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            Divider()

            Button {
                contextDetent = .medium
                showsContext = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let context, context.fraction != nil {
                        ChatContextBar(snapshot: context).frame(height: 8)
                    }
                    Text(context?.summary ?? "Нет замера")
                        .font(.caption) // design-system-guard: ignore — владелец 07.11: системное окно без фирменной стилизации
                        .foregroundStyle(.secondary) // design-system-guard: ignore — владелец 07.11: системное окно без фирменной стилизации
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Контекст модели")
            .accessibilityValue(context?.summary ?? "Нет замера")
            .accessibilityIdentifier("chat.session.context")

            if let onAttachmentSource {
                Divider()
                HStack {
                    ForEach(ChatSessionAttachment.allCases) { attachment in
                        Button { onAttachmentSource(source(for: attachment)) } label: {
                            Text(attachment.title)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("chat.session.attachment.\(attachment.rawValue)")
                    }
                }
            }

            if let workMode {
                Divider()
                Picker("Режим работы", selection: workMode) {
                    ForEach(ChatSessionWorkModePolicy.allModes, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 8)
                .accessibilityIdentifier("chat.session.workMode")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(idealWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(choice.isSaving)
        .environment(\.tfTypeSettingsEnabled, true)
        .tfSheet(isPresented: $showsContext) {
            ChatContextSheet(snapshot: context, roleName: nil, loadError: controls.errorText,
                             onRefresh: { Task { await onRefresh() } })
                .presentationDetents([.medium, .large], selection: $contextDetent)
                .presentationDragIndicator(.visible)
        }
        .tfSheet(isPresented: $showsModelPicker) {
            ChatModelPickerSheet(choice: choice)
                .environment(\.tfTypeSettingsEnabled, true)
        }
        .onChange(of: showsModelPicker) { _, shows in
            guard shows else { return }
            Task { await choice.refresh(chat: chat) }
        }
    }

    private func source(for attachment: ChatSessionAttachment) -> ChatAttachmentSource {
        switch attachment {
        case .photo: .photo
        case .file: .file
        case .camera: .camera
        }
    }
}
