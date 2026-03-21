import SwiftUI

/// The interactive SwiftUI overlay that handles the drag gesture for selecting
/// a screen region. Renders a premium liquid glass selection rectangle with
/// rounded corners, glow effects, and an inverted frosted mask.
struct LiquidOverlayView: View {

    // MARK: - Properties

    let screenFrame: CGRect
    let onSelectionComplete: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var isDragging = false
    @State private var selectionCompleted = false
    @State private var showHint = true

    // MARK: - Computed

    private var selectionRect: CGRect {
        guard let start = dragStart, let current = dragCurrent else {
            return .zero
        }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private var dynamicCornerRadius: CGFloat {
        let minDimension = min(selectionRect.width, selectionRect.height)
        // Scale from 4 to 16 depending on selection size
        return min(max(minDimension * 0.04, 4), 16)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dim layer with cutout for selection
                // The mask punches a transparent hole where the user is selecting
                dimLayer(size: geometry.size)

                // If dragging, show the selection border and size
                if isDragging, selectionRect.width > 2 && selectionRect.height > 2 {
                    // The beautiful liquid glass border
                    selectionBorderLayer

                    // Size indicator
                    sizeIndicator
                }

                // Hint text
                if showHint && !isDragging {
                    hintLabel
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                            withAnimation(.easeOut(duration: 0.1)) {
                                showHint = false
                            }
                        }
                        dragCurrent = value.location
                        isDragging = true
                    }
                    .onEnded { _ in
                        isDragging = false
                        selectionCompleted = true

                        // Convert to screen coordinates
                        let screenRect = convertToScreenCoordinates(selectionRect)
                        onSelectionComplete(screenRect)

                        // Reset
                        dragStart = nil
                        dragCurrent = nil
                    }
            )
        }
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Dim Layer with Cutout

    /// Semi-transparent dark overlay that covers the entire screen.
    /// When a selection is active, the selected region is punched out (fully transparent)
    /// so the user can see the actual screen content clearly — just like Windows Snipping Tool.
    @ViewBuilder
    private func dimLayer(size: CGSize) -> some View {
        if isDragging, selectionRect.width > 2 && selectionRect.height > 2 {
            // Dim layer with inverted mask: everything is dimmed except the selection
            Color.black.opacity(0.3)
                .mask(
                    Rectangle()
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: dynamicCornerRadius)
                                .fill(Color.black)
                                .frame(width: selectionRect.width, height: selectionRect.height)
                                .position(
                                    x: selectionRect.midX,
                                    y: selectionRect.midY
                                )
                        )
                        .compositingGroup()
                        .luminanceToAlpha()
                )
                .frame(width: size.width, height: size.height)
        } else {
            // No selection yet — dim the entire screen
            Color.black.opacity(0.3)
                .frame(width: size.width, height: size.height)
        }
    }

    /// Premium liquid glass border around the selection box.
    private var selectionBorderLayer: some View {
        ZStack {
            // Outer glow
            RoundedRectangle(cornerRadius: dynamicCornerRadius + 2)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: selectionRect.width + 2, height: selectionRect.height + 2)
                .position(x: selectionRect.midX, y: selectionRect.midY)
                .shadow(color: Color.white.opacity(0.3), radius: 8, x: 0, y: 0)
                .shadow(color: Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.2), radius: 16, x: 0, y: 0)

            // Inner bright ring
            RoundedRectangle(cornerRadius: dynamicCornerRadius)
                .stroke(Color.white.opacity(0.85), lineWidth: 0.5)
                .frame(width: selectionRect.width, height: selectionRect.height)
                .position(x: selectionRect.midX, y: selectionRect.midY)

            // Corner handles for visual polish
            ForEach(cornerPositions, id: \.id) { corner in
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.white.opacity(0.5), radius: 4)
                    .position(corner.point)
            }

            // Inner shadow effect (subtle)
            RoundedRectangle(cornerRadius: dynamicCornerRadius)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
                .frame(width: selectionRect.width - 2, height: selectionRect.height - 2)
                .position(x: selectionRect.midX, y: selectionRect.midY)
                .blur(radius: 1)
        }
    }

    /// Displays the pixel dimensions of the selection.
    private var sizeIndicator: some View {
        let width = Int(selectionRect.width)
        let height = Int(selectionRect.height)

        return Text("\(width) × \(height)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .position(
                x: selectionRect.midX,
                y: selectionRect.maxY + 24
            )
    }

    /// Initial hint displayed when overlay opens.
    private var hintLabel: some View {
        VStack(spacing: 8) {
            Image(systemName: "crop")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.7))

            Text("Click and drag to select a region")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))

            Text("Press Esc to cancel")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.4))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Corner Positions

    private struct CornerPoint: Identifiable {
        let id: Int
        let point: CGPoint
    }

    private var cornerPositions: [CornerPoint] {
        let rect = selectionRect
        return [
            CornerPoint(id: 0, point: CGPoint(x: rect.minX, y: rect.minY)),
            CornerPoint(id: 1, point: CGPoint(x: rect.maxX, y: rect.minY)),
            CornerPoint(id: 2, point: CGPoint(x: rect.minX, y: rect.maxY)),
            CornerPoint(id: 3, point: CGPoint(x: rect.maxX, y: rect.maxY))
        ]
    }

    // MARK: - Coordinate Conversion

    /// Convert view-local coordinates to absolute screen coordinates.
    /// macOS uses bottom-left origin for screen coordinates, while SwiftUI uses top-left.
    private func convertToScreenCoordinates(_ rect: CGRect) -> CGRect {
        // The view coordinates are relative to the screen frame
        let screenX = screenFrame.origin.x + rect.origin.x
        // Flip Y: screen coordinates have origin at bottom-left
        let screenY = screenFrame.origin.y + (screenFrame.height - rect.origin.y - rect.height)

        return CGRect(
            x: screenX,
            y: screenY,
            width: rect.width,
            height: rect.height
        )
    }
}
