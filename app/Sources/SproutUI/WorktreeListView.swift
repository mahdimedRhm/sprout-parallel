import AppKit
import SproutCore
import SproutTerminal
import SwiftUI

struct WorktreeListView: View {
    @EnvironmentObject private var store: WorktreeStore

    var body: some View {
        if let project = store.selectedProject {
            if project.worktrees.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("no worktrees in \(project.name)").foregroundStyle(Theme.muted)
                    ActionChip(key: "n", label: "create one", tint: Theme.green) { store.beginCreate() }
                }
            } else {
                // Rows sit directly above the detail when they fit; otherwise
                // the rows scroll and the detail stays pinned below them.
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        clearAllBar(project)
                        WorktreeRow.header
                        rows(project)
                        detail
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        clearAllBar(project)
                        WorktreeRow.header
                        ScrollViewReader { proxy in
                            ScrollView { rows(project) }
                                .onChange(of: store.selectedWorktreePath) { _, path in
                                    if let path { proxy.scrollTo(path) }
                                }
                        }
                        .frame(maxHeight: .infinity)
                        detail
                    }
                }
            }
        } else {
            Text(store.isRefreshing ? "loading…" : "no projects found").foregroundStyle(Theme.muted)
        }
    }

    private func clearAllBar(_ project: Project) -> some View {
        HStack {
            Text("\(project.worktrees.count) worktree\(project.worktrees.count == 1 ? "" : "s") in \(project.name)")
                .foregroundStyle(Theme.muted)
            Spacer()
            ActionChip(key: "⇧X", label: "clear all", tint: Theme.red) { store.beginClear() }
                .font(Theme.mono(11))
        }
        .padding(.bottom, 8)
    }

    private func rows(_ project: Project) -> some View {
        VStack(spacing: 1) {
            ForEach(project.worktrees) { worktree in
                WorktreeRow(worktree: worktree, selected: worktree.path == store.selectedWorktreePath)
                    .id(worktree.path)
                    .onTapGesture(count: 2) { Openers.vscode(worktree.path) }
                    .onTapGesture { store.selectedWorktreePath = worktree.path }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let worktree = store.selectedWorktree {
            WorktreeDetail(worktree: worktree)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WorktreeRow: View {
    let worktree: Worktree
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("●").foregroundStyle(worktree.isDirty ? Theme.amber : Theme.green).frame(width: 12)
            Text(worktree.branch)
                .foregroundStyle(selected ? Theme.bright : Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            SyncText(ahead: worktree.ahead, behind: worktree.behind).frame(width: 72, alignment: .leading)
            Text(worktree.serveUrl == nil ? "—" : "●")
                .foregroundStyle(worktree.isServing ? Theme.green : Theme.muted)
                .help(worktree.isServing ? "serving on \(worktree.serveUrl ?? "")" : "not serving")
                .frame(width: 44, alignment: .leading)
            Text(worktree.redisDb.map { "db:\($0)" } ?? "—")
                .foregroundStyle(worktree.redisDb == nil ? Theme.muted : Theme.cyan)
                .frame(width: 44, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 3).fill(selected ? Theme.selection : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Theme.selectionEdge : Color.clear))
        .contentShape(Rectangle())
    }

    static var header: some View {
        HStack(spacing: 8) {
            Text("").frame(width: 12)
            Text("BRANCH").frame(maxWidth: .infinity, alignment: .leading)
            Text("SYNC").frame(width: 72, alignment: .leading)
            Text("SERVE").frame(width: 44, alignment: .leading)
            Text("REDIS").frame(width: 44, alignment: .leading)
        }
        .font(Theme.mono(10))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }
}

struct SyncText: View {
    let ahead: Int?
    let behind: Int?

    var body: some View {
        if let ahead, let behind {
            HStack(spacing: 4) {
                Text("↑\(ahead)").foregroundStyle(ahead > 0 ? Theme.green : Theme.muted)
                Text("↓\(behind)").foregroundStyle(behind > 0 ? Theme.red : Theme.muted)
            }
        } else {
            Text("—").foregroundStyle(Theme.muted)
        }
    }
}

struct WorktreeDetail: View {
    @EnvironmentObject private var store: WorktreeStore
    @EnvironmentObject private var terminals: TerminalSessions
    let worktree: Worktree

    private func serviceStatus(_ service: Service) -> some View {
        let running = terminals.isServiceRunning(service, in: worktree.path)
        return HStack(spacing: 4) {
            Text(running ? "● running" : "○ stopped").foregroundStyle(running ? Theme.green : Theme.muted)
            if !running { Text("· \(service == .serve ? "s" : "q") to start").foregroundStyle(Theme.muted) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            KV("base") { Text(worktree.base) }
            KV("head") { head }
            KV("dirty") {
                Text(worktree.isDirty ? "\(worktree.changes) file\(worktree.changes == 1 ? "" : "s")" : "clean")
                    .foregroundStyle(worktree.isDirty ? Theme.amber : Theme.green)
            }
            KV("mysql") {
                if worktree.dbFailed == true {
                    Text("✗ not created — see the create log").foregroundStyle(Theme.red)
                } else {
                    Text(worktree.mysqlDb ?? "—").foregroundStyle(worktree.mysqlDb == nil ? Theme.muted : Theme.violet)
                }
            }
            KV("redis") { redis }
            KV("herd") {
                if let url = worktree.herdUrl {
                    Button(url) { Openers.browser(url) }.buttonStyle(.plain).foregroundStyle(Theme.cyan)
                } else {
                    Text("—").foregroundStyle(Theme.muted)
                }
            }
            KV("serve") {
                if let url = worktree.serveUrl {
                    HStack(spacing: 6) {
                        Text("●").foregroundStyle(worktree.isServing ? Theme.green : Theme.muted)
                        Button(url) { Openers.browser(url) }
                            .buttonStyle(.plain)
                            .foregroundStyle(worktree.isServing ? Theme.cyan : Theme.muted)
                        serviceStatus(.serve)
                    }
                } else {
                    serviceStatus(.serve)
                }
            }
            KV("queue") { serviceStatus(.queue) }
            KV("path") {
                Text((worktree.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            HStack(spacing: 12) {
                ActionChip(key: "⏎", label: "code", tint: Theme.green) { Openers.vscode(worktree.path) }
                ActionChip(key: "t", label: "warp") { Openers.warp(worktree.path) }
                ActionChip(key: "f", label: "finder") { Openers.finder(worktree.path) }
                if let url = worktree.herdUrl {
                    ActionChip(key: "o", label: "herd") { Openers.browser(url) }
                }
                if let url = worktree.serveUrl {
                    ActionChip(key: "⇧O", label: "serve") { Openers.browser(url) }
                }
                ActionChip(key: "⌫", label: "delete", tint: Theme.red) { store.beginDelete() }
            }
            .font(Theme.mono(11))
            .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bar))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
    }

    @ViewBuilder private var head: some View {
        if let commit = worktree.lastCommit {
            (Text(commit.hash).foregroundStyle(Theme.amber)
                + Text(" \(commit.subject)").foregroundStyle(Theme.text)
                + Text(" · \(commit.when)").foregroundStyle(Theme.muted))
                .lineLimit(1)
        } else {
            Text("—").foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private var redis: some View {
        if worktree.redisDb == nil && worktree.redisPrefix == nil {
            Text("—").foregroundStyle(Theme.muted)
        } else {
            HStack(spacing: 6) {
                if let db = worktree.redisDb { Text("db:\(db)").foregroundStyle(Theme.cyan) }
                if let prefix = worktree.redisPrefix { Text("\(prefix)*").foregroundStyle(Theme.violet).lineLimit(1) }
            }
        }
    }
}
