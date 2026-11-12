import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

/// Строка списка чатов — одна на все виды (роль, группа, помощник владельца):
/// аватар, имя, превью, время, бейдж непрочитанных. Строка во всю ширину,
/// без карточки и шеврона — вид списка, а не меню настроек.
struct ChatListRow: View {
    let title: String
    let preview: String
    let time: String?
    let unread: Int
    /// Название задачи, за которой закреплён чат (`nil` — свободный).
    var taskTitle: String?
    /// Ход роли в комнате: идёт сейчас или нет.
    var turn: RoomTurn? = nil
    /// Занятый контекст сессии, например «Контекст 42%».
    var contextLabel: String? = nil
    /// Стадия сессии: «Ожидает» или «В работе».
    var status: String? = nil
    var projectName: String? = nil
    /// Участник слева. Нет участника — строка без кружка.
    var member: RoleChatMember? = nil
    /// Кружок рисует соседняя кнопка. Строка отдаёт только текст,
    /// без левого отступа: его занимает кружок.
    var omitsAvatar = false

    /// Строка под превью: контекст и проект. Ход — в названии («· в работе»).
    private var metaLine: String? {
        let parts = [contextLabel, status, projectName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var displayedTitle: String {
        ChatWorkingMark.titled(title, running: turn?.running == true)
    }

    var body: some View {
        HStack(alignment: .center, spacing: TFSpacing.xs) {
            if let member, !omitsAvatar {
                RoleMemberAvatar(member: member)
                    .environment(\.tfAvatarLiveTurn, turn?.running == true)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayedTitle)
                    .tfText(.body)
                    .fontWeight(unread > 0 ? .semibold : .regular)
                    .foregroundStyle(Color.tfText)
                    .lineLimit(1)
                Text(preview)
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
                    .lineLimit(1)
                if let metaLine {
                    Text(metaLine)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(1)
                }
                // Пометка «чат за задачей»: по ней видно, куда уходит
                // переписка (владелец 21.09.2026: «пометка нужна»).
                if let taskTitle, !taskTitle.isEmpty {
                    Label(taskTitle, systemImage: "checklist")
                        .tfText(.caption)
                        .foregroundStyle(Color.tfDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: TFSpacing.xs)
            VStack(alignment: .trailing, spacing: TFSpacing.xs) {
                if let time {
                    Text(time)
                        .tfText(.meta)
                        .foregroundStyle(Color.tfDim)
                }
                if unread > 0 { badge }
            }
        }
        .padding(.leading, omitsAvatar ? 0 : TFSpacing.screenHorizontal)
        .padding(.trailing, TFSpacing.screenHorizontal)
        .padding(.vertical, TFSpacing.xs)
        .contentShape(Rectangle())
        // Строка целиком — одна единица для VoiceOver: без этого он читает
        // аватар, имя, превью и время как четыре отдельных элемента.
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        Text(unread > 99 ? "99+" : "\(unread)")
            .tfText(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tfPaper)
            .padding(.horizontal, TFSpacing.xs + 2)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Color.tfRedSolid))
            .accessibilityLabel("Непрочитанных: \(unread)")
    }
}

// FlowLayout переехал в Sources/DesignSystem/Components/FlowLayout.swift
// (28.09.2026) — чипам «Сведения» на карточке задачи нужна та же раскладка.

/// Аватар участника чата — фото, если оно есть у учётки, иначе инициалы.
struct RoleMemberAvatar: View {
    let member: RoleChatMember
    var size: TFAvatar.Size = .xl

    var body: some View {
        let initials = member.initials ?? String(member.name.prefix(1))
        let tint = Color(hex: member.avatarColor ?? TFHexDefault.unassigned)
        // Внешний агент: серверная картинка — чужой краб, не портрет. Пока
        // владелец не поставил своё фото, рисуем инициалы. Своё фото читает
        // `TFAvatar` из `AvatarCrop`, серверный адрес сюда не подмешиваем.
        if RoleAvatarAsset.isExternalChatRole(roleKey: member.roleKey, userID: member.id) {
            TFAvatar(size: size, initials: initials, tint: tint, userID: member.id)
        } else if let path = member.avatarURL,
           let url = URL(string: APIClient.baseURL.absoluteString + path) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    TFAvatar(size: size, image: image, initials: initials, tint: tint, userID: member.id)
                } else {
                    TFAvatar(size: size, initials: initials, tint: tint, userID: member.id)
                }
            }
        } else {
            TFAvatar(size: size, initials: initials, tint: tint, userID: member.id)
        }
    }
}

/// Время в строке списка чатов: сегодня — часы, вчера — словом, дальше до
/// недели — день недели, ещё дальше — дата. Формат взят у Teams, потому что
/// строка списка читается «когда было последнее сообщение», а не «сколько
/// прошло» (`RelativeTime` в этой же папке отвечает на второй вопрос).
enum ChatListTime {
    /// Московские часы: строка списка и плашка дня внутри чата обязаны
    /// называть один и тот же день одним и тем же словом (общее правило
    /// проекта — все даты в Europe/Moscow).
    private static var moscow: TimeZone { TimeZone(identifier: "Europe/Moscow") ?? .current }
    private static func moscowCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = moscow
        return cal
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = moscow
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = moscow
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = moscow
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    static func label(_ raw: String?) -> String? {
        guard let moment = DateFormats.sqliteUTC(raw) else { return nil }
        let calendar = moscowCalendar()
        if calendar.isDateInToday(moment) { return clock.string(from: moment) }
        if calendar.isDateInYesterday(moment) { return "Вчера" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: moment),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if days < 7 { return weekday.string(from: moment).capitalized }
        return shortDate.string(from: moment)
    }
}
