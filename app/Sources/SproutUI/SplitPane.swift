import AppKit
import SwiftUI

/// `top` above a draggable divider, `bottom` below. The bottom's share of the
/// height and its collapsed state persist across launches.
struct SplitPane<Top: View, Bottom: View>: View {
    @AppStorage("sprout.terminalFraction") private var fraction = 0.45
    @AppStorage("sprout.terminalCollapsed") private var collapsed = false
    @State private var dragStartFraction: Double?

    /// Height of the bottom when collapsed: just its tab bar.
    static var collapsedHeight: CGFloat { 30 }

    private let top: Top
    private let bottom: Bottom

    init(@ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let bottomHeight = collapsed
                ? Self.collapsedHeight
                : max(Self.collapsedHeight, (height * fraction).rounded())
            VStack(spacing: 0) {
                top.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                divider(totalHeight: height)
                bottom.frame(height: bottomHeight)
            }
        }
    }

    private func divider(totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: collapsed ? 1 : 5)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside && !collapsed { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard !collapsed, totalHeight > 0 else { return }
                        let start = dragStartFraction ?? fraction
                        dragStartFraction = start
                        fraction = min(0.85, max(0.15, start - value.translation.height / totalHeight))
                    }
                    .onEnded { _ in dragStartFraction = nil })
    }
}
