import SwiftUI

struct RoleRuntimeContextSheet: View {
    let role: RoleProfile
    @State private var context: RoleRuntimeContext?
    @State private var group = "Роль"
    @State private var errorText: String?
    @State private var loading = true
    @State private var service = RoleInstructionService()
    @Environment(\.dismiss) private var dismiss
    private var groups: [String] {
        var result: [String] = []
        for block in context?.blocks ?? [] where block.id != "role.persona" && !result.contains(block.group) { result.append(block.group) }
        return result
    }
    var body: some View {
        NavigationStack {
            Group {
                if loading { TFLoading(.block) }
                else if let context {
                    ScrollView {
                        VStack(alignment: .leading, spacing: TFSpacing.lg) {
                            TFSectionHeader("Личность роли")
                            TFCard(padding: 0) {
                                NavigationLink {
                                    RoleBehaviorTemplatesView(role: role.role, canEdit: context.canEdit == true)
                                } label: {
                                    TFListRow(icon: "person.text.rectangle", iconStyle: .plain,
                                              title: "Личность",
                                              subtitle: "Характер, шаблоны и пол",
                                              trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                                }
                                .buttonStyle(TFTapRowStyle())
                                .accessibilityIdentifier("roleContext.behavior")
                            }
                            TFSectionHeader("Правила и инструкции")
                            TFCard {
                                VStack(alignment: .leading, spacing: TFSpacing.md) {
                                    Text(context.notice ?? "Изменения применятся при следующем запуске роли.")
                                        .tfText(.caption).foregroundStyle(Color.tfSub)
                                    if !groups.isEmpty {
                                        Menu {
                                            ForEach(groups, id: \.self) { item in Button(item) { group = item } }
                                        } label: {
                                            HStack {
                                                Text(group).tfText(.body)
                                                Spacer()
                                                Image(systemName: "chevron.down")
                                            }.foregroundStyle(Color.tfText)
                                        }
                                        .accessibilityIdentifier("roleContext.groups")
                                    }
                                }
                            }
                            if let blocks = context.blocks {
                                TFCard(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(blocks.filter { $0.group == group && $0.id != "role.persona" }) { block in
                                            NavigationLink {
                                                RoleInstructionEditor(role: role.role, block: block, canEdit: context.canEdit == true, service: service)
                                            } label: {
                                                TFListRow(icon: "doc.text", iconStyle: .plain, title: block.title,
                                                          subtitle: block.source,
                                                          trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(Color.tfDim)))
                                            }
                                            .buttonStyle(TFTapRowStyle())
                                            .accessibilityIdentifier("roleContext.block.\(block.id)")
                                            TFDivider(inset: TFSpacing.lg)
                                        }
                                    }
                                }
                            } else {
                                ForEach(context.layers) { layer in
                                    TFSectionHeader(layer.title)
                                    TFCard {
                                        VStack(alignment: .leading, spacing: TFSpacing.md) {
                                            Text(layer.source).tfText(.caption).foregroundStyle(Color.tfSub)
                                            Text(layer.text).tfText(.body).textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }.padding(TFSpacing.lg)
                    }
                } else {
                    TFEmptyState(
                        icon: "exclamationmark.triangle",
                        text: "Не удалось загрузить инструкции",
                        description: errorText ?? ""
                    )
                }
            }
            .tfNativeHeader("Контекст роли", displayMode: .inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .background(Color.tfBackground)
            .task { await load() }
            .refreshable { await load() }
        }
    }
    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do {
            context = try await service.context(role: role.role)
            if !groups.contains(group) { group = groups.first ?? "Роль" }
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }
}


/// Прямой вход в один из канонических промптов с тем же сохранением и историей.
struct RolePromptSettingsSheet: View {
    let role: RoleProfile
    let blockID: String
    let title: String
    @State private var context: RoleRuntimeContext?
    @State private var errorText: String?
    @State private var loading = true
    @State private var service = RoleInstructionService()

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    TFLoading(.block)
                } else if let context, let block = context.blocks?.first(where: { $0.id == blockID }) {
                    RoleInstructionEditor(role: role.role, block: block,
                                          canEdit: context.canEdit == true, service: service,
                                          title: title, simple: true)
                } else {
                    TFEmptyState(
                        icon: "exclamationmark.triangle",
                        text: "Не удалось загрузить инструкцию",
                        description: errorText ?? "Инструкция недоступна на сервере.",
                        actionTitle: "Повторить",
                        action: { Task { await load() } }
                    )
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do {
            context = try await service.context(role: role.role)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
