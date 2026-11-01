import SwiftUI

// Вид кнопок «скрыть клавиатуру» и «диктовка» — один на всё приложение
// (LOCK-254: размер иконки 18, тап-цель `TFHitTarget.min`, при записи —
// `VoiceBarsView` как у голосовых в чате). До 16.10.2026 одно и то же
// рисовали трижды: Markdown-панель, надстройка большой карточки и — теперь
// — ряд ярлыков короткой карточки создания. Действие у каждого экрана своё,
// поэтому здесь только подпись кнопки.

public struct TFKeyboardDismissLabel: View {
    public init() {}
    public var body: some View {
        Image(systemName: "keyboard.chevron.compact.down")
            .tfTypeFont(size: 18)
            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
    }
}

public struct TFDictationLabel: View {
    let isRecording: Bool
    let isTranscribing: Bool
    let level: Double

    public init(isRecording: Bool, isTranscribing: Bool = false, level: Double) {
        self.isRecording = isRecording
        self.isTranscribing = isTranscribing
        self.level = level
    }

    public var body: some View {
        if isRecording {
            VoiceBarsView(
                level: level,
                color: Color.tfRed.mix(with: .black, by: 0.55), peakColor: Color.tfRed,
                barWidth: 3, spacing: 2, maxHeight: 20, isSmooth: true
            )
            .frame(width: TFHitTarget.min, height: TFHitTarget.min)
        } else if isTranscribing {
            ProgressView()
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
        } else {
            Image(systemName: "mic.fill")
                .tfTypeFont(size: 18)
                .frame(width: TFHitTarget.min, height: TFHitTarget.min)
        }
    }
}
