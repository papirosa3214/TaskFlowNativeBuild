import SwiftUI
import PhotosUI

/// Шторка «Изменить» профиля. Переделана 20.10.2026 по просьбе владельца —
/// «по-человечески»: фото, имя, логин и пароль в одном месте.
///
/// Раньше здесь было только имя: нативный `updateProfile` не умел логин и
/// пароль и к тому же читал ответ сервера как голого пользователя, хотя
/// `PUT /auth/profile` отдаёт `{user, token}`. Теперь клиент шлёт всё, что
/// шлёт веб (`EditProfileModal.tsx`), и сохраняет свежий токен.
///
/// Фото меняется сразу, без «Сохранить» — как и тапом по аватарке в строке
/// профиля; «Убрать фото» живёт здесь (владелец 03.09.2026).
///
/// ⚠️ `SettingsViewModel` — параметром, не `@Environment`: внутри шторки
/// `@Environment(SettingsViewModel.self)` падал в рантайме iOS 26.5.
struct EditProfileSheet: View {
    let user: ApiUser
    let avatarURLOverride: String?
    let settings: SettingsViewModel
    let onSaved: (ApiUser) -> Void
    let onAvatarChanged: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var login: String
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var isPhotoBusy = false
    @State private var errorMessage: String?

    private var avatarURL: String? { avatarURLOverride ?? user.avatarUrl }

    init(user: ApiUser, avatarURLOverride: String?, settings: SettingsViewModel, onSaved: @escaping (ApiUser) -> Void, onAvatarChanged: @escaping (String?) -> Void) {
        self.user = user
        self.settings = settings
        self.avatarURLOverride = avatarURLOverride
        self.onSaved = onSaved
        self.onAvatarChanged = onAvatarChanged
        _name = State(initialValue: user.name)
        _login = State(initialValue: user.email ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.lg) {
            Text("Профиль")
                .tfText(.title)
                .foregroundStyle(Color.tfText)
                .frame(maxWidth: .infinity)
            photoBlock
            TFErrorBanner(errorMessage, variant: .block)
            ProfileNameLoginFields(name: $name, login: $login)
            ProfilePasswordFields(current: $currentPassword, new: $newPassword, repeated: $repeatPassword)
            HStack(spacing: TFSpacing.md) {
                TFButton("Отмена", variant: .secondary) { dismiss() }
                TFButton(isSaving ? "Сохранение…" : "Сохранить", variant: .primary, isEnabled: canSave) {
                    Task { await save() }
                }
            }
        }
        .padding(.bottom, TFSpacing.xl)
        .onChange(of: pickerItem) { _, item in
            Task { await uploadPhoto(item) }
        }
    }

