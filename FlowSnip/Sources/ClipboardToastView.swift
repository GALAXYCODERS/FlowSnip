import SwiftUI

/// A liquid glass styled toast that confirms a screenshot was copied to the clipboard.
/// Animates in with a bouncy scale, shimmers, then floats away.
struct ClipboardToastView: View {

    @State private var isVisible = false
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.green, Color.mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Copied to Clipboard")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Glass background
                Capsule()
                    .fill(.ultraThinMaterial)

                // Gradient border (liquid glass)
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )

                // Shimmer sweep
                Capsule()
                    .stroke(Color.white.opacity(0.4), lineWidth: 1.2)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.45),
                                .init(color: .white, location: 0.55),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 80)
                        .offset(x: shimmerOffset)
                    )
            }
        )
        .compositingGroup()
        .shadow(color: Color.white.opacity(0.25), radius: 10, x: 0, y: 0)
        .shadow(color: Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.15), radius: 20, x: 0, y: 0)
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        .scaleEffect(isVisible ? 1.0 : 0.5)
        .opacity(isVisible ? 1.0 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            // Animate in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                isVisible = true
            }

            // Shimmer sweep
            withAnimation(
                .easeInOut(duration: 0.8)
                .delay(0.3)
            ) {
                shimmerOffset = 200
            }

            // Animate out
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeIn(duration: 0.35)) {
                    isVisible = false
                }
            }
        }
    }
}
