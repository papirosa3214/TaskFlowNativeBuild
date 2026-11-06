import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import QuickLook

/// Оформление голосового пузыря в чате. Своё сообщение — красная обводка без
/// заливки, ровно как у своего текстового: вид отправленного сообщения не
/// зависит от того, как его отправили (владелец 21.09.2026).
///
/// Цвета задаются ЗДЕСЬ, а не в `VoiceMessageBubble`: тот файл собирается
/// ещё и в отдельное приложение-прототип `VoiceMessageLab`, которому
/// дизайн-система TaskFlow недоступна.
enum RoleChatVoiceStyle {
    /// Своё голосовое — та же подложка, что у остальных, и красная обводка
    /// поверх. Отличает свои сообщения только обводка, как и у текстовых.
    /// Кнопка воспроизведения — один красный треугольник, без круга и без
    /// обводки (владелец 21.09.2026).
    ///
    /// Отступ и радиус — как у текстового сообщения в чате. С числами
    /// прототипа (14 и 22) иконка отправителя и текст расшифровки вставали
    /// на других вертикалях, чем в текстовом: владелец 21.09.2026 —
    /// «интервалы абсолютно одинаковые, симметрия».
    static let own = VoiceBubbleStyle(
        fill: Color.tfCard,
        stroke: Color.tfRed,
        playTint: Color.tfRed,
        playDisc: .none,
        contentColor: Color.tfText,
        padding: TFSpacing.md,
        cornerRadius: TFRadius.lg
    )

    /// Чужое голосовое: пузырь прототипа, но с теми же отступами, что у
    /// текстового сообщения — по той же причине.
    static let others = VoiceBubbleStyle(
        padding: TFSpacing.md,
        cornerRadius: TFRadius.lg
    )
}

struct RoleChatRemoteVoiceBubble: View {
    let attachment: ApiChatAttachment
    /// Сообщение-владелец вложения: из него берётся расшифровка и строка
    /// отправителя (иконка + имя), которая у голосового стоит ВНУТРИ пузыря.
    let message: RoleChatMessage
    let player: VoicePlayer
    let api: APIClient
    /// Своё ли сообщение: голосовое приходит из истории теми же вложениями,
    /// поэтому сторону нужно передать явно — иначе своё голосовое нарисовалось
    /// бы чужой карточкой.
    let isOwn: Bool
    let header: AnyView
    @State private var localMessage: VoiceMessage?
    @State private var failed = false

    var body: some View {
        Group {
            if let localMessage {
                // Своё голосовое — та же подложка, что у остальных, плюс
                // красная обводка; чужое — прежний пузырь прототипа
                // (владелец 21.09.2026: вид не зависит от способа отправки).
                VoiceMessageBubble(
                    message: localMessage,
                    player: player,
                    style: isOwn ? RoleChatVoiceStyle.own : RoleChatVoiceStyle.others,
                    header: header
                )
            } else if failed {
                Label("Не удалось загрузить аудио", systemImage: "exclamationmark.triangle")
            } else {
                TFLoading(.block)
            }
        }
        .task(id: attachment.id) {
            do {
                let data = try await api.downloadRaw(path: "/attachments/\(attachment.id)")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("role-chat-\(attachment.id).m4a")
                try data.write(to: url, options: .atomic)
                let duration = try AVAudioPlayer(contentsOf: url).duration
                let transcript = message.text
                localMessage = VoiceMessage(
                    audioURL: url,
                    duration: duration,
                    transcript: transcript.isEmpty ? .failed : .ready(transcript)
                )
            } catch { failed = true }
        }
    }
}
