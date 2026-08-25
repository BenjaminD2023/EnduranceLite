import SwiftUI

/// Green battery + infinity mark, drawn to match the original Endurance badge.
struct EnduranceMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                BatteryBody()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.86, blue: 0.38),
                                Color(red: 0.30, green: 0.72, blue: 0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.18), radius: w * 0.03, y: w * 0.02)

                BatteryBody()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.45)
                        )
                    )

                InfinityGlyph()
                    .stroke(Color.white.opacity(0.96), style: StrokeStyle(lineWidth: h * 0.13, lineCap: .round, lineJoin: .round))
                    .frame(width: w * 0.62, height: h * 0.42)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(1.55, contentMode: .fit)
        .accessibilityLabel("EnduranceLite")
    }
}

private struct BatteryBody: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let nubWidth = rect.width * 0.08
        let body = CGRect(
            x: rect.minX,
            y: rect.minY + rect.height * 0.08,
            width: rect.width - nubWidth,
            height: rect.height * 0.84
        )
        path.addRoundedRect(in: body, cornerSize: CGSize(width: body.height * 0.22, height: body.height * 0.22))

        let nub = CGRect(
            x: body.maxX - 1,
            y: rect.midY - rect.height * 0.16,
            width: nubWidth + 1,
            height: rect.height * 0.32
        )
        path.addRoundedRect(in: nub, cornerSize: CGSize(width: nub.height * 0.35, height: nub.height * 0.35))
        return path
    }
}

private struct InfinityGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: mid)
        path.addCurve(
            to: mid,
            control1: CGPoint(x: rect.minX - rect.width * 0.05, y: rect.minY - rect.height * 0.15),
            control2: CGPoint(x: rect.minX - rect.width * 0.05, y: rect.maxY + rect.height * 0.15)
        )
        path.addCurve(
            to: mid,
            control1: CGPoint(x: rect.maxX + rect.width * 0.05, y: rect.minY - rect.height * 0.15),
            control2: CGPoint(x: rect.maxX + rect.width * 0.05, y: rect.maxY + rect.height * 0.15)
        )
        return path
    }
}

struct GhostIcon: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var body = Path()
            body.addEllipse(in: CGRect(x: w * 0.12, y: h * 0.08, width: w * 0.76, height: h * 0.62))
            body.addRect(CGRect(x: w * 0.12, y: h * 0.38, width: w * 0.76, height: h * 0.32))
            let waveY = h * 0.70
            body.move(to: CGPoint(x: w * 0.12, y: waveY))
            body.addQuadCurve(to: CGPoint(x: w * 0.37, y: waveY), control: CGPoint(x: w * 0.25, y: h * 0.92))
            body.addQuadCurve(to: CGPoint(x: w * 0.62, y: waveY), control: CGPoint(x: w * 0.50, y: h * 0.92))
            body.addQuadCurve(to: CGPoint(x: w * 0.88, y: waveY), control: CGPoint(x: w * 0.75, y: h * 0.92))
            context.fill(body, with: .color(.secondary))

            let eyeR = w * 0.07
            context.fill(Path(ellipseIn: CGRect(x: w * 0.32, y: h * 0.30, width: eyeR * 2, height: eyeR * 2)), with: .color(Color(nsColor: .windowBackgroundColor)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.58, y: h * 0.30, width: eyeR * 2, height: eyeR * 2)), with: .color(Color(nsColor: .windowBackgroundColor)))
        }
        .accessibilityHidden(true)
    }
}

struct MenuBatteryGlyph: View {
    var percent: Int
    var charging: Bool
    var onBattery: Bool
    var lowPower: Bool = false

    /// Same yellow macOS uses for the menu-bar battery in Low Power Mode.
    private var iconColor: Color {
        if !charging && percent <= 10 { return Color.red }
        if lowPower { return Color(nsColor: .systemYellow) }
        return Color.primary
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(iconColor, lineWidth: 1.2)
                    .frame(width: 19, height: 9)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(iconColor)
                    .frame(width: max(1.5, 15.5 * CGFloat(percent) / 100), height: 5.5)
                    .padding(.leading, 1.7)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(iconColor)
                        .offset(x: 5)
                }
            }
            RoundedRectangle(cornerRadius: 0.5)
                .fill(iconColor)
                .frame(width: 1.6, height: 4)
        }
        .frame(height: 12)
        .opacity(onBattery || charging || lowPower ? 1 : 0.85)
    }
}
