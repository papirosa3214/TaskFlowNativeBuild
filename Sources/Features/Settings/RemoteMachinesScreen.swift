import SwiftUI
import Observation

/// Экран «Удалённые машины» — план taskflow-mac-host.
///
/// 16.10.2026, владелец (телефон, раздел «Сервер»): «Какие, блядь, машин?
/// Чего за повторить, кого я тут повторю в разделе "Сервер"? Почему здесь нет
/// раздела "Удаленный хост", куда я нажимаю, и вот потом выкатывается вот
/// такая вот "не удалось прочитать список машин"».
///
/// Секция была вставлена прямо в поток карточки «Сервер» — без заголовка, без
/// шеврона и без перехода. Из-за этого её ошибка загрузки и кнопка «Повторить»
/// выкатывались на первый экран настроек и выглядели так, будто относятся к
/// самому «Серверу». Остальные пункты этой секции — обычные `navRow` с
/// шевроном, ведущие на свои экраны; машины теперь такой же пункт.
///
/// Экран отвечает на один вопрос: подключён ли MacBook и что ему разрешено.
/// Никаких ключей и команд — ключ живёт в Keychain на самой машине, а
/// сопряжение делается по QR тем же кодом, что и у телефона.
///
/// Модель данных и строка машины живут в `RemoteMachinesModel.swift`
/// и в этом же файле (`LOCK-UI-DRIFT-GATE`): перенос сюда — только экрана,
/// логика не менялась.
struct RemoteMachinesScreen: View {
    @State private var viewModel = RemoteMachinesViewModel()

    var body: some View {
        // Урок 2026-09-25 (чёрные треугольники в углах системной клавиатуры,
        // iOS 26): фон одним слоем на самом верху тела экрана, `ZStack` +
        // `.ignoresSafeArea()` без ограничения edges.
        ZStack {
            Color.tfBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.lg) {
                    content
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.top, TFSpacing.md)
                .padding(.bottom, TFSpacing.xl)
            }
        }
        .tfNativeHeader("Удалённые машины")
        .accessibilityIdentifier("remote-machines-screen")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            TFLoading(.block)
        case .failed:
            // Сообщение и действие принадлежат ЭТОМУ экрану, а не списку
            // настроек: здесь «Повторить» читается однозначно — повторить
            // загрузку списка машин.
            VStack(alignment: .leading, spacing: TFSpacing.md) {
                TFErrorBanner("Не удалось прочитать список машин", variant: .block)
                    .accessibilityIdentifier("remote-machines-error")
                TFButton("Повторить", icon: "arrow.clockwise", variant: .secondary) {
                    Task { await viewModel.load() }
                }
                .accessibilityIdentifier("remote-machines-retry")
            }
        case .loaded:
            loaded
        }
    }

    @ViewBuilder
    private var loaded: some View {
        Text("Макины-хосты, которым TaskFlow отдал работу на этой сети. Ключ хранится в Keychain на самой машине, здесь его нет — сопряжение идёт по коду.")
            .tfText(.caption)
            .foregroundStyle(Color.tfSub)

        if viewModel.machines.isEmpty {
            TFEmptyState(
                text: "Машин пока нет",
                description: "Поставьте taskflow-host на мак — он сам покажет код для сопряжения."
            )
        } else {
            TFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.machines.enumerated()), id: \.element.id) { index, машина in
                        if index > 0 { TFDivider(inset: TFSpacing.lg + 40 + TFSpacing.md) }
                        MachineRow(машина: машина) {
                            Task { await viewModel.отключить(машина) }
                        }
                            .padding(.vertical, TFSpacing.xs)
                            .accessibilityIdentifier("remote-machines-row-\(машина.name)")
                    }
                }
            }
        }

        TFButton(
            viewModel.macOnLine ? "Сопрячь ещё одну машину" : "Подключить MacBook",
            icon: "qrcode",
            variant: .secondary,
            isEnabled: !viewModel.идётОбмен
        ) {
            Task { await viewModel.выдатьКодСопряжения() }
        }
        .accessibilityIdentifier("remote-machines-pair")

        if let отказ = viewModel.отказОбмена {
            TFErrorBanner(отказ, variant: .block)
                .accessibilityIdentifier("remote-machines-pair-error")
        }

        if let код = viewModel.кодСопряжения {
            pairingCodeView(код)
        }
    }

    /// Код для сканирования телефоном. Показываем и текстом, и картинкой:
    /// сканировать с этого же телефона нельзя, а ввести руками — можно.
    private func pairingCodeView(_ код: PairingCodeResponse) -> some View {
        TFCard(padding: TFSpacing.md, surface: .card2, radius: TFRadius.md) {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text("Отсканируй этот код на маке (или введи вручную):")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)

                Text(код.code)
                    .tfText(.title)
                    .monospaced()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("remote-machines-code")

                Text("Код действует \(viewModel.секундДоИстечения / 60) мин \(viewModel.секундДоИстечения % 60) с")
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Строка «удалённый хост»: индикатор связи и подпись последнего контакта.
/// Вынесена из `RemoteMachinesModel.swift` без изменений — на новом экране
/// ей нужен тот же вид, а правило проекта: одна правка — одно место.
struct MachineRow: View {
    let машина: RemoteMachine
    /// Действие «убрать запись». Владелец 18.10.2026: удалить машину из
    /// настроек было нечем, поэтому в списке навсегда висели отозванные
    /// тестовые записи. Зажатие строки открывает меню — как он и просил.
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: TFSpacing.md) {
            Image(systemName: машина.online ? "desktopcomputer" : "desktopcomputer.trianglebadge.exclamationmark")
                .foregroundStyle(машина.online ? Color.green : Color.secondary)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(машина.имяДляЧеловека)
                    .tfText(.body)
                    .foregroundStyle(Color.tfText)
                Text(подпись)
                    .tfText(.meta)
                    .foregroundStyle(Color.tfSub)
            }

            Spacer(minLength: TFSpacing.sm)

            if let префикс = машина.tokenPrefix {
                Text(префикс)
                    .tfText(.caption)
                    .monospaced()
                    .foregroundStyle(Color.tfSub)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label(машина.revokedAt == nil ? "Отключить и убрать запись" : "Убрать запись", systemImage: "trash")
                }
            }
        }
        .accessibilityHint(машина.revokedAt == nil ? "Удерживайте, чтобы отключить" : "Удерживайте, чтобы убрать запись")
    }

    /// «на связи» / «нет связи» — словами, а не только цветом: индикатор
    /// без подписи для незрячего пользователя не значит ничего.
    private var подпись: String {
        if машина.revokedAt != nil { return "отключено" }
        guard машина.online else { return "нет связи" }
        guard let префикс = машина.tokenPrefix else { return "на связи" }
        return "на связи · ключ \(префикс)…"
    }
}
