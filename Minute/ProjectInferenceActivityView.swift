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

    private let segmentLength: CGFloat = 0.24
    private let gradient = LinearGradient(
        colors: [.pink, .purple, .blue, .cyan, .green, .yellow, .orange],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let progress = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 2.8) / 2.8
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let segmentEnd = CGFloat(progress) + segmentLength

            ZStack {
                inferenceSegment(
                    shape: shape,
                    from: CGFloat(progress),
                    to: min(segmentEnd, 1)
                )

                if segmentEnd > 1 {
                    inferenceSegment(
                        shape: shape,
                        from: 0,
                        to: segmentEnd - 1
                    )
                }
            }
            .padding(-1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func inferenceSegment(
        shape: RoundedRectangle,
        from start: CGFloat,
        to end: CGFloat
    ) -> some View {
        ZStack {
            shape
                .trim(from: start, to: end)
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 4)
                .opacity(0.65)

            shape
                .trim(from: start, to: end)
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
                )
        }
    }
}
