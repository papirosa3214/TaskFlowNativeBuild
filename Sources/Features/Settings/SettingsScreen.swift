import SwiftUI

/// `/settings` — spec/SCREENS-2.md §6. Дерево настроек: профиль, тема/
/// биометрия/иконка/шаблоны/метки, ИИ и команда, сервер с интеграциями, выход.
///
/// Шапка — `SettingsHeaderChrome` (своя композиция, не `TFScreenHeader`):
/// см. комментарий в файле компонента — веб держит здесь `variant="large"`
/// (по умолчанию) СО стрелкой «назад» (правило добавлено в
/// `ScreenHeader.tsx` 27.08.2026), а нативный `TFScreenHeader.large` стрелку
/// не рисует вовсе — гэп, не мой файл чинить.
struct SettingsScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @State private var appIconSheetOpen = false
    @State private var appIcon: AppIconOption = .current
    @Environment(SessionStore.self) private var session
    @State private var viewModel = SettingsViewModel()
    @State private var profileOverride: ApiUser?
    @AppStorage("settings.user.expanded") private var userSettingsExpanded = true
    @AppStorage("settings.ai.expanded") private var aiExpanded = true
    @AppStorage(SecretaryVoice.storageKey) private var secretaryVoice = SecretaryVoice.default.rawValue
    @AppStorage("settings.server.expanded") private var serverExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.xl) {
                    accountSection
                    userSettingsSection
                    aiSection
                    serverSection
                    signOutSection
                }
                .padding(.vertical, TFSpacing.lg)
            }
        }
        // Своя шапка уже несёт заголовок и кнопку «назад» — системный навбар
        // поверх неё давал ВТОРУЮ стрелку и лишнюю полосу.
        // Нативная сворачивающаяся шапка по официальным гайдам SwiftUI.
        .tfNativeHeader("Настройки")
        .background(Color.tfBackground)
        .environment(viewModel)
        .tfBottomSheet(isPresented: $appIconSheetOpen) {
            AppIconPickerSheet(selection: $appIcon) { appIconSheetOpen = false }
        }
    }

    private var displayedUser: ApiUser? { profileOverride ?? session.currentUser }

    @ViewBuilder
    private var accountSection: some View {
        Group {
            if let user = displayedUser {
                // Владелец 20.10.2026: профиль — отдельный экран по шеврону,
                // как остальные пункты, а не шторка.
                NavigationLink {
                    EditProfileScreen(
                        user: user,
                        avatarURLOverride: profileOverride?.avatarUrl,
                        settings: viewModel,
                        onSaved: { updated in profileOverride = updated },
                        onAvatarChanged: { newURL in patchAvatarURL(newURL, baseUser: user) }
                    )
                } label: {
                    ProfileAccountRow(user: user, avatarURLOverride: profileOverride?.avatarUrl)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.profile")
            } else {
                TFListRow(icon: "person", iconStyle: .plain, title: "Аккаунт")
            }
        }
        .padding(.horizontal, TFSpacing.screenHorizontal)
    }

    /// Общий патч локального вида после смены/удаления фото — переиспользуют
    /// и строка профиля (тап по аватарке), и шторка «Изменить» (кнопка
    /// «Убрать фото», просьба владельца 03.09.2026 — см. `EditProfileSheet`).
    /// `SessionStore.currentUser` не обновляем (нет публичного сеттера),
    /// только локальный вид (`profileOverride`).
    private func patchAvatarURL(_ newURL: String?, baseUser: ApiUser) {
        let patched = displayedUser ?? baseUser
        profileOverride = ApiUser(
            id: patched.id, name: patched.name, email: patched.email,
            role: patched.role, type: patched.type, avatarColor: patched.avatarColor,
            initials: patched.initials, status: patched.status, createdAt: patched.createdAt,
            isSystemBot: patched.isSystemBot, createdBy: patched.createdBy,
            avatarUrl: newURL?.isEmpty == false ? newURL : nil,
            avatarUrlWorking: patched.avatarUrlWorking, avatarUrlBlocked: patched.avatarUrlBlocked,
            lastSeenAt: patched.lastSeenAt, activity: patched.activity, online: patched.online,
            lastAction: patched.lastAction, lastActionTitle: patched.lastActionTitle, limits: patched.limits
        )
    }

    private var darkThemeBinding: Binding<Bool> {
        Binding(
            get: {
                let appearance = AppAppearance(rawValue: appearanceRaw) ?? .dark
                return (appearance.colorScheme ?? colorScheme) == .dark
            },
            set: { isDark in
                appearanceRaw = (isDark ? AppAppearance.dark : .light).rawValue
            }
        )
    }

    @ViewBuilder
    private var userSettingsSection: some View {
        section(title: "Пользовательские настройки", isExpanded: $userSettingsExpanded) {
            TFListRow(
                icon: "moon", iconStyle: .plain, title: "Тема",
                trailing: AnyView(
                    TFToggle(isOn: darkThemeBinding)
                        .accessibilityLabel("Тёмная тема")
                        .accessibilityIdentifier("settings.appearance")
                ),
                titleStyle: .action,
                verticalPadding: TFSpacing.xs
            )
            TFDivider(inset: rowDividerInset)
            HintsSettingsSection(dividerInset: rowDividerInset)
            if viewModel.isBiometryAvailable {
                TFDivider(inset: rowDividerInset)
                toggleRow(icon: viewModel.biometryKind == .faceID ? "faceid" : "touchid", title: viewModel.biometryLabel, isOn: $viewModel.isBiometryEnabled)
            }
            TFDivider(inset: rowDividerInset)
            Button {
                appIconSheetOpen = true
            } label: {
                TFListRow(icon: "photo", iconStyle: .plain, title: "Иконка",
                          trailing: AnyView(editAction), titleStyle: .action,
                          verticalPadding: TFSpacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.app-icon")
            if session.currentUser?.role == .owner {
                TFDivider(inset: rowDividerInset)
                navRow(icon: "bell.badge", title: "Напоминания о просрочке", route: .escalationSettings)
                    .accessibilityIdentifier("settings-escalation")
            }
            TFDivider(inset: rowDividerInset)
            toggleRow(icon: "rectangle.bottomhalf.filled", title: "Системный таббар",
                      isOn: $viewModel.isPillTabBarEnabled, toggleIdentifier: "settings.pillTabBar")
            // Владелец 20.10.2026: «Шаблоны задач» и «Метки» — из «Общих» сюда.
            TFDivider(inset: rowDividerInset)
            navRow(icon: "bookmark", title: "Шаблоны задач", route: .templates)
            TFDivider(inset: rowDividerInset)
            navRow(icon: "tag", title: "Метки", route: .labels)
        }
    }

    @ViewBuilder
    /// LOCK-179: ИИ разделён на СЕРВЕРНЫЙ (провайдеры и модели Pi) и
    /// ЛОКАЛЬНЫЙ («На устройстве»). Раньше единственная строка вела в
    /// `VoiceModelsScreen` — локальные модели; теперь это разные пункты.
    private var aiSection: some View {
        section(title: "Искусственный интеллект", isExpanded: $aiExpanded) {
            // Владелец 20.10.2026: «Команда» — из «Общих» сюда.
            navRow(icon: "person.3.fill", title: "Команда", route: .agents)
            TFDivider(inset: rowDividerInset)
            if session.currentUser?.role == .owner {
                navRow(icon: "checkmark.shield", title: "Оценщик JEV", route: .jevSettings)
                    .accessibilityIdentifier("settings-jev")
                TFDivider(inset: rowDividerInset)
            }
            navRow(icon: "cpu", title: "Агенты (модели и провайдеры)", route: .runtimeProviders)
            TFDivider(inset: rowDividerInset)
            navRow(icon: "iphone", title: "Приложение (телефон и сервер)", route: .voiceModels)
            TFDivider(inset: rowDividerInset)
            NavigationLink(value: AppRoute.secretaryVoicePicker) {
                TFListRow(icon: "waveform", iconStyle: .plain, title: "Голос Помощника владельца",
                          trailing: AnyView(secretaryVoiceValue), titleStyle: .action,
                          verticalPadding: TFSpacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.secretary-voice")
        }
    }

    /// Текущий голос + шеврон: выбор и прослушивание — на отдельном экране.
    private var secretaryVoiceValue: some View {
        HStack(spacing: TFSpacing.sm) {
            Text(secretaryVoice).tfText(.body).foregroundStyle(Color.tfSub)
            chevron
        }
    }

    @ViewBuilder
    /// LOCK-180/181: к серверным строкам добавлены «Pi Runtime» (статус
    /// рантайма) и «Service Accounts» (переехавшая из «Команды» механика
    /// ApiUser/токена).
    private var serverSection: some View {
        section(title: "Сервер", isExpanded: $serverExpanded) {
            if session.currentUser?.role == .owner {
                navRow(icon: "slider.horizontal.3", title: "Параметры", route: .serverSettings)
                    .accessibilityIdentifier("settings-server-parameters")
                TFDivider(inset: rowDividerInset)
                SystemControlSection()
                TFDivider(inset: rowDividerInset)
                ServerRestartRow()
                TFDivider(inset: rowDividerInset)
            }
            ServerStatusSection()
            TFDivider(inset: rowDividerInset)
            RuntimeStatusRow()
            TFDivider(inset: rowDividerInset)
            navRow(icon: "person.badge.key", title: "Сервер MCP", route: .serviceAccounts)
            TFDivider(inset: rowDividerInset)
            // Правка 8 плана taskflow-mac-host: удалённые машины-хосты.
            // Только владельцу: завести и отозвать машину может он, и реестр
            // машин (`server/src/routes/hosts.ts`) тоже закрыт authOrApiToken.
            if session.currentUser?.role == .owner {
                // 16.10.2026, LOCK-REMOTE-MACHINES-ROW: пункт с шевроном и
                // переходом на свой экран, как «Параметры» и «Сервер MCP».
                // До этого здесь стоял блок с машинами прямо в потоке, и его
                // ошибка загрузки с «Повторить» выкатывалась прямо сюда.
                navRow(icon: "desktopcomputer", title: "Удалённые машины", route: .remoteMachines)
                    .accessibilityIdentifier("settings-remote-machines")
            }
            // Владелец 20.10.2026: «Интеграции» — из «Общих» сюда.
            TFDivider(inset: rowDividerInset)
            navRow(icon: "link", title: "Интеграции", route: .integrations)
        }
    }

    @ViewBuilder
    private var signOutSection: some View {
        Button(role: .destructive) {
            session.logout()
        } label: {
            // Владелец 20.10.2026: шрифт и отступ подзаголовков разделов,
            // цвет обычный — не красный.
            HStack {
                Text("Выйти")
                    .tfSectionDisplay(style: .taskTitle)
                Spacer()
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Общие строители строк

    private func section<Content: View>(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.sm) {
            Button { isExpanded.wrappedValue.toggle() } label: {
                // Владелец 20.10.2026: подзаголовки — крупным шрифтом
                // разделов «Обзора» (`tfSectionDisplay(style: .taskTitle)`).
                Text(title)
                    .tfSectionDisplay(style: .taskTitle)
                    .padding(.horizontal, TFSpacing.screenHorizontal)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded.wrappedValue ? "Развернут" : "Свернут")
            if isExpanded.wrappedValue {
                TFCard(padding: 0) { VStack(spacing: 0) { content() } }
                    .padding(.horizontal, TFSpacing.screenHorizontal)
            }
        }
    }

    private func navRow(icon: String, title: String, route: AppRoute) -> some View {
        NavigationLink(value: route) {
            TFListRow(icon: icon, iconStyle: .plain, title: title, trailing: AnyView(chevron), titleStyle: .action, verticalPadding: TFSpacing.xs)
        }
        .buttonStyle(.plain)
    }

    /// Шеврон рисуется вручную через `trailing`, а не через `action` у
    /// `TFListRow`: тап-зону и переход уже даёт обёртывающий `NavigationLink`,
    /// вложенный `Button` внутри него задвоил бы жест (см. INTEGRATION.md —
    /// переходы только `NavigationLink(value:)`).
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13))
            .foregroundStyle(Color.tfDim)
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>, toggleIdentifier: String? = nil) -> some View {
        TFListRow(
            icon: icon, iconStyle: .plain, title: title,
            trailing: AnyView(
                Group {
                    if let toggleIdentifier {
                        TFToggle(isOn: isOn).accessibilityIdentifier(toggleIdentifier)
                    } else {
                        TFToggle(isOn: isOn)
                    }
                }
            ),
            titleStyle: .action,
            verticalPadding: TFSpacing.xs
        )
    }

    private var editAction: some View {
        Text("Изменить")
            .tfText(.meta)
            .foregroundStyle(Color.tfText)
            .padding(.horizontal, TFSpacing.sm)
            .padding(.vertical, TFSpacing.xs)
            .background(Color.tfCard2)
            .overlay(RoundedRectangle(cornerRadius: TFRadius.md).strokeBorder(Color.tfStroke, lineWidth: TFBorder.width))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
    }

    private var rowDividerInset: CGFloat { TFSpacing.lg + 40 + TFSpacing.md }
}
