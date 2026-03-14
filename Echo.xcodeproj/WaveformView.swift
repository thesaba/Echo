import SwiftUI

struct WaveformView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = time * 2.0

            Canvas { context, size in
                let baseY = size.height / 2
                let width = size.width

                func path(phase: Double, amplitude: Double, frequency: Double) -> Path {
                    var path = Path()
                    let step = width / 60
                    var x: CGFloat = 0
                    var first = true
                    while x <= width {
                        let relative = Double(x / width)
                        let y = baseY + CGFloat(sin(relative * frequency * .pi * 2 + phase) * amplitude)
                        if first {
                            path.move(to: CGPoint(x: x, y: y))
                            first = false
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        x += step
                    }
                    return path
                }

                let phase1 = phase
                let phase2 = phase * 1.4 + .pi / 2
                let phase3 = phase * 1.8 + .pi

                // subtle breathing on amplitudes
                let amp1 = 6 + 3 * sin(phase * 0.6)
                let amp2 = 10 + 4 * sin(phase * 0.8 + .pi / 3)
                let amp3 = 14 + 5 * sin(phase * 1.0 + .pi / 1.5)

                let gradient = Gradient(colors: [
                    Color.echoPurple.opacity(0.1),
                    Color.echoPurple.opacity(0.9),
                    Color.echoPurple.opacity(0.1)
                ])

                // back wave
                let path1 = path(phase: phase1, amplitude: amp1, frequency: 1.4)
                context.stroke(
                    path1,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: baseY),
                        endPoint: CGPoint(x: width, y: baseY)
                    ),
                    lineWidth: 2
                )

                // middle wave
                let path2 = path(phase: phase2, amplitude: amp2, frequency: 1.8)
                context.stroke(
                    path2,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: baseY - 4),
                        endPoint: CGPoint(x: width, y: baseY + 4)
                    ),
                    lineWidth: 3
                )

                // front wave
                let path3 = path(phase: phase3, amplitude: amp3, frequency: 2.2)
                context.stroke(
                    path3,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: baseY - 8),
                        endPoint: CGPoint(x: width, y: baseY + 8)
                    ),
                    lineWidth: 4
                )
            }
        }
    }
}
