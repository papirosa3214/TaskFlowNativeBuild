import SwiftUI

struct FontSettingsScreen: View {
    @State private var context: TypographyContext = .app
    @AppStorage(TFTextTone.storageKey) private var appToneRaw = TFTextTone.pure.rawValue
    @AppStorage(TFTextTone.chatStorageKey) private var chatToneRaw = TFTextTone.pure.rawValue
    @AppStorage(TFTypeFace.storageKey) private var appFaceRaw = TFTypeFace.system.rawValue
    @AppStorage(TFTypeFace.chatStorageKey) private var chatFaceRaw = TFTypeFace.system.rawValue
    @AppStorage(TFTypeScale.revisionKey) private var typeRevision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.lg) {
                Picker("Шрифт", selection: $context) {
                    Text("Приложение").tag(TypographyContext.app)
                    Text("Чат").tag(TypographyContext.chat)
                }
                .pickerStyle(.segmented)

                controlsCard

                Text("Размер")
                    .tfSectionDisplay(style: .title)
                sizeCard

                Text("Образец")
                    .tfSectionDisplay(style: .title)
                if context == .app {
                    appSample
                } else {
                    chatSample
                }
            }
            .padding(.horizontal, TFSpacing.screenHorizontal)
            .padding(.vertical, TFSpacing.lg)
        }
        .tfNativeHeader("Шрифт")
        .tfScreenBackground()
    }

    private var controlsCard: some View {
        TFCard(padding: 0, bordered: true) {
            VStack(spacing: 0) {
                HStack(spacing: TFSpacing.md) {
                    Text("Тон")
                        .tfText(.body)
                        .foregroundStyle(Color.tfText)
                    Spacer()
                    ForEach(TFTextTone.allCases) { tone in
                        Button {
                            setTone(tone)
                        } label: {
                            Image(systemName: selectedTone == tone ? "checkmark.circle.fill" : "circle.fill")
                                .tfTypeFont(size: TFIconSize.md, weight: .regular)
                                .foregroundStyle(tone.color)
                                .frame(minWidth: TFHitTarget.min, minHeight: TFHitTarget.min)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tone.title)
                        .accessibilityAddTraits(selectedTone == tone ? .isSelected : [])
                    }
                }
                .padding(.horizontal, TFSpacing.md)

                TFDivider(inset: TFSpacing.md)

                Menu {
                    ForEach(TFTypeFace.allCases) { face in
                        Button {
                            setFace(face)
                        } label: {
                            if face == selectedFace {
                                Label(face.title, systemImage: "checkmark")
                            } else {
                                Text(face.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: TFSpacing.md) {
                        Text("Стиль шрифта")
                            .tfText(.body)
                            .foregroundStyle(Color.tfText)
                        Spacer()
                        Text(selectedFace.title)
                            .tfText(.action)
                            .foregroundStyle(Color.tfSub)
                        Image(systemName: "chevron.up.chevron.down")
                            .tfTypeFont(size: TFIconSize.xs, weight: .semibold)
                            .foregroundStyle(Color.tfDim)
                    }
                    .padding(.horizontal, TFSpacing.md)
                    .frame(minHeight: TFHitTarget.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var sizeCard: some View {
        TFCard(padding: 0, bordered: true) {
            VStack(spacing: 0) {
                if context == .app {
                    ForEach(Array(TFTypeGroup.allCases.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { TFDivider(inset: TFSpacing.md) }
                        sizeRow(title: group.title, baseSize: group.baseSize, binding: scaleBinding(for: group))
                    }
                } else {
                    ForEach(Array(TFChatTypeGroup.allCases.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { TFDivider(inset: TFSpacing.md) }
                        sizeRow(title: group.title, baseSize: group.baseSize, binding: scaleBinding(for: group))
                    }
                }
            }
        }
    }

    private func sizeRow(title: String, baseSize: CGFloat, binding: Binding<Double>) -> some View {
        HStack(spacing: TFSpacing.md) {
            Text(title)
                .tfText(.action)
                .foregroundStyle(Color.tfText)
                .frame(width: 118, alignment: .leading)
                .lineLimit(1)
            Slider(value: binding, in: 0...Double(TFTypeScale.allCases.count - 1), step: 1)
            Text(String(Int((baseSize * scale(at: binding.wrappedValue).multiplier).rounded())))
                .tfText(.action)
                .foregroundStyle(Color.tfSub)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, TFSpacing.md)
        .frame(minHeight: TFHitTarget.min)
    }

    private var appSample: some View {
        let tone = selectedTone.color
        let face = selectedFace
        return TFCard(padding: TFSpacing.md, bordered: true) {
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                previewText("ЗАДАЧА", group: .tertiary, face: face, color: tone.opacity(0.72))
                previewText("Подготовить релиз", group: .heading, face: face, color: tone, weight: .bold)
                previewText("Проверка перед публикацией", group: .subheading, face: face, color: tone, weight: .semibold)
                previewText("Сверить изменённую логику и отчёт.", group: .body, face: face, color: tone)
                previewText("Сегодня · В работе", group: .secondary, face: face, color: tone.opacity(0.72))
                previewText("ВЛАДЕЛЕЦ · 3 ШАГА", group: .tertiary, face: face, color: tone.opacity(0.62))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var chatSample: some View {
        let tone = selectedTone.color
        return TFCard(padding: TFSpacing.md, bordered: true) {
            VStack(alignment: .leading, spacing: TFSpacing.sm) {
                Text("Ответ готов")
                    .font(chatPreviewFont(.heading, weight: .semibold))
                    .foregroundStyle(tone)
                (Text("Я проверил ").font(chatPreviewFont(.body))
                 + Text("изменённую логику").font(chatPreviewFont(.emphasis, weight: .bold))
                 + Text(" и отчёт.").font(chatPreviewFont(.body)))
                    .foregroundStyle(tone)
                TFCard(padding: TFSpacing.sm, surface: .card2, radius: TFRadius.sm) {
                    Text("status: ready")
                        .font(chatPreviewFont(.mono, design: .monospaced))
                        .foregroundStyle(tone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Проверяю связанные файлы…")
                    .font(chatPreviewFont(.thinking).italic())
                    .foregroundStyle(tone.opacity(0.72))
                Text("12 с · 1 842 токена")
                    .font(chatPreviewFont(.meta))
                    .foregroundStyle(tone.opacity(0.62))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedTone: TFTextTone {
        TFTextTone(rawValue: context == .app ? appToneRaw : chatToneRaw) ?? .pure
    }

    private var selectedFace: TFTypeFace {
        TFTypeFace(rawValue: context == .app ? appFaceRaw : chatFaceRaw) ?? .system
    }

    private func setTone(_ tone: TFTextTone) {
        if context == .app { appToneRaw = tone.rawValue }
        else {
            chatToneRaw = tone.rawValue
            // Модификаторы текста следят за тоном приложения, а не чата:
            // без счётчика уже открытая лента осталась бы в прежнем тоне.
            typeRevision += 1
        }
    }

    private func setFace(_ face: TFTypeFace) {
        TFTypeFace.save(face, for: context)
        if context == .app { appFaceRaw = face.rawValue }
        else { chatFaceRaw = face.rawValue }
    }

    private func scaleBinding(for group: TFTypeGroup) -> Binding<Double> {
        Binding(
            get: { Double(TFTypeScale.allCases.firstIndex(of: .saved(for: group)) ?? 2) },
            set: { TFTypeScale.save(scale(at: $0), for: group) }
        )
    }

    private func scaleBinding(for group: TFChatTypeGroup) -> Binding<Double> {
        Binding(
            get: { Double(TFTypeScale.allCases.firstIndex(of: .saved(forChat: group)) ?? 2) },
            set: { TFTypeScale.save(scale(at: $0), forChat: group) }
        )
    }

    private func scale(at value: Double) -> TFTypeScale {
        let index = min(max(Int(value.rounded()), 0), TFTypeScale.allCases.count - 1)
        return TFTypeScale.allCases[index]
    }

    private func previewText(
        _ value: String,
        group: TFTypeGroup,
        face: TFTypeFace,
        color: Color,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(value)
            .font(face.font(size: group.baseSize * TFTypeScale.saved(for: group).multiplier, weight: weight))
            .foregroundStyle(color)
    }

    private func chatPreviewFont(
        _ group: TFChatTypeGroup,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        let size = group.baseSize * TFTypeScale.saved(forChat: group).multiplier
        if group == .mono { return .system(size: size, weight: weight, design: .monospaced) }
        return selectedFace.font(size: size, weight: weight, design: design)
    }
}
