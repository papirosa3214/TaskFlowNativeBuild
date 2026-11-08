import AVFoundation
import SwiftUI

/// Привязка этого iPhone к TaskFlow по QR-коду с сервера.
///
/// Зачем экран существует. Домашний вход без пароля выключен 08.11.2026 по
/// требованию владельца («под моей учёткой никто зайти не должен»), поэтому
/// `/auth/lan` больше не пускает, а токен устройства из связки ключей может
/// пропасть — переустановка, выход, ответ 401 и очистка Keychain. Тогда
/// остаётся только пароль владельца руками, чего он и не хотел.
///
/// Код выписывает сервер: `npx tsx scripts/pairing-code.ts` печатает QR в
/// терминале (или `POST /api/pairing/code` — для уже вошедшего клиента).
/// Код одноразовый, живёт 5 минут, в базе лежит только его sha256. Здесь он
/// меняется на долгоживущий токен устройства (`POST /api/pairing/exchange`),
/// а дальше сессия обычная.
///
/// Шторка закрывается свайпом: кнопок «Закрыть»/«Готово» в нижних шторках
/// приложения нет (решение владельца 05.11.2026).
struct DevicePairingSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// Код, пришедший ссылкой `taskflow://pair?…` (QR отсканировали камерой
    /// системы, а не этой шторкой).
    private let prefilledCode: String?

    @State private var manualCode = ""
    @State private var isSubmitting = false
    /// Камера может быть недоступна (симулятор, отказ в доступе) — тогда
    /// остаётся ручной ввод, и об этом надо сказать словами, а не пустым
    /// чёрным прямоугольником.
    @State private var cameraMessage: String?

    init(prefilledCode: String? = nil) {
        self.prefilledCode = prefilledCode
        _manualCode = State(initialValue: prefilledCode ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TFSpacing.lg) {
                    Text("Откройте QR-код на сервере и наведите камеру. Код живёт 5 минут и срабатывает один раз.")
                        .tfText(.body)
                        .foregroundStyle(Color.tfSub)

                    scanner

                    HStack(spacing: TFSpacing.md) {
                        Rectangle()
                            .fill(Color.tfStroke)
                            .frame(height: 1)
                        Text("или код вручную")
                            .tfText(.caption)
                            .foregroundStyle(Color.tfDim)
                            .fixedSize()
                        Rectangle()
                            .fill(Color.tfStroke)
                            .frame(height: 1)
                    }

                    TFTextField("32 символа из QR", text: $manualCode, icon: "keyboard")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("device-pairing-code")

                    TFErrorBanner(session.errorMessage, variant: .block)

                    TFButton(
                        isSubmitting ? "Привязываем…" : "Привязать",
                        icon: "qrcode.viewfinder",
                        isEnabled: !isSubmitting && !manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        submit(manualCode)
                    }
                    .accessibilityIdentifier("device-pairing-submit")
                }
                .padding(.horizontal, TFSpacing.screenHorizontal)
                .padding(.vertical, TFSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .tfNativeHeader("Привязка по QR")
            .onAppear {
                // Ссылка из QR, открытая камерой системы: код уже есть —
                // человеку не нужно ничего нажимать второй раз.
                if let prefilledCode, PairingLink.normalizedCode(prefilledCode) != nil {
                    submit(prefilledCode)
                }
            }
        }
    }

    @ViewBuilder
    private var scanner: some View {
        ZStack {
            if let cameraMessage {
                VStack(spacing: TFSpacing.sm) {
                    Image(systemName: "camera.badge.ellipsis")
                        .tfTypeFont(size: 28)
                        .foregroundStyle(Color.tfDim)
                    Text(cameraMessage)
                        .tfText(.caption)
                        .foregroundStyle(Color.tfSub)
                        .multilineTextAlignment(.center)
                }
                .padding(TFSpacing.lg)
            } else {
                QRScannerView(
                    onCode: { code in submit(code) },
                    onUnavailable: { message in cameraMessage = message }
                )
            }
        }
        .frame(height: 260)
        .frame(maxWidth: .infinity)
        .background(Color.tfTile)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg, style: .continuous))
    }

    private func submit(_ rawCode: String) {
        guard !isSubmitting else { return }
        isSubmitting = true
        // Ссылку/код нормализует `SessionStore.pairDevice` — здесь только
        // передаём как есть: человек мог вставить ссылку целиком.
        Task {
            let success = await session.pairDevice(code: rawCode)
            isSubmitting = false
            if success { dismiss() }
        }
    }
}

/// Камера с распознаванием QR-кодов.
///
/// Взят `AVCaptureMetadataOutput`, а не `DataScannerViewController`: тот даёт
/// готовый оверлей со своими подсказками и кнопками, а здесь нужна рамка
/// внутри своей карточки — иначе на экране появляется чужой «сканер» со
/// своим текстом. Ничего, кроме распознавания, представление не делает.
private struct QRScannerView: UIViewRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: (String) -> Void

    func makeUIView(context: Context) -> ScannerView {
        let view = ScannerView()
        view.onCode = onCode
        view.onUnavailable = onUnavailable
        return view
    }

    func updateUIView(_ uiView: ScannerView, context: Context) {}

    static func dismantleUIView(_ uiView: ScannerView, coordinator: ()) {
        uiView.stop()
    }

    final class ScannerView: UIView, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        var onUnavailable: ((String) -> Void)?
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "taskflow.qr-scanner.session")
        /// Кадров в секунду больше, чем нужно: код отдаём один раз, дальше
        /// сессия останавливается — иначе `onCode` срабатывал бы десятки раз
        /// и привязка уходила бы в очередь запросов.
        private var handled = false

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer })?.frame = bounds
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stop() } else { start() }
        }

        private func start() {
            guard session.inputs.isEmpty else {
                if !session.isRunning { queue.async { self.session.startRunning() } }
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configure()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.onUnavailable?("Нет доступа к камере. Разрешите его в настройках iOS или введите код вручную.")
                            return
                        }
                        self.configure()
                    }
                }
            default:
                onUnavailable?("Нет доступа к камере. Разрешите его в настройках iOS или введите код вручную.")
            }
        }

        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                onUnavailable?("Камера недоступна на этом устройстве — введите код вручную.")
                return
            }
            session.beginConfiguration()
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                onUnavailable?("Камера недоступна на этом устройстве — введите код вручную.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            session.commitConfiguration()

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = bounds
            layer.addSublayer(preview)

            queue.async {
                self.session.startRunning()
                // `availableMetadataObjectTypes` заполняется только у работающей
                // сессии: до старта список пуст. Проверка «умеет ли камера QR» до
                // запуска всегда врала — 08.11.2026 живой iPhone получал ответ
                // «Камера не умеет читать QR — введите код вручную», хотя камера
                // QR читает. Поэтому спрашиваем после старта, и только тогда
                // включаем коды, чтобы не уронить сессию неподдерживаемым типом.
                guard output.availableMetadataObjectTypes.contains(.qr) else {
                    self.session.stopRunning()
                    DispatchQueue.main.async {
                        self.onUnavailable?("Камера не умеет читать QR — введите код вручную.")
                    }
                    return
                }
                output.metadataObjectTypes = [.qr]
            }
        }

        func stop() {
            guard session.isRunning else { return }
            queue.async { self.session.stopRunning() }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !handled,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue
            else { return }
            handled = true
            stop()
            onCode?(value)
        }
    }
}
