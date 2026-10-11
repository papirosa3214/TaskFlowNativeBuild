import SwiftUI

/// Native rendering of the reference's .bg, .button and .inner layers.
/// Dimensions follow the 168 px mounting base around its 154 px button.
public struct TFGlassSurface<Glyph: View>: View {
    let size: CGFloat
    let charge: CGFloat
    let tint: Color
    let glowProgress: CGFloat
    let holdsGlow: Bool
    let circular: Bool
    let surfaceTint: Color?
    @ViewBuilder let glyph: () -> Glyph

    public init(size: CGFloat, charge: CGFloat, tint: Color, glowProgress: CGFloat = 0, holdsGlow: Bool = false, circular: Bool = false, surfaceTint: Color? = nil, @ViewBuilder glyph: @escaping () -> Glyph) {
        self.size = size
        self.charge = charge
        self.tint = tint
        self.glowProgress = glowProgress
        self.holdsGlow = holdsGlow
        self.circular = circular
        self.surfaceTint = surfaceTint
        self.glyph = glyph
    }

    private var scale: CGFloat { size / 168 }
    private var mountRadius: CGFloat { circular ? size / 2 : 37.5 * scale }
    private var mountHeight: CGFloat { circular ? size : 164 * scale }
    private var bodyRadius: CGFloat { (circular ? 77 : 30) * scale }
    private var capRadius: CGFloat { (circular ? 57 : 25.5) * scale }
    private var baseColor: Color { surfaceTint?.mix(with: .black, by: 0.4) ?? .black }
    private func bodyColor(_ gray: Double, darken: Double) -> Color {
        surfaceTint?.mix(with: .black, by: darken) ?? Color(white: gray)
    }
    private var capGradient: LinearGradient {
        let colors: [Color] = surfaceTint.map { [$0.mix(with: .black, by: 0.18), $0] }
            ?? [Color(white: 0.137), Color(white: 0.285)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    public var body: some View {
        ZStack {
            if circular, let surfaceTint {
                // One continuous red surface; depth comes from lighting, not nested discs.
                Circle()
                    .fill(RadialGradient(
                        stops: [.init(color: surfaceTint.mix(with: .white, by: 0.08), location: 0),
                                .init(color: surfaceTint, location: 0.65),
                                .init(color: surfaceTint.mix(with: .black, by: 0.23), location: 1)],
                        center: UnitPoint(x: 0.42, y: 0.3), startRadius: 0, endRadius: size * 0.7)
                        .shadow(.inner(color: .black.opacity(0.32), radius: 3, y: -2))
                        .shadow(.inner(color: .white.opacity(0.12), radius: 2, y: 1)))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
            } else {
            // Separate mounting base: black for tabs, dark red for creation.
            RoundedRectangle(cornerRadius: mountRadius)
                .fill(baseColor)
                .overlay {
                    RoundedRectangle(cornerRadius: mountRadius)
                        .strokeBorder(Color.white.opacity(0.035), lineWidth: 0.5)
                }
                .frame(width: size, height: mountHeight)
                .shadow(color: .black.opacity(0.5), radius: 4 * scale, y: 8 * scale)

            // Light is behind the opaque body. Only the mounting gap exposes it.
            TFLampGlow(progress: holdsGlow ? charge : glowProgress,
                       steady: holdsGlow, tint: tint)
                .frame(width: size, height: mountHeight)
                .mask {
                    RoundedRectangle(cornerRadius: mountRadius)
                        .strokeBorder(.white, lineWidth: 7 * scale)
                        .blur(radius: 1.5 * scale)
                }
                .clipShape(RoundedRectangle(cornerRadius: mountRadius).inset(by: scale))

            RoundedRectangle(cornerRadius: bodyRadius)
                .fill(LinearGradient(
                    stops: [
                        .init(color: bodyColor(0.16, darken: 0.22), location: 0),
                        .init(color: bodyColor(0.16, darken: 0.22), location: 0.35),
                        .init(color: bodyColor(0.16, darken: 0.22), location: 0.7),
                        .init(color: bodyColor(0.085, darken: 0.4), location: 1)
                    ], startPoint: .top, endPoint: .bottom
                ).shadow(.inner(color: .white.opacity(0.35), radius: scale, y: scale))
                 .shadow(.inner(color: .black.opacity(0.8), radius: 3 * scale, y: -3 * scale)))
                .clipShape(RoundedRectangle(cornerRadius: bodyRadius))
                .frame(width: 154 * scale, height: (circular ? 154 : 150) * scale)

            // The smaller recessed pad has its own gradient and inset edges.
            RoundedRectangle(cornerRadius: capRadius)
                .fill(capGradient
                    .shadow(.inner(color: .black.opacity(0.65), radius: 4 * scale, y: -3 * scale))
                    .shadow(.inner(color: .white.opacity(0.20), radius: scale, y: scale)))
                .overlay {
                    RoundedRectangle(cornerRadius: capRadius)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.17), .black.opacity(0.75)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: scale)
                }
                .frame(width: 114 * scale, height: (circular ? 114 : 106) * scale)
                .offset(y: -scale)

            }

            glyph()
                .shadow(color: .black.opacity(0.85), radius: scale, y: -scale)
                .shadow(color: tint.opacity(0.45 * Double(charge)), radius: 4 * scale)
                .frame(width: 114 * scale, height: (circular ? 114 : 106) * scale)
                .offset(y: -scale)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

public struct TFGlassTabIcon<Content: View>: View {
    let size: CGFloat
    let tint: Color
    let isActive: Bool
    let circular: Bool
    let surfaceTint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowProgress: CGFloat = 0
    @ViewBuilder let content: () -> Content

    public init(size: CGFloat, tint: Color, isActive: Bool, circular: Bool = false, surfaceTint: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.size = size
        self.tint = tint
        self.isActive = isActive
        self.circular = circular
        self.surfaceTint = surfaceTint
        self.content = content
    }

    public var body: some View {
        TFGlassSurface(size: size, charge: isActive ? 1 : 0, tint: tint,
                       glowProgress: glowProgress, holdsGlow: holdsGlow, circular: circular, surfaceTint: surfaceTint, glyph: content)
            .animation(.easeInOut(duration: 0.4), value: isActive)
            .task(id: isActive) {
                var reset = Transaction(animation: nil)
                reset.disablesAnimations = true
                withTransaction(reset) { glowProgress = 0 }
                guard isActive, !holdsGlow, !reduceMotion else { return }
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
                withAnimation(.linear(duration: 3)) { glowProgress = 1 }
            }
    }

    private var holdsGlow: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TASKFLOW_TAB_GLOW_MODE"] == "steady"
        #else
        false
        #endif
    }
}

/// Two broad light fields expand upward from the lower corners.
/// The opaque button occludes this field, exposing light only through its gap.
private struct TFLampGlow: View, Animatable {
    var progress: CGFloat
    let steady: Bool
    let tint: Color
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private func smooth(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        GeometryReader { proxy in
            let phase: CGFloat = steady ? 0.5 : progress
            let spread = smooth(phase / 0.35)
            let intensity = steady ? progress : min(smooth(phase / 0.35), smooth((1 - phase) / 0.3))
            ZStack {
                ForEach([0.2, 0.8], id: \.self) { x in
                    RadialGradient(colors: [tint.mix(with: .white, by: 0.1).opacity(0.55),
                                            tint.opacity(0.38), tint.opacity(0.15), .clear],
                                   center: UnitPoint(x: x, y: 1.1 - phase * 0.55),
                                   startRadius: 0, endRadius: proxy.size.width * (0.15 + 1.7 * spread))
                }
            }
            .opacity(Double(intensity))
        }
    }
}

public struct TFGlassTabStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
