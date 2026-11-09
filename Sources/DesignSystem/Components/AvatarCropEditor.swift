import SwiftUI
import PhotosUI

/// Подгонка портрета роли под кружок аватарки.
///
/// Владелец 10.10.2026: картинки вырезать вручную не хочет, руками внутри
/// круга двигать — хочет. Поэтому здесь ровно то, что нужно: круг в натуральную
/// величину (как при долгом нажатии на аватарку), картинка внутри него и три
/// способа её двигать — перетаскиванием, щипком и ползунком масштаба для
/// точной подстройки. Что настроено, сохраняется по роли и применяется везде,
/// где рисуется портрет (`TFRolePortrait`).
struct AvatarCropEditor: View {
    let role: String
    let roleTitle: String
    /// Вшитый портрет роли — когда своё фото не выбрано. `nil` — у роли нет
    /// вшитой картинки (так у внешних агентов: Claude Code, Codex, Gemini,
    /// Гермес, OpenCode): тогда своё фото — основной путь, а без фото рисуются
    /// инициалы.
    let imageAsset: String?
    /// Учётка роли на сервере. Есть — выбранное фото сразу уходит на сервер
    /// (`POST /api/users/:id/avatar`), и его видят все экраны, включая чаты
    /// и карточки. `nil` — фото останется только на телефоне.
    var accountID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var scale: Double = 1
    @State private var offset: CGSize = .zero
    @State private var photo: String?
    @State private var shape: AvatarCrop.Shape = .circle
    @State private var pickerItem: PhotosPickerItem?
    @State private var isResetting = false
    /// Идёт отправка фото на сервер — кнопки на это время заблокированы,
    /// иначе второе нажатие затрёт первое без предупреждения.
    @State private var isUploading = false
    /// Ошибка сервера — говорим словами, а не молчим.
    @State private var errorText: String?

    private let circle: CGFloat = 300

    private var photoURL: URL? { photo.map(AvatarCrop.photoURL) }

