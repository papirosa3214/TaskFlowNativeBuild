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
    /// Вшитый портрет роли — когда своё фото не выбрано.
    let imageAsset: String

    @Environment(\.dismiss) private var dismiss
    @State private var scale: Double = 1
    @State private var offset: CGSize = .zero
    @State private var photo: String?
    @State private var shape: AvatarCrop.Shape = .circle
    @State private var pickerItem: PhotosPickerItem?
    @State private var isResetting = false

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
                        Text("Размер").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $scale, in: 1...4)
                        Text("\(Int(scale * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 46, alignment: .trailing)
                    }
                    Text("Тяните картинку мышью или пальцем, щипок меняет размер.")
                        .font(.caption).foregroundStyle(.secondary)
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
                        scale = 1
                        offset = .zero
                        photo = nil
                        shape = .circle
                    } label: {
                        Label("Сбросить", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(scale == 1 && offset == .zero && photo == nil && shape == .circle)

                    Spacer()

                    Button("Готово") {
                        AvatarCrop.save(
                            AvatarCrop.Value(scale: scale, dx: offset.width, dy: offset.height,
                                             photo: photo, shape: shape),
                            for: role
                        )
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
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
            .onAppear { load() }
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
                    }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let photoURL, let img = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(scale)
                .offset(offset)
        } else {
            Image(imageAsset)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(scale)
                .offset(offset)
        }
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