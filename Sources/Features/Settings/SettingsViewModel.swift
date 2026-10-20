import Foundation
import Observation
import LocalAuthentication

/// Вью-модель `SettingsScreen` — spec/SCREENS-2.md §6.
///
/// Профиль читается из `SessionStore` (общий стор, инъекция через
/// `@Environment`, как у `TodayViewModel`), а вот тема/биометрия — ЛОКАЛЬНЫЕ
/// настройки устройства (спец §6: «сохраняются на устройстве»), под которые
/// в `Core` пока нет общего хранилища настроек. По задаче: «если готового
/// способа хранения ещё нет — положи в UserDefaults у себя и отметь это в
/// отчёте» — так и сделано, ключи ниже.
@MainActor
@Observable
final class SettingsViewModel {
    private let apiClient: APIClient

    /// Биометрия — spec §6: строка видна только если физически доступна.
    var biometryKind: LABiometryType = .none
    var isBiometryAvailable: Bool { biometryKind != .none }
    var biometryLabel: String {
        biometryKind == .faceID ? "Вход по Face ID" : "Вход по Touch ID"
    }
    var isBiometryEnabled: Bool {
        didSet { UserDefaults.standard.set(isBiometryEnabled, forKey: Self.biometryKey) }
    }

    /// Своя экранная клавиатура (`Sources/Keyboard/`, пишет другой
    /// исполнитель) — ключ зафиксирован здесь, поскольку раздел «Пользовательские
    /// настройки» — моя территория. Имя ключа — в отчёт оркестратору, чтобы
    /// исполнитель клавиатуры читал/писал именно его через `UserDefaults.standard`,
    /// а не заводил свой параллельный.
    ///
    /// 18.10.2026, владелец: строку тумблера «Своя клавиатура» в настройках
    /// заменили на «Таббар-пилюля» — клавиатура в приложении не показывалась, а
    /// ручка была пустой. Свойство и ключ остались: клавиатура по-прежнему
    /// читает их напрямую, минуя этот экран.
    var isCustomKeyboardEnabled: Bool {
        didSet { UserDefaults.standard.set(isCustomKeyboardEnabled, forKey: Self.customKeyboardKey) }
    }

    /// Системный TabView Apple вместо прежнего таббара (владелец 18.10.2026).
    /// Ключ общий с `RootShellView` — панель переключается на лету, без
    /// перезапуска приложения.
    var isPillTabBarEnabled: Bool {
        didSet { UserDefaults.standard.set(isPillTabBarEnabled, forKey: Self.pillTabBarKey) }
    }

    var errorMessage: String?

    static let customKeyboardKey = "taskflow_custom_keyboard_enabled"
    static let pillTabBarKey = "taskflow_tabbar_pill_enabled"
    private static let biometryKey = "taskflow_settings_biometry_enabled"

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
        isBiometryEnabled = UserDefaults.standard.bool(forKey: Self.biometryKey)
        // Своя клавиатура по умолчанию выключена: пока она не проверена на
        // живом телефоне, системная остаётся основной.
        isCustomKeyboardEnabled = UserDefaults.standard.bool(forKey: Self.customKeyboardKey)
        // Пилюля — по умолчанию: владелец 18.10.2026 просил именно её. Ключа в
        // UserDefaults ещё нет → тумблер новый, показываем пилюлю.
        if let stored = UserDefaults.standard.object(forKey: Self.pillTabBarKey) as? Bool {
            isPillTabBarEnabled = stored
        } else {
            isPillTabBarEnabled = true
        }
        detectBiometry()
    }

    private func detectBiometry() {
        let context = LAContext()
        var evalError: NSError?
        // `canEvaluatePolicy` не запрашивает разрешение — только проверяет
        // физическое наличие сенсора, ровно то, что нужно строке-условию
        // «биометрия физически доступна» (spec §6).
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &evalError)
        biometryKind = context.biometryType
    }

    /// `PUT /auth/profile` уже есть в `APIClient+Auth.swift`
    /// (`updateProfile(name:avatarColor:)`) — вызывается прямо отсюда.
    /// `SessionStore.currentUser` при этом НЕ обновляется: свойство
    /// `private(set)`, публичного метода «обновить текущего пользователя»
    /// в сторе нет (только `login`/`logout`/`bootstrap`). Правка чужого
    /// файла не по адресу этой папки, поэтому `SettingsScreen` держит свой
    /// локальный override поверх `session.currentUser` для немедленного
    /// отображения — до следующего перезапуска приложения (новый
    /// `bootstrap()` подтянет актуальное с сервера). Гэп — в отчёт
    /// оркестратору: стоило бы завести `SessionStore.refreshProfile()`.
    func saveProfile(
        name: String,
        avatarColor: String?,
        email: String? = nil,
        password: String? = nil,
        currentPassword: String? = nil
    ) async throws -> ApiUser {
        try await apiClient.updateProfile(
            name: name, avatarColor: avatarColor, email: email,
            password: password, currentPassword: currentPassword
        )
    }

    func uploadAvatar(data: Data, mime: String) async throws -> String {
        try await apiClient.uploadAvatar(data: data, mime: mime).avatarUrl
    }

    func deleteAvatar() async throws {
        try await apiClient.deleteAvatar()
    }
}
