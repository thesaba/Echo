import SwiftUI

struct PulsingCircle: View {
    let color: Color
    let baseOpacity: Double
    let size: CGFloat
    let maxScale: CGFloat

    @State private var animate = false

    init(color: Color, baseOpacity: Double = 0.35, size: CGFloat, maxScale: CGFloat = 1.08) {
        self.color = color
        self.baseOpacity = baseOpacity
        self.size = size
        self.maxScale = maxScale
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(animate ? maxScale : 1.0)
            .opacity(animate ? baseOpacity : max(baseOpacity - 0.15, 0))
            .onAppear { animate = true }
            .onDisappear { animate = false }
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animate)
    }
}
