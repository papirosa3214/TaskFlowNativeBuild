import SwiftUI
import UIKit

/// Окно подсказок поверх всего приложения, включая листы и шапки.
/// Касания принимает только карточка подсказки — остальное проходит в
/// приложение, поэтому подсвеченный элемент можно нажать как обычно.
final class HintOverlayWindow: UIWindow {
    private static var window: HintOverlayWindow?

    @MainActor
    static func install() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard window == nil,
              let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        else { return }
        let window = HintOverlayWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: HintOverlayView())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let card = MainActor.assumeIsolated { HintCenter.shared.currentStep == nil ? .zero : HintCenter.shared.cardFrame }
        guard card.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

struct HintOverlayView: View {
    @State private var center = HintCenter.shared

    var body: some View {
        GeometryReader { proxy in
            if let step = center.currentStep {
                let hole = step.anchor.flatMap { center.anchors[$0] }?.insetBy(dx: -6, dy: -6)
                ZStack(alignment: .topLeading) {
                    dim(size: proxy.size, hole: hole)
                    card(step, hole: hole, size: proxy.size)
                }
                .animation(.easeInOut(duration: 0.2), value: center.active?.step)
            }
        }
        .ignoresSafeArea()
    }

    private func dim(size: CGSize, hole: CGRect?) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12)) }
        }
        .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func card(_ step: HintStep, hole: CGRect?, size: CGSize) -> some View {
        let width = min(size.width - 32, 380)
        return VStack(alignment: .leading, spacing: 10) {
            Text(step.title).font(.headline)
            Text(step.text).font(.body).fixedSize(horizontal: false, vertical: true)
            if step.anchor != nil && hole == nil {
                Text("Элемент появится, когда откроешь нужный экран.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(step.branches) { branch in
                Button(branch.title) { center.choose(branch) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("hint.branch.\(branch.title)")
            }
            HStack {
                Button("Пропустить") { center.finish() }
                    .accessibilityIdentifier("hint.skip")
                Spacer()
                if step.branches.isEmpty {
                    Button(step.next == nil ? "Готово" : "Дальше") { center.next() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("hint.next")
                }
            }
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { center.cardFrame = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hint.card")
        .position(x: size.width / 2, y: cardY(hole: hole, size: size))
    }

    /// Карточка — под элементом, если он в верхней половине, иначе над ним.
    private func cardY(hole: CGRect?, size: CGSize) -> CGFloat {
        guard let hole else { return size.height * 0.62 }
        return hole.midY < size.height / 2
            ? min(hole.maxY + 130, size.height - 140)
            : max(hole.minY - 130, 140)
    }
}
