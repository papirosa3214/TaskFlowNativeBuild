import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

/// Выбор задачи для привязки чата (владелец 21.09.2026: «привязка конкретных
/// чатов к проекту и, соответственно, к задаче»). Список берётся из общего
/// `TaskStore` — задачи уже загружены приложением, отдельный запрос не нужен.
/// Название и состав чата: переименование, добавление и исключение участников.
/// Владелец 21.09.2026: «нет возможности вообще как-то понять, кто в этом чате
/// присутствует», «переименовывать не умею», «исключать не умею», «добавлять не
/// умею».
///
/// Построено как остальные экраны приложения: крестик слева — закрыть, «…»
/// справа — действия (добавление участника — ПОДМЕНЮ со списком ролей, как
/// выбор модели в `VoiceModelsScreen`), удаление участника — по зажатию на
/// строке, без значков в списке.
struct RoleChatDetailsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onChanged: (RoleChat) -> Void
    /// Владелец 26.09.2026: «Удалить чат» переехал сюда, в «…» этой же
    /// шторки — раньше жил в общем меню комнаты чата вместе с «Название и
    /// участники», хотя открыть их можно было и тапом по имени. Строка
    /// удаления сама закрывает шторку и вызывает этот колбэк, который
    /// закрывает саму комнату чата (чата больше нет — там нечего показывать).
    let onDeleted: () -> Void
    @State private var chat: RoleChat
    @State private var title: String
    @State private var roles: [RoleProfile] = []
    @State private var isLoadingRoles = true
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var isDeleteChatConfirmOpen = false
    @AppStorage(RoleWorkDetailLevel.storageKey) private var workDetailLevel = RoleWorkDetailLevel.standard
    @AppStorage(RoleTranslator.autoKey) private var autoTranslate = false
    private let api = APIClient()

    init(chat: RoleChat, onChanged: @escaping (RoleChat) -> Void, onDeleted: @escaping () -> Void) {
        _chat = State(initialValue: chat)
        _title = State(initialValue: chat.title ?? "")
        self.onChanged = onChanged
        self.onDeleted = onDeleted
    }

    private var isCreator: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TASKFLOW_MEMBER_SWIPE_PREVIEW"] == "1" { return true }
        #endif
        return chat.createdBy == session.currentUser?.id
    }
    private var isOwner: Bool { session.currentUser?.role == .owner }

    /// Роли, которых в чате ещё нет: участником может быть только роль с
    /// серверной учёткой — иначе отвечать в чате ей нечем.
    private var availableRoles: [RoleProfile] {
        roles.filter { profile in
            guard profile.canJoinChat, let account = profile.accountID else { return false }
            return !chat.members.contains { $0.id == account }
        }
    }

    private var titleChanged: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != (chat.title ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    if isCreator {
                        TextField("Без названия", text: $title)
                            .onSubmit { Task { await saveTitle() } }
                    } else {
                        Text(chat.title?.isEmpty == false ? chat.title! : "Без названия")
                            .foregroundStyle(Color.tfSub)
                    }
                }
                Section {
                    ForEach(chat.members) { member in
                        memberRow(member)
                        // Слоты — отдельные участники исполнения (спецификация
                        // 08.11.2026, §6): подписи те же, что в выборе `@`.
                        ForEach(RoleChatSlot.numbered(for: member.id, in: chat.slots), id: \.subtaskID) { slot in
                            slotRow(slot)
                        }
                    }
                } header: {
                    // «Собеседники» точнее: это роли, к которым обращаешься через @
                    // (владелец 10.11.2026: «собеседники так лучше»).
                    Text("Собеседники")
                } footer: {
                    Text(chat.kind == "direct"
                        ? "Личный чат: можно писать без @."
                        : "Групповой чат: выберите собеседника через @.")
                        .accessibilityIdentifier("chat.details.addressing")
                }
                // Одна настройка на все чаты (владелец 14.10.2026).
                Section {
                    Picker("Показ работы роли", selection: $workDetailLevel) {
                        ForEach(RoleWorkDetailLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Показ работы роли")
                } footer: {
                    Text(workDetailLevel.explanation)
                }
                Section {
                    HStack {
                        Text("Переводить работу ролей сразу")
                        Spacer()
                        TFToggle(isOn: $autoTranslate)
                    }
                        .onChange(of: autoTranslate) { _, on in RoleTranslator.shared.isOn = on }
                        .accessibilityIdentifier("chat.details.autoTranslate")
                } footer: {
                    Text("Английские реплики ролей показываются по-русски. Переводит iPhone, без сервера; кнопка «Перевести» в ленте работает и без этой настройки.")
                }
            }
            .navigationTitle("Чат")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
                if isCreator || isOwner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            // Личная комната роли — только двое: владелец и роль
                            // (владелец 08.11.2026: «на то они и личные, что там не
                            // должно быть больше двух участников»). Приглашение
                            // остаётся в обычных чатах и в групповом каталоге.
                            if isCreator && chat.roomKind != "personal" {
                                Menu {
                                    if isLoadingRoles {
                                        Text("Загрузка ролей…")
                                    } else if availableRoles.isEmpty {
                                        Text("Все роли уже в чате")
                                    } else {
                                        ForEach(availableRoles) { profile in
                                            Button {
                                                guard let account = profile.accountID else { return }
                                                Task { await addMember(account) }
                                            } label: {
                                                Text(profile.title)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Добавить участника", systemImage: "person.badge.plus")
                                }
                            }
                            if isOwner {
                                Button(role: .destructive) {
                                    isDeleteChatConfirmOpen = true
                                } label: {
                                    Label("Удалить чат", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Ещё")
                        .accessibilityIdentifier("chat.details.menu")
                        .hintAnchor(HintAnchorID.chatMembersMenu)
                    }
                }
            }
            .alert("Не удалось изменить чат", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Закрыть", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog("Удалить чат?", isPresented: $isDeleteChatConfirmOpen,
                                titleVisibility: .visible) {
                Button("Удалить чат", role: .destructive) { Task { await deleteChat() } }
            }
            // Название сохраняется само: отдельной кнопки в шапке нет — там
            // «…». Правка уходит на сервер по клавише «готово» и при закрытии
            // шторки, если текст успел измениться.
            .onDisappear {
                if titleChanged { Task { await saveTitle() } }
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["TASKFLOW_MEMBER_SWIPE_PREVIEW"] == "1" { return }
                #endif
                isLoadingRoles = true
                defer { isLoadingRoles = false }
                do { roles = try await api.rolesList() }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func memberRow(_ member: RoleChatMember) -> some View {
        let canRemove = isCreator && member.id != session.currentUser?.id
        return memberContent(member)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .accessibilityIdentifier("chat.member." + member.id)
        .contextMenu {
            if canRemove {
                Button(role: .destructive) {
                    Task { await removeMember(member) }
                } label: {
                    Label("Удалить из чата", systemImage: "trash")
                }
            }
        }
    }

    /// Строка слота под своей ролью: «Разработчик 1», «Разработчик 2». Одна
    /// учётная запись роли может вести несколько этапов сразу, и по подписи
    /// видно, к какому из них адресована реплика.
    private func slotRow(_ slot: RoleChatSlot) -> some View {
        HStack(spacing: TFSpacing.md) {
            Image(systemName: "square.stack.3d.up")
                .tfTypeFont(size: TFIconSize.sm)
                .foregroundStyle(Color.tfDim)
            Text(slot.label)
                .foregroundStyle(Color.tfSub)
            Spacer(minLength: TFSpacing.sm)
        }
        .padding(.leading, TFSpacing.xl)
        .accessibilityIdentifier("chat.slot." + slot.subtaskID)
    }

    private func memberContent(_ member: RoleChatMember) -> some View {
        HStack(spacing: TFSpacing.md) {
            RoleMemberAvatar(member: member, size: .node)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).foregroundStyle(Color.tfText)
                if member.id == chat.createdBy {
                    Text("создатель чата").tfText(.meta).foregroundStyle(Color.tfDim)
                }
            }
            Spacer(minLength: TFSpacing.sm)
        }
        .contentShape(Rectangle())
    }

    /// Сервер отвечает обновлённым чатом — им и обновляем экран, и отдаём
    /// наверх, в комнату: переименование и состав видны сразу.
    private func apply(_ updated: RoleChat) {
        chat = updated
        title = updated.title ?? ""
        onChanged(updated)
    }

    private func saveTitle() async {
        guard titleChanged else { return }
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.renameRoleChat(id: chat.id, title: title)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteChat() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.deleteRoleChat(id: chat.id)
            // Строку из локального списка убираем сразу и тоже без стирания:
            // сервер её больше не отдаёт, а локальная копия иначе вернула бы
            // чат при ответе 304.
            try? LocalStore.shared.hideChat(id: chat.id)
            dismiss()
            onDeleted()
        } catch { errorMessage = error.localizedDescription }
    }

    private func addMember(_ memberID: String) async {
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.addRoleChatMember(chatID: chat.id, memberID: memberID)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func removeMember(_ member: RoleChatMember) async {
        isBusy = true
        defer { isBusy = false }
        do { apply(try await api.removeRoleChatMember(chatID: chat.id, memberID: member.id)) }
        catch { errorMessage = error.localizedDescription }
    }
}
