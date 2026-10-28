import SwiftUI

/// Контуры непосредственно из TabIcon*.svg (viewBox 24 × 24).
/// Каждый штрих рисуется одновременно, как stroke-dashoffset в веб-панели.
struct TFTabDrawIcon: View {
    let name: String
    let showsTodayDate: Bool
    let isActive: Bool
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1
    @State private var day = Calendar.current.component(.day, from: Date())

    var body: some View {
        ZStack {
            if let paths = TabIconContours.paths(for: showsTodayDate ? "TabIconToday" : name) {
                ForEach(paths.indices, id: \.self) { index in
                    TabIconStroke(path: paths[index])
                        .trim(from: 0, to: progress)
                        .stroke(style: StrokeStyle(lineWidth: size * 1.75 / 24, lineCap: .round, lineJoin: .round))
                }
            } else {
                Image(name).renderingMode(.template).resizable().scaledToFit()
            }
            if showsTodayDate {
                Text("\(day)")
                    .font(.system(size: size * (day > 9 ? 0.34 : 0.38), weight: .heavy))  // design-system-guard: ignore — число дня внутри значка вкладки, доля от размера значка
                    .monospacedDigit()
                    .offset(y: size * 0.13)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: isActive) { _, active in
            if !active || reduceMotion {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { progress = 1 }
            }
        }
        .task(id: isActive) {
            guard isActive, !reduceMotion else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { progress = 0 }
            // Следующий кадр отделяет сброс от интерполяции; отменяется при смене вкладки.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.5)) { progress = 1 }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { progress = 1 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            day = Calendar.current.component(.day, from: Date())
        }
        .accessibilityHidden(true)
    }
}

private struct TabIconStroke: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path {
        path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

private enum TabIconContours {
    static func paths(for name: String) -> [Path]? {
        var paths: [Path] = []
        switch name {
        case "TabIconHome":
            paths.append(Path { p in
                p.move(to: CGPoint(x: 3, y: 10.5))
                p.addLine(to: CGPoint(x: 12, y: 3))
                p.addLine(to: CGPoint(x: 21, y: 10.5))
            })
            paths.append(Path { p in
                p.move(to: CGPoint(x: 5, y: 9.5))
                p.addLine(to: CGPoint(x: 5, y: 20))
                arc(&p, from: CGPoint(x: 5, y: 20), to: CGPoint(x: 6, y: 21), radius: 1, large: false, sweep: false)
                p.addLine(to: CGPoint(x: 10, y: 21))
                p.addLine(to: CGPoint(x: 10, y: 15))
                p.addLine(to: CGPoint(x: 14, y: 15))
                p.addLine(to: CGPoint(x: 14, y: 21))
                p.addLine(to: CGPoint(x: 18, y: 21))
                arc(&p, from: CGPoint(x: 18, y: 21), to: CGPoint(x: 19, y: 20), radius: 1, large: false, sweep: false)
                p.addLine(to: CGPoint(x: 19, y: 9.5))
            })
        case "TabIconProjects":
            paths.append(Path { p in
                p.move(to: CGPoint(x: 6, y: 6.5))
                p.addLine(to: CGPoint(x: 6, y: 5))
                arc(&p, from: CGPoint(x: 6, y: 5), to: CGPoint(x: 7, y: 4), radius: 1, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 10.2, y: 4))
                p.addLine(to: CGPoint(x: 11.8, y: 6))
                p.addLine(to: CGPoint(x: 18, y: 6))
                arc(&p, from: CGPoint(x: 18, y: 6), to: CGPoint(x: 19, y: 7), radius: 1, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 19, y: 8))
            })
            paths.append(Path { p in
                p.move(to: CGPoint(x: 3, y: 10))
                arc(&p, from: CGPoint(x: 3, y: 10), to: CGPoint(x: 4, y: 9), radius: 1, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 10.2, y: 9))
                p.addLine(to: CGPoint(x: 11.8, y: 11))
                p.addLine(to: CGPoint(x: 20, y: 11))
                arc(&p, from: CGPoint(x: 20, y: 11), to: CGPoint(x: 21, y: 12), radius: 1, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 21, y: 19))
                arc(&p, from: CGPoint(x: 21, y: 19), to: CGPoint(x: 20, y: 20), radius: 1, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 4, y: 20))
                arc(&p, from: CGPoint(x: 4, y: 20), to: CGPoint(x: 3, y: 19), radius: 1, large: false, sweep: true)
                p.closeSubpath()
            })
        case "TabIconPlanning":
            // «Входящие»: лоток для входящих (28.10.2026, вместо календаря).
            paths.append(Path { p in
                p.move(to: CGPoint(x: 6.5, y: 5))
                p.addLine(to: CGPoint(x: 17.5, y: 5))
                p.addLine(to: CGPoint(x: 21, y: 13))
                p.addLine(to: CGPoint(x: 21, y: 19))
                arc(&p, from: CGPoint(x: 21, y: 19), to: CGPoint(x: 20, y: 20), radius: 1, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 4, y: 20))
                arc(&p, from: CGPoint(x: 4, y: 20), to: CGPoint(x: 3, y: 19), radius: 1, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 3, y: 13))
                p.closeSubpath()
            })
            paths.append(Path { p in
                p.move(to: CGPoint(x: 3, y: 13))
                p.addLine(to: CGPoint(x: 8, y: 13))
                p.addLine(to: CGPoint(x: 9.5, y: 15.5))
                p.addLine(to: CGPoint(x: 14.5, y: 15.5))
                p.addLine(to: CGPoint(x: 16, y: 13))
                p.addLine(to: CGPoint(x: 21, y: 13))
            })
        case "TabIconChat":
            paths.append(Path { p in
                p.move(to: CGPoint(x: 21, y: 11.5))
                arc(&p, from: CGPoint(x: 21, y: 11.5), to: CGPoint(x: 20.1, y: 15.3), radius: 8.38, large: false, sweep: true)
                arc(&p, from: CGPoint(x: 20.1, y: 15.3), to: CGPoint(x: 12.5, y: 20), radius: 8.5, large: false, sweep: true)
                arc(&p, from: CGPoint(x: 12.5, y: 20), to: CGPoint(x: 8.7, y: 19.1), radius: 8.38, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 3, y: 21))
                p.addLine(to: CGPoint(x: 4.9, y: 15.3))
                arc(&p, from: CGPoint(x: 4.9, y: 15.3), to: CGPoint(x: 4, y: 11.5), radius: 8.38, large: false, sweep: true)
                arc(&p, from: CGPoint(x: 4, y: 11.5), to: CGPoint(x: 8.7, y: 3.9), radius: 8.5, large: false, sweep: true)
                arc(&p, from: CGPoint(x: 8.7, y: 3.9), to: CGPoint(x: 12.5, y: 3), radius: 8.38, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 13, y: 3))
                arc(&p, from: CGPoint(x: 13, y: 3), to: CGPoint(x: 21, y: 11), radius: 8.48, large: false, sweep: true)
                p.addLine(to: CGPoint(x: 21, y: 11.5))
                p.closeSubpath()
            })
        case "TabIconToday":
            paths.append(Path { p in
                p.addRoundedRect(in: CGRect(x: 3.0, y: 5.0, width: 18.0, height: 16.0), cornerSize: CGSize(width: 2.0, height: 2.0))
            })
            paths.append(Path { p in
                p.move(to: CGPoint(x: 3, y: 10))
                p.addLine(to: CGPoint(x: 21, y: 10))
            })
            paths.append(Path { p in
                p.move(to: CGPoint(x: 8, y: 3))
                p.addLine(to: CGPoint(x: 8, y: 7))
                p.move(to: CGPoint(x: 16, y: 3))
                p.addLine(to: CGPoint(x: 16, y: 7))
            })
        default: return nil
        }
        return paths
    }

    /// SVG endpoint arc → круговая дуга SwiftUI. У исходных иконок rx == ry, rotation == 0.
    private static func arc(_ path: inout Path, from start: CGPoint, to end: CGPoint,
                            radius: CGFloat, large: Bool, sweep: Bool) {
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let distanceSquared = dx * dx + dy * dy
        guard distanceSquared > 0 else { return }
        let r = max(radius, sqrt(distanceSquared))
        let sign: CGFloat = large == sweep ? -1 : 1
        let factor = sign * sqrt(max(0, (r * r - distanceSquared) / distanceSquared))
        let center = CGPoint(x: (start.x + end.x) / 2 + factor * dy,
                             y: (start.y + end.y) / 2 - factor * dx)
        let a = atan2(start.y - center.y, start.x - center.x)
        let b = atan2(end.y - center.y, end.x - center.x)
        path.addArc(center: center, radius: r,
                    startAngle: .radians(Double(a)), endAngle: .radians(Double(b)), clockwise: !sweep)
    }
}
