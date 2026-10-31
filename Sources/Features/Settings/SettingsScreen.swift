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
    @AppStorage(TFTextTone.storageKey) private var textToneRaw = TFTextTone.pure.rawValue
    @AppStorage(TFTextScale.storageKey) private var textScaleRaw = TFTextScale.standard.rawValue
    @State private var typeRevision = 0
    /// Панель ввода в чатах: родная или новая (владелец 29.10.2026).
    @AppStorage(ChatComposerStyle.storageKey) private var composerStyleRaw = ChatComposerStyle.defaultStyle.rawValue
    /// Тумблер «Новая панель ввода» — как у нижней панели: включена новая,
    /// выключена родная.
    private var composerStyleBinding: Binding<Bool> {
        Binding(
            get: { ChatComposerStyle.resolve(composerStyleRaw) == .unified },
            set: { composerStyleRaw = ($0 ? ChatComposerStyle.unified : .standard).rawValue }
        )
    }
    @AppStorage("settings.appearance.expanded") private var appearanceExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.xl) {
                    accountSection
                    appearanceSection
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

    // MARK: - Внешний вид (просьба владельца 28.10.2026)

    /// Образцы ступеней шкалы для выбора размера: кегль берётся из `Typography`,
    /// а не задаётся числом в разметке (правило дизайн-системы).
    private static let scaleSamples: [TFTextStyle] = [.action, .body, .title, .titleLarge]

    /// Тон основного текста и размер шрифта на всё приложение. Обе настройки
    /// живут в `@AppStorage`: тон читает токен `tfText` в корне приложения,
    /// размер — `.dynamicTypeSize(...)` там же.
    @ViewBuilder
    private var appearanceSection: some View {
        section(title: "Внешний вид", isExpanded: $appearanceExpanded) {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text("Тон текста")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
                HStack(spacing: TFSpacing.sm) {
                    ForEach(TFTextTone.allCases) { tone in
                        let isSelected = textToneRaw == tone.rawValue
                        Button { textToneRaw = tone.rawValue } label: {
                            VStack(spacing: TFSpacing.xs) {
                                Text("Аа")
                                    .tfText(.title)
                                    .foregroundStyle(tone.color)
                                    .frame(maxWidth: .infinity, minHeight: TFHitTarget.min)
                                    .background(Color.tfCard2)
                                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.md))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: TFRadius.md)
                                            .strokeBorder(isSelected ? Color.tfRed : Color.tfStroke,
                                                          lineWidth: isSelected ? 2 : TFBorder.width)
                                    )
                                Text(tone.title)
                                    .tfText(.micro)
                                    .foregroundStyle(isSelected ? Color.tfText : Color.tfDim)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.text-tone.\(tone.rawValue)")
                    }
                }
            }
            .padding(.horizontal, TFSpacing.md)
            .padding(.vertical, TFSpacing.md)

            TFDivider(inset: rowDividerInset)
            Text("Размер текста")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.md)
                .padding(.top, TFSpacing.md)
            ForEach(Array(TFTextScale.allCases.enumerated()), id: \.element.id) { index, scale in
                if index > 0 { TFDivider(inset: rowDividerInset) }
                let isSelected = textScaleRaw == scale.rawValue
                Button { textScaleRaw = scale.rawValue } label: {
                    HStack(spacing: TFSpacing.md) {
                        Text("Аа")
                            .tfText(Self.scaleSamples[index])
                            .foregroundStyle(Color.tfText)
                            .frame(width: 34, alignment: .leading)
                        Text(scale.title)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.tfRed)
                        }
                    }
                    .padding(.horizontal, TFSpacing.md)
                    .frame(minHeight: TFHitTarget.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.text-scale.\(scale.rawValue)")
            }

            // Гарнитура (владелец, 01.11.2026): 11 шрифтов с кириллицей.
            TFDivider(inset: rowDividerInset)
            Text("Гарнитура")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.md)
                .padding(.top, TFSpacing.md)
            faceRow

            // Шрифты по пяти группам (владелец, 01.11.2026): заголовок,
            // подзаголовок, основной, второстепенный, мелкий. Чаты настройку
            // не читают: их корни ставят `.tfChatTypography()`.
            TFDivider(inset: rowDividerInset)
            Text("Шрифты")
                .tfText(.meta)
                .foregroundStyle(Color.tfSub)
                .padding(.horizontal, TFSpacing.md)
                .padding(.top, TFSpacing.md)
            ForEach(Array(TFTypeGroup.allCases.enumerated()), id: \.element.id) { index, group in
                if index > 0 { TFDivider(inset: rowDividerInset) }
                typeGroupRow(group)
            }
        }
    }

    /// Строка выбора гарнитуры: образец рисуется самим шрифтом.
    private var faceRow: some View {
        let current = TFTypeFace.saved
        return Menu {
            ForEach(TFTypeFace.allCases) { face in
                Button {
                    UserDefaults.standard.set(face.rawValue, forKey: TFTypeFace.storageKey)
                    typeRevision &+= 1
                } label: {
                    Text(face.title + " — " + face.subtitle)
                }
            }
        } label: {
            HStack(spacing: TFSpacing.md) {
                Text("Аа")
                    .font(current.font(size: 21, weight: .regular))
                    .foregroundStyle(Color.tfText)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.title)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                    Text(current.subtitle)
                        .tfText(.micro)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
                Spacer(minLength: TFSpacing.sm)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))  // design-system-guard: ignore — значок меню
                    .foregroundStyle(Color.tfDim)
            }
            .padding(.horizontal, TFSpacing.md)
            .frame(minHeight: TFHitTarget.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.type-face")
    }

    /// Строка одной группы шрифтов: образец в её кегле и меню со ступенями.
    private func typeGroupRow(_ group: TFTypeGroup) -> some View {
        let current = TFTypeScale.saved(for: group)
        return Menu {
            ForEach(TFTypeScale.allCases) { scale in
                Button {
                    TFTypeScale.save(scale, for: group)
                    typeRevision &+= 1
                } label: {
                    Text(scale.title + " " + String(Int((group.baseSize * scale.multiplier).rounded())))
                }
            }
        } label: {
            HStack(spacing: TFSpacing.md) {
                Text("Аа")
                    // design-system-guard: ignore — образец обязан быть ровно в кегле своей группы
                    .font(.system(size: group.baseSize * current.multiplier, weight: .regular))
                    .foregroundStyle(Color.tfText)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title)
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                    Text(group.subtitle)
                        .tfText(.micro)
                        .foregroundStyle(Color.tfSub)
                        .lineLimit(1)
                }
                Spacer(minLength: TFSpacing.sm)
                Text(current.title)
                    .tfText(.action)
                    .foregroundStyle(Color.tfDim)
            }
            .padding(.horizontal, TFSpacing.md)
            .frame(minHeight: TFHitTarget.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.type-group.\(group.rawValue)")
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
            // Панель ввода в чатах — по образцу таббара выше: родная или новая
            // (владелец 29.10.2026: «переключатель сделать наподобие, как вот
            // эта нижняя таб-бар»).
            TFDivider(inset: rowDividerInset)
            toggleRow(icon: "text.bubble", title: "Новая панель ввода",
                      isOn: composerStyleBinding, toggleIdentifier: "settings.chat-composer-style")
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
                navRow(icon: "key", title: "Секреты", route: .secrets)
                    .accessibilityIdentifier("settings-server-secrets")
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
            NavigationLink(value: AppRoute.integrations) {
                TFListRow(icon: "link", iconStyle: .asset("IntegrationsLink"), title: "Интеграции", trailing: AnyView(chevron), titleStyle: .action, verticalPadding: TFSpacing.xs)
            }
            .buttonStyle(.plain)
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
