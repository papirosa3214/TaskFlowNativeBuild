import SwiftUI

/// Правка 9 плана taskflow-mac-host: «Где выполнять — сервер или машина».
///
/// Отдельный компонент, а не ещё одна строка в `SubtaskFeedView`: выбор
/// машины нужен и в шаге, и в подзадаче, и правила показа (нельзя менять на
/// идущем шаге, нельзя выбрать офлайн-машину) одинаковы — держать их в
/// одном месте дешевле, чем дублировать.

/// Машина в том виде, в каком её знает UI. Сервер отдаёт реестр целиком,
/// здесь нужен только выбор: id, имя и на связи ли она.
struct RemoteMachineOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let online: Bool

    /// Слово, а не только цвет: «офлайн» должно читаться с экрана.
    var состояниеСтрокой: String { online ? "на связи" : "офлайн" }
}

struct SubtaskHostPicker: View {
    let subtask: ApiSubtask
    let machines: [RemoteMachineOption]
    let onSelect: (String?) -> Void

    @State private var показыватьВыбор = false

    /// Машина, на которой шаг идёт сейчас, — для заголовка кнопки.
    private var выбранная: RemoteMachineOption? {
        guard let id = subtask.hostId else { return nil }
        return machines.first { $0.id == id }
    }

    /// Текущее место работы шага словами. nil-hostId — «сервер», а не «нету».
    private var заголовок: String {
        if let выбранная { return выбранная.name }
        return "Сервер"
    }

    /// Показывать выбор незачем, если машин нет, и нельзя, когда шаг уже идёт:
    /// сервер всё равно откажет с 409, а пользователь увидит ошибку вместо
    /// понятного «уже идёт».
    private var доступен: Bool {
        !subtask.done && subtask.agentState != .inProgress && subtask.isActivelyRunning == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Button {
                показыватьВыбор.toggle()
            } label: {
                HStack(spacing: TFSpacing.sm) {
                    Image(systemName: выбранная == nil ? "server.rack" : "desktopcomputer")
                        .font(.body)
                        .foregroundStyle(Color.tfSub)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Где выполнять")
                            .tfText(.meta)
                            .foregroundStyle(Color.tfSub)
                        Text(заголовок)
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                    }
                    Spacer()
                    if доступен {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.tfSub)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!доступен)
            .accessibilityIdentifier("subtask-host-picker-\(subtask.id)")
            .accessibilityLabel("Где выполнять: \(заголовок)")

            if показыватьВыбор, доступен {
                выбор
            }
        }
    }

    private var выбор: some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            // Сервер — всегда первый и всегда доступен: без машины всё
            // работает как раньше, это не откат, а нормальный режим.
            строка(id: nil, имя: "Сервер", подпись: "локально на .110", online: true)
            ForEach(machines) { машина in
                строка(id: машина.id, имя: машина.name, подпись: машина.состояниеСтрокой, online: машина.online)
            }
        }
        .padding(.top, TFSpacing.xs)
    }

    private func строка(id: String?, имя: String, подпись: String, online: Bool) -> some View {
        Button {
            показыватьВыбор = false
            // Повторный тап по текущему — не мутация, а закрытие меню.
            guard subtask.hostId != id else { return }
            onSelect(id)
        } label: {
            HStack(spacing: TFSpacing.sm) {
                Image(systemName: subtask.hostId == id ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(subtask.hostId == id ? Color.tfBlue : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(имя)
                        .tfText(.body)
                        .foregroundStyle(online ? Color.tfText : Color.secondary)
                    Text(подпись)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfSub)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Офлайн-машину выбрать нельзя: роль стартует и сразу упадёт.
        .disabled(!online)
        .accessibilityIdentifier(id.map { "subtask-host-option-\($0)" } ?? "subtask-host-option-server")
        .accessibilityLabel("\(имя), \(подпись)")
    }
}