    /// Крупная аватарка по центру, под ней «Сменить фото» и «Убрать фото».
    private var photoBlock: some View {
        VStack(spacing: TFSpacing.sm) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                TFAvatar(
                    size: .profile,
                    initials: user.initials ?? "?",
                    tint: (user.avatarColor).map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned),
                    urlPath: avatarURL,
                    portrait: true,
                    zoomable: false
                )
            }
            .accessibilityLabel("Сменить фото")
            HStack(spacing: TFSpacing.lg) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(isPhotoBusy ? "Загружаю…" : "Сменить фото")
                        .tfText(.action)
                        .foregroundStyle(Color.tfRed)
                        .frame(minHeight: 44)
                }
                if avatarURL != nil {
                    Button {
                        Task { await removePhoto() }
                    } label: {
                        Text("Убрать фото")
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(TFTapFadeStyle())
                }
            }
            .disabled(isPhotoBusy || isSaving)
        }
        .frame(maxWidth: .infinity)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedLogin: String { login.trimmingCharacters(in: .whitespaces).lowercased() }

    private var canSave: Bool {
        guard !isSaving, !trimmedName.isEmpty, !trimmedLogin.isEmpty else { return false }
        return trimmedName != user.name
            || trimmedLogin != (user.email ?? "").lowercased()
            || !newPassword.isEmpty
    }

    private func save() async {
        errorMessage = nil
        if !newPassword.isEmpty {
            if newPassword.count < 4 { errorMessage = "Новый пароль — минимум 4 символа"; return }
            if newPassword != repeatPassword { errorMessage = "Пароли не совпадают"; return }
            if currentPassword.isEmpty { errorMessage = "Чтобы сменить пароль, введите текущий"; return }
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await settings.saveProfile(
                name: trimmedName,
                avatarColor: nil,
                email: trimmedLogin,
                password: newPassword.isEmpty ? nil : newPassword,
                currentPassword: newPassword.isEmpty ? nil : currentPassword
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil
        isPhotoBusy = true
        defer { isPhotoBusy = false; pickerItem = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let data = avatarJPEG(from: raw) else {
                errorMessage = "Не удалось прочитать картинку"
                return
            }
            onAvatarChanged(try await settings.uploadAvatar(data: data, mime: "image/jpeg"))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removePhoto() async {
        errorMessage = nil
        isPhotoBusy = true
        defer { isPhotoBusy = false }
        do {
            try await settings.deleteAvatar()
            onAvatarChanged("")
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Имя и логин — одна карточка с разделителем, как группы полей задачи.
private struct ProfileNameLoginFields: View {
    @Binding var name: String
    @Binding var login: String

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("Имя и вход")
            TFFieldGroup {
                TFTextField("Имя", text: $name, icon: "person")
                    .textContentType(.name)
                TFFieldDivider()
                TFTextField("Логин (почта)", text: $login, icon: "envelope")
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }
}

/// Смена пароля: текущий, новый, повтор. Пустые поля — пароль не меняется.
private struct ProfilePasswordFields: View {
    @Binding var current: String
    @Binding var new: String
    @Binding var repeated: String

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            SettingsCapsLabel("Сменить пароль")
            TFFieldGroup {
                ProfileSecureField(placeholder: "Текущий пароль", text: $current, contentType: .password)
                TFFieldDivider()
                ProfileSecureField(placeholder: "Новый пароль", text: $new, contentType: .newPassword)
                TFFieldDivider()
                ProfileSecureField(placeholder: "Повторите новый", text: $repeated, contentType: .newPassword)
            }
            Text("Не меняете пароль — оставьте поля пустыми.")
                .tfText(.meta)
                .foregroundStyle(Color.tfDim)
        }
    }
}

/// Скрытое поле в той же геометрии, что `TFTextField` (у него скрытого
/// режима нет): иконка-замок, отступы и высота поля из токенов.
private struct ProfileSecureField: View {
    let placeholder: String
    @Binding var text: String
    let contentType: UITextContentType

    @ScaledMetric(relativeTo: .callout) private var minHeight: CGFloat = TFField.height
    @ScaledMetric(relativeTo: .callout) private var iconSize: CGFloat = TFIconSize.sm

    var body: some View {
        HStack(spacing: TFField.iconTextGap) {
            Image(systemName: "lock")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.tfDim)
            SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.tfDim))
                .tfText(.input)
                .foregroundStyle(Color.tfText)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, TFSpacing.lg)
        .frame(minHeight: minHeight)
    }
}

/// Фото из галереи → JPEG не крупнее 1024 px: сервер принимает до 5 МБ
/// png/jpeg/webp/gif, а галерея отдаёт HEIC и большие кадры.
fileprivate func avatarJPEG(from raw: Data) -> Data? {
    guard let image = UIImage(data: raw) else { return nil }
    let longSide = max(image.size.width, image.size.height)
    let scale = longSide > 1024 ? 1024 / longSide : 1
    let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let resized = UIGraphicsImageRenderer(size: target).image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
    return resized.jpegData(compressionQuality: 0.85)
}

/// Кружок аватарки в шапке профиля — тап открывает `PhotosPicker` (смена
/// фото), рядом кнопка «Изменить» (имя + убрать фото, шторка выше).
///
/// «Убрать фото» раньше была тут же отдельной кнопкой — просьба владельца
/// 03.09.2026, см. комментарий у `EditProfileSheet`: перенесена внутрь
/// правки, здесь остался только прямой тап по самой аватарке (загрузка).
struct ProfileAccountRow: View {
    let user: ApiUser
    let avatarURLOverride: String?
    let onEdit: () -> Void
    let onAvatarChanged: (String?) -> Void

    @Environment(SettingsViewModel.self) private var settings
    @State private var pickerItem: PhotosPickerItem?
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var avatarURL: String? { avatarURLOverride ?? user.avatarUrl }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            HStack(spacing: TFSpacing.md) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    avatarView
                }
                .disabled(isBusy)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .tfText(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.tfText)
                    if let email = user.email {
                        Text(email)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Изменить", action: onEdit)
                    .buttonStyle(.plain)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfText)
                    .padding(.horizontal, TFSpacing.sm)
                    .padding(.vertical, TFSpacing.xs)
                    .background(Color.tfCard2)
                    .overlay(RoundedRectangle(cornerRadius: TFRadius.md).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
            }
            TFErrorBanner(errorMessage)
        }
        .padding(.horizontal, TFSpacing.lg)
        .padding(.vertical, TFSpacing.md)
        .onChange(of: pickerItem) { _, newItem in
            Task { await upload(newItem) }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        // Раньше здесь был `AsyncImage(URL(string: "/api/avatars/…"))`: адрес
        // относительный, без сервера, картинка не грузилась и всегда рисовалась
        // буква (владелец 06.10.2026: «почему М»). `TFAvatar` сам дописывает
        // адрес сервера и кеширует.
        TFAvatar(
            size: .profile,
            initials: user.initials ?? "?",
            tint: (user.avatarColor).map { Color(hex: $0) } ?? Color(hex: TFHexDefault.unassigned),
            urlPath: avatarURL,
            portrait: true,
            zoomable: false
        )
    }

    private func upload(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            guard let data = avatarJPEG(from: raw) else {
                errorMessage = "Не удалось прочитать картинку"
                return
            }
            let url = try await settings.uploadAvatar(data: data, mime: "image/jpeg")
            onAvatarChanged(url)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