    var body: some View {
        NavigationStack {
            VStack(spacing: TFSpacing.lg) {
                ZStack {
                    Color.black

                    content
                        .frame(width: circle, height: circle)
                        .clipShape(shape == .circle
                                   ? AnyShape(Circle())
                                   : AnyShape(RoundedRectangle(cornerRadius: TFRadius.md)))

                    // Кольцо-подсказка: видно, где пройдёт край кружка.
                    RoundedRectangle(cornerRadius: shape.corner)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .frame(width: circle, height: circle)
                }
                .frame(height: circle)
                .contentShape(Rectangle())
                // Жесты лежат ПОВЕРХ картинки, но ПОД рамкой окна: щипок и
                // перетаскивание работают одновременно, иначе второй жест
                // отменял бы первый.
                .gesture(dragGesture.simultaneously(with: magnifyGesture))

                VStack(spacing: TFSpacing.sm) {
                    Picker("Форма", selection: $shape) {
                        ForEach(AvatarCrop.Shape.allCases) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Размер").tfText(.meta).foregroundStyle(Color.tfSub)
                        Slider(value: $scale, in: 1...4)
                        Text("\(Int(scale * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 46, alignment: .trailing)
                    }
                    Text(imageAsset == nil
                         ? "У этой роли нет вшитого портрета — выберите своё фото."
                         : "Тяните картинку пальцем, щипок меняет размер.")
                        .tfText(.meta).foregroundStyle(Color.tfSub)
                    if let errorText {
                        Text(errorText)
                            .tfText(.meta)
                            .foregroundStyle(Color.tfRed)
                    }
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)

                HStack(spacing: TFSpacing.md) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Своё фото", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        // Сброс — это состояние редактора, а не кнопка-пустышка:
                        // возвращаем исходный портрет, масштаб 1, центр и круг.
                        // Своё фото убираем и с сервера — иначе стереть его
                        // из приложения было бы нечем.
                        scale = 1
                        offset = .zero
                        photo = nil
                        shape = .circle
                        Task { await removeFromServer() }
                    } label: {
                        Label("Сбросить", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUploading || (scale == 1 && offset == .zero && photo == nil && shape == .circle))

                    Spacer()

                    Button(isUploading ? "Сохраняю…" : "Готово") {
                        AvatarCrop.save(
                            AvatarCrop.Value(scale: scale, dx: offset.width, dy: offset.height,
                                             photo: photo, shape: shape),
                            for: role
                        )
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUploading)
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)

                Spacer(minLength: 0)
            }
            .background(Color.tfBackground)
            .navigationTitle(roleTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    if let name = AvatarCrop.storePhoto(data, for: role) {
                        await MainActor.run {
                            photo = name
                            scale = 1
                            offset = .zero
                        }
                        // Своё фото — на сервер, чтобы его видели все экраны
                        // (чаты, карточки, граф плана), а не только этот телефон.
                        await uploadToServer(data)
                    }
                }
            }
            .onAppear { load() }
        }
    }

    @ViewBuilder private var content: some View {
        if let photoURL, let img = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(scale)
                .offset(offset)
        } else if let imageAsset {
            Image(imageAsset)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(scale)
                .offset(offset)
        } else {
            // Роль без вшитого портрета и без фото — рисуем инициалы, а не
            // пустой чёрный кружок.
            Circle()
                .fill(roleAccentColor(role))
                .overlay {
                    Text(String(roleTitle.prefix(1)))
                        .font(.system(size: 96, weight: .semibold)) // design-system-guard: ignore — превью 300 pt, не текст экрана
                        .foregroundStyle(Color.tfPaper)
                }
        }
    }

    /// Отправить выбранное фото на сервер и подсказать справочнику аватарок
    /// новый адрес. Без учётки — молча остаёмся с локальным фото.
    private func uploadToServer(_ data: Data) async {
        guard let accountID, !accountID.isEmpty else { return }
        await MainActor.run { isUploading = true; errorText = nil }
        defer { Task { @MainActor in isUploading = false } }
        let jpeg = AvatarCrop.jpeg(from: data) ?? data
        do {
            let saved = try await APIClient().uploadAgentAvatar(id: accountID, data: jpeg, mime: "image/jpeg")
            await MainActor.run {
                AvatarDirectory.shared.set(path: saved.avatarUrl, forUserID: accountID)
            }
        } catch {
            await MainActor.run {
                errorText = "Фото осталось на телефоне: сервер не принял его (\(error.localizedDescription))."
            }
        }
    }

    /// Убрать фото с сервера: роль возвращается к вшитому портрету или
    /// инициалам на всех экранах, а не только на этом телефоне.
    private func removeFromServer() async {
        guard let accountID, !accountID.isEmpty else { return }
        await MainActor.run { isUploading = true; errorText = nil }
        do {
            try await APIClient().deleteAgentAvatar(id: accountID)
            await MainActor.run { AvatarDirectory.shared.remove(forUserID: accountID) }
        } catch {
            await MainActor.run {
                errorText = "Фото с сервера удалить не удалось (\(error.localizedDescription))."
            }
        }
        await MainActor.run { isUploading = false }
    }

    private func load() {
        let v = AvatarCrop.value(for: role)
        scale = v.scale
        offset = CGSize(width: v.dx, height: v.dy)
        photo = v.photo
        shape = v.shape
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: value.translation.width, height: value.translation.height)
            }
    }

    /// Щипок меняет только масштаб; перенос — перетаскиванием.
    /// `MagnifyGesture` не отдаёт смещение, а вычислить его от начала жеста
    /// нельзя: щипок и перенос идут одновременно, начала у них разные.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(value.magnification * baseScale, 1), 4)
            }
            .onEnded { _ in baseScale = scale }
    }

    @State private var baseScale: Double = 1
}