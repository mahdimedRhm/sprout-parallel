import SproutCore
import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: WorktreeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(store.log.enumerated()), id: \.offset) { index, line in
                            LogLine(line: line).id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: store.log.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            status.padding(.top, 4)
        }
        .font(Theme.mono(11))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.logBg))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
        // Win the free space in the forms over their trailing Spacer.
        .layoutPriority(1)
    }

    @ViewBuilder private var status: some View {
        switch store.operation {
        case .idle:
            EmptyView()
        case .running:
            BlinkingText(text: "● running…", color: Theme.green)
        case .succeeded:
            Text("✓ done · esc to go back").foregroundStyle(Theme.green)
        case .failed(let message):
            Text("✗ \(message)").foregroundStyle(Theme.red)
        }
    }
}

struct LogLine: View {
    let line: String

    var body: some View {
        if line.hasPrefix("$ ") {
            Text("$ ").foregroundStyle(Theme.green) + Text(String(line.dropFirst(2))).foregroundStyle(Theme.bright)
        } else if line.contains("Error") {
            Text(line).foregroundStyle(Theme.red)
        } else if line.contains("Warning") {
            Text(line).foregroundStyle(Theme.amber)
        } else if line.contains("→") {
            Text(line).foregroundStyle(Theme.text)
        } else {
            Text(line).foregroundStyle(Theme.muted)
        }
    }
}

struct BlinkingText: View {
    let text: String
    let color: Color
    @State private var dim = false

    var body: some View {
        Text(text)
            .foregroundStyle(color)
            .opacity(dim ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever()) { dim = true }
            }
    }
}
