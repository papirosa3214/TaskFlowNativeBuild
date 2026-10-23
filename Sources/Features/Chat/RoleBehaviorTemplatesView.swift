import SwiftUI

struct RoleBehaviorTemplatesView: View {
    let role: String
    let canEdit: Bool
    @State private var service = RoleBehaviorService()
    @State private var active: RoleBehavior?
    @State private var draft: RoleBehaviorDraft?
    @State private var templateName = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var status: String?
    @State private var showDiscard = false
    @Environment(\.dismiss) private var dismiss

    private var changed: Bool {
        guard let draft, let active else { return false }
        return draft.differs(from: active)
    }
    private var text: Binding<String> { Binding(get: { draft?.text ?? "" }, set: { draft?.text = $0; status = nil }) }
    private var gender: Binding<RoleBehaviorGender> { Binding(get: { draft?.gender ?? .male }, set: { draft?.gender = $0; status = nil }) }
    private var validText: Bool { !(draft?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                if let active, let draft {
                    section("Сейчас действует") {
                        Text(active.text).textSelection(.enabled).accessibilityIdentifier("roleBehavior.activeText")
                        Text("Пол: \(active.gender.title)").tfText(.caption).foregroundStyle(Color.tfSub)
                            .accessibilityIdentifier("roleBehavior.activeGender")
                    }
                    section("Личность · ROLE.md") {
                        if canEdit {
                            TextEditor(text: text)
                                .frame(minHeight: 220).scrollContentBackground(.hidden)
                                .tfText(.input).foregroundStyle(Color.tfText)
                                .accessibilityIdentifier("roleBehavior.editor")
                            Picker("Пол", selection: gender) {
                                ForEach(RoleBehaviorGender.allCases, id: \.self) { Text($0.title).tag($0) }
                            }.tint(Color.tfText)
                            .accessibilityIdentifier("roleBehavior.gender")
                            Text("Определяет, как роль говорит о себе: «сделал» или «сделала».")
                                .tfText(.caption).foregroundStyle(Color.tfSub)
                            TFButton("Применить личность", icon: "checkmark", variant: .secondary, isEnabled: !busy && !draft.hasConflict && validText && changed) {
                                Task { await apply() }
                            }.accessibilityIdentifier("roleBehavior.apply")
                        } else {
                            Text(active.text).textSelection(.enabled)
                        }
                    }
                    if draft.hasConflict {
                        section("Личность изменилась на сервере") {
                            Text("Ваш текст и пол сохранены в редакторе. Обновите версию, сравните с действующей личностью и примените правку.")
                            TFButton("Обновить версию, сохранить мой текст", variant: .secondary, isEnabled: !busy) {
                                Task { await load(preserveDraft: true) }
                            }.accessibilityIdentifier("roleBehavior.refreshVersion")
                        }
                    }
                    section("Шаблоны поведения") {
                        Text("Откройте шаблон, измените его при необходимости и нажмите «Применить личность».")
                            .tfText(.caption).foregroundStyle(Color.tfSub)
                        ForEach(active.templates) { template in
                            TFButton(template.name, variant: .secondary, isEnabled: canEdit && !busy) {
                                self.draft?.select(template)
                                templateName = template.builtin ? "" : template.name
                                status = "Шаблон открыт в редакторе. Действующая личность не изменена."
                            }.accessibilityIdentifier("roleBehavior.template.\(template.id)")
                            Text("\(template.builtin ? "Встроенный" : "Свой") · \(template.gender.title)")
                                .tfText(.caption).foregroundStyle(Color.tfSub)
                        }
                        if canEdit {
                            TFButton("Создать свой", icon: "plus", variant: .outline, isEnabled: !busy) {
                                self.draft?.text = ""
                                templateName = ""
                                status = "Опишите, кем является роль, и сохраните шаблон."
                            }.accessibilityIdentifier("roleBehavior.new")
                        }
                    }.hintAnchor(HintAnchorID.roleBehavior)
                    if canEdit {
                        section("Сохранить как шаблон") {
                            TFTextField("Название шаблона", text: $templateName)
                                .accessibilityIdentifier("roleBehavior.templateName")
                            TFButton("Сохранить как новый шаблон", icon: "square.and.arrow.down", variant: .secondary, isEnabled: !busy && validText && !templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                Task { await saveTemplate() }
                            }.accessibilityIdentifier("roleBehavior.saveTemplate")
                            Text("Сохранение добавит свой шаблон с этим текстом и полом. Применяется отдельной кнопкой выше.")
                                .tfText(.caption).foregroundStyle(Color.tfSub)
                        }
                    }
                } else if busy { ProgressView() }
                if let errorText { Text(errorText).accessibilityIdentifier("roleBehavior.error") }
                if let status { Text(status).accessibilityIdentifier("roleBehavior.status") }
            }.padding(TFSpacing.lg).disabled(busy)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.tfBackground)
        .navigationTitle("Личность роли")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(changed)
        .toolbar {
            if changed { ToolbarItem(placement: .cancellationAction) { Button("Назад") { showDiscard = true } } }
        }
        .interactiveDismissDisabled(changed)
        .confirmationDialog("Отменить несохранённую правку личности?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Отменить правку", role: .destructive) { dismiss() }
        }
        .task { await load(preserveDraft: false) }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            TFSectionHeader(title)
            TFCard {
                VStack(alignment: .leading, spacing: TFSpacing.md, content: content)
                    .tfText(.body).foregroundStyle(Color.tfText).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    @MainActor private func load(preserveDraft: Bool) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            let value = try await service.load(role: role)
            active = value
            if preserveDraft { draft?.adoptVersion(value.version) }
            else { draft = RoleBehaviorDraft(behavior: value) }
        } catch { errorText = error.localizedDescription }
    }
    @MainActor private func apply() async {
        guard let draft else { return }
        busy = true; errorText = nil; status = nil
        defer { busy = false }
        do {
            let value = try await service.apply(role: role, draft: draft)
            active = value; self.draft = RoleBehaviorDraft(behavior: value)
            status = "Личность сохранена. Применится при следующем запуске роли."
        } catch APIError.conflict {
            self.draft?.hasConflict = true
            errorText = "Конфликт версий. Ваш текст и пол не потеряны."
        } catch { errorText = error.localizedDescription }
    }
    @MainActor private func saveTemplate() async {
        guard let draft else { return }
        busy = true; errorText = nil; status = nil
        defer { busy = false }
        do {
            _ = try await service.saveTemplate(role: role, name: templateName.trimmingCharacters(in: .whitespacesAndNewlines), text: draft.text, gender: draft.gender)
            active = try await service.load(role: role)
            status = "Шаблон сохранён. Действующая личность не изменена."
        } catch { errorText = error.localizedDescription }
    }
}
