import AppKit
import SwiftUI

/// `top` above a draggable divider, `bottom` below. The bottom's share of the
/// height and its collapsed state persist across launches.
struct SplitPane<Top: View, Bottom: View>: View {
    @AppStorage("sprout.terminalFraction") private var fraction = 0.45
    @AppStorage("sprout.terminalCollapsed") private var collapsed = false
    @State private var dragStartFraction: Double?
    @State private var hovering = false
    @State private var dragging = false
    @State private var cursorPushed = false

    /// The top always keeps at least this much height: in list mode that's the
    /// header, two rows and the details card.
    static var minimumTopHeight: CGFloat { 300 }

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
            let dividerHeight: CGFloat = collapsed ? 1 : 5
            let wanted = collapsed
                ? Self.collapsedHeight
                : max(Self.collapsedHeight, (height * fraction).rounded())
            let room = height - Self.minimumTopHeight - dividerHeight
            let bottomHeight = max(Self.collapsedHeight, min(wanted, room))
            VStack(spacing: 0) {
                top.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
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
                hovering = inside
                updateCursor()
            }
            .onChange(of: collapsed) { _, _ in updateCursor() }
            .onDisappear {
                hovering = false
                dragging = false
                updateCursor()
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard !collapsed, totalHeight > 0 else { return }
                        if !dragging {
                            dragging = true
                            updateCursor()
                        }
                        let start = dragStartFraction ?? fraction
                        dragStartFraction = start
                        fraction = min(0.85, max(0.15, start - value.translation.height / totalHeight))
                    }
                    .onEnded { _ in
                        dragStartFraction = nil
                        dragging = false
                        updateCursor()
                    })
    }

    /// Push the resize cursor once when hover or a drag starts; pop once when both end.
    private func updateCursor() {
        let wanted = (hovering || dragging) && !collapsed
        if wanted && !cursorPushed {
            NSCursor.resizeUpDown.push()
            cursorPushed = true
        } else if !wanted && cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}
