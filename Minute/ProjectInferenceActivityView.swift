import SwiftUI

struct ProjectInferenceSpinner: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: 16, height: 16)
            .help("Inferring project with local Codex")
            .accessibilityLabel("Inferring project")
    }
}

struct ProjectInferenceGlow: View {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors: [Color] = [
        .pink, .purple, .blue, .cyan, .green, .yellow, .orange, .pink
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 4.8) / 4.8
            let angle = CGFloat(phase) * .pi * 2
            let gradientRadius: CGFloat = 0.7
            let startPoint = UnitPoint(
                x: 0.5 + cos(angle) * gradientRadius,
                y: 0.5 + sin(angle) * gradientRadius
            )
            let endPoint = UnitPoint(
                x: 0.5 - cos(angle) * gradientRadius,
                y: 0.5 - sin(angle) * gradientRadius
            )
            let gradient = LinearGradient(
                colors: colors,
                startPoint: startPoint,
                endPoint: endPoint
            )
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack {
                shape
                    .stroke(gradient, lineWidth: 3)
                    .blur(radius: 3)
                    .opacity(0.22)

                shape
                    .stroke(gradient, lineWidth: 1.25)
                    .opacity(0.62)
            }
            .padding(-0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
