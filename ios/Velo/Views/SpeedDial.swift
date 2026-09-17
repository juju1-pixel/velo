import SwiftUI

struct SpeedDial: View {
    let speed: Double?
    let unit: SpeedUnit
    let status: String
    let isOverLimit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 36

    private var accent: Color { isOverLimit ? VeloTheme.warning : VeloTheme.accent }
    private var displayedSpeed: Double? { speed.map { unit.speed(from: $0) } }

    // This visual range never caps an accepted GPS reading.
    private var scaleMaximum: Double {
        let minimum = unit == .kilometersPerHour ? 500.0 : 350.0
        let increment = unit == .kilometersPerHour ? 100.0 : 50.0
        return max(minimum, ((displayedSpeed ?? 0) / increment).rounded(.up) * increment)
    }
    private var progress: Double { min(1, max(0, (displayedSpeed ?? 0) / scaleMaximum)) }
    private var majorIntervals: Int { unit == .kilometersPerHour ? 5 : 7 }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let center = CGPoint(x: width / 2, y: width / 2)
                let radius = width * 0.455
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [VeloTheme.surface, VeloTheme.background.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().stroke(VeloTheme.border, lineWidth: 1))
                        .padding(2)
                    Canvas { context, _ in
                        func point(_ angle: Double, _ r: Double) -> CGPoint {
                            CGPoint(x: center.x + cos(angle * .pi / 180) * r,
                                    y: center.y + sin(angle * .pi / 180) * r)
                        }
                        let tickCount = majorIntervals * 5
                        for index in 0...tickCount {
                            let angle = 135 + Double(index) / Double(tickCount) * 270
                            let major = index % 5 == 0
                            var tick = Path()
                            tick.move(to: point(angle, radius))
                            tick.addLine(to: point(angle, radius - (major ? 15 : 7)))
                            context.stroke(tick, with: .color(major ? VeloTheme.foreground : VeloTheme.tick), lineWidth: major ? 2.4 : 1)
                            if major {
                                let value = scaleMaximum * Double(index) / Double(tickCount)
                                let label = Text(value, format: .number.precision(.fractionLength(0)))
                                    .font(.system(size: width * 0.047, weight: .semibold))
                                    .foregroundColor(VeloTheme.foreground)
                                context.draw(label, at: point(angle, radius - 32))
                            }
                        }
                    }.accessibilityHidden(true)

                    Text("VELO")
                        .font(.system(size: 12, weight: .bold)).tracking(4)
                        .foregroundStyle(VeloTheme.secondary)
                        .position(x: center.x, y: width * 0.32)
                        .accessibilityHidden(true)

                    if speed != nil {
                        SpeedNeedle(angle: 135 + progress * 270)
                            .fill(accent)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: progress)
                            .accessibilityHidden(true)
                    }
                    Circle().fill(speed == nil ? VeloTheme.secondary : accent)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().fill(VeloTheme.surface).frame(width: 6, height: 6))
                        .position(center)
                        .accessibilityHidden(true)

                    VStack(spacing: 4) {
                        Text("当前速度").font(.caption).foregroundStyle(VeloTheme.secondary)
                        Text(displayedSpeed.map { String(format: "%.1f", $0) } ?? "0")
                            .font(.system(size: min(numberSize, width * 0.115), weight: .medium, design: .rounded))
                            .monospacedDigit().tracking(-0.5).lineLimit(1).minimumScaleFactor(0.5)
                            .foregroundStyle(isOverLimit ? VeloTheme.warning : VeloTheme.foreground)
                            .accessibilityIdentifier("currentSpeed")
                            .accessibilityLabel(displayedSpeed.map { String(format: "%.1f", $0) } ?? "0，暂无有效速度读数")
                        Text(unit.rawValue).font(.caption.weight(.medium)).foregroundStyle(VeloTheme.secondary)
                    }
                    .frame(width: width * 0.42)
                    .position(x: center.x, y: width * 0.74)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.top, 12)

            Label(isOverLimit ? "已超过设定提醒速度" : status,
                  systemImage: isOverLimit ? "exclamationmark.circle.fill" : "circle.fill")
                .font(.caption).foregroundStyle(accent)
                .labelStyle(StatusLabelStyle())
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(accent.opacity(0.07), in: Capsule())
                .padding(.bottom, 12)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SpeedNeedle: Shape {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radians = angle * .pi / 180
        let direction = CGVector(dx: cos(radians), dy: sin(radians))
        let length = min(rect.width, rect.height) * 0.425
        var path = Path()
        path.move(to: CGPoint(x: center.x + direction.dx * length, y: center.y + direction.dy * length))
        path.addLine(to: CGPoint(x: center.x - direction.dy * 3, y: center.y + direction.dx * 3))
        path.addLine(to: CGPoint(x: center.x - direction.dx * 13, y: center.y - direction.dy * 13))
        path.addLine(to: CGPoint(x: center.x + direction.dy * 3, y: center.y - direction.dx * 3))
        path.closeSubpath()
        return path
    }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

#Preview("500 km/h") {
    SpeedDial(speed: 500 / 3.6, unit: .kilometersPerHour, status: "实时测速中", isOverLimit: false)
        .veloPanel().padding(20).background(VeloTheme.background)
        .preferredColorScheme(.light)
}
