# Sprout — embedded terminals per worktree

Date: 2026-09-30
Status: Design approved in chat, pending spec review
Builds on: `2026-09-29-sprout-menubar-app-design.md` (the Sprout app)

## Goal

Every worktree gets its own terminal tabs inside the Sprout window, running the
user's real shell in the worktree folder, so serving, queue workers, and ad-hoc
commands live next to the worktree's info.

**In scope**
- Terminal tabs per worktree (open, close, switch), titled after what's running.
- Layout A: worktree table + details on top, terminal below, draggable divider,
  collapsible with ``⌃` ``.
- Keys go to the shell when the terminal has focus.
- Terminals of vanished worktrees close automatically.
- Quit warns when a tab has a command running.
- Terminal colours match Sprout's palette.

**Out of scope**
- Keeping shells alive across Sprout quits (no tmux).
- Split panes inside the terminal area; find-in-terminal; custom fonts.
- Per-worktree startup commands (e.g. auto-running `php artisan serve`).

## Engine

SwiftTerm (MIT, https://github.com/migueldeicaza/SwiftTerm), pinned
`.upToNextMinor(from: "1.20.0")`. Verified with a probe on this machine:
`LocalProcessTerminalView.startProcess(executable:args:environment:execName:currentDirectory:)`
starts `zsh -l` in a folder; `LocalProcessTerminalViewDelegate` delivers
`setTerminalTitle` and `processTerminated`; `tcgetpgrp(view.process.childfd)` +
`proc_name` gives the foreground process (`zsh` idle, `sleep` while running).
SwiftTerm declares tools-version 6.0; the root package stays at 5.9 and builds.

This is the app's first third-party dependency; SwiftPM fetches it from GitHub
on the first build.

## Behaviour

### Sessions
- A worktree's first tab starts when its terminal area is first shown for it.
- Shell: `/bin/zsh -l`, cwd = worktree path, environment = Sprout's environment
  plus `TERM=xterm-256color`, `COLORTERM=truecolor`, `LANG` defaulting to
  `en_US.UTF-8` if unset.
- `⌘T` new tab (same folder); `⌘⇧W` closes the active tab — confirms first if
  the tab is busy. `＋` in the tab bar = `⌘T`; clicking a tab activates it.
- Tab title = foreground process name when busy (`php`, `npm`, `sleep`), else
  the shell's title if it set one, else `zsh`. Titles refresh at least once per
  second while the window is visible.
- A tab whose shell exits (`exit`, crash) is removed. If it was the last tab of
  the worktree, the terminal area shows "no terminal · ⌘T to open".
- Switching worktree shows that worktree's tabs; others keep running.
- After every worktree refresh, tabs of worktrees no longer present are
  terminated and removed (covers delete, clear, external removal).
- Quit (`⌘Q`, footer "quit", app menu): if any tab is busy, an alert lists them
  (`<title> — <project>/<folder>`) with "Quit anyway" / "Cancel"; otherwise quit
  immediately. All shells are terminated on quit.

### Keyboard & focus
- When the terminal view is first responder, every key goes to the shell
  (including `esc`, `⏎`, letters, arrows). Sprout's single-key list shortcuts
  don't fire.
- ``⌃` `` toggles focus list ⇄ terminal; if the terminal is collapsed it expands
  first. Clicking the terminal focuses it.
- `⌘W`, `⌘Q`, `⌘T`, `⌘⇧W` work regardless of focus. `⌘C`/`⌘V` copy/paste in
  the terminal (SwiftTerm).
- Footer hints add ``⌃` terminal`` and `⌘T new tab` in list mode.

### Layout (A)
- Right pane = vertical split: top = existing content (table + details, or the
  create / delete / clear forms), bottom = terminal area (tab bar + terminal).
- Divider draggable; split fraction persisted (UserDefaults
  `sprout.terminalFraction`, default 0.45 of the pane height; clamp 0.15–0.85).
- Collapsed state persisted (`sprout.terminalCollapsed`); collapsed shows only
  the tab bar. Collapsing never stops shells.
- No worktree selected (empty project): terminal area shows
  "select a worktree to open its terminal".

### Look
- Background `#070A0D`, foreground `#C9D1D9`, caret `#39FFA0`, selection
  `#1D3A4A`, font SF Mono 12 (JetBrains Mono if installed, as elsewhere).
- ANSI 16: black `#0B0F14`, red `#FF6B6B`, green `#39FFA0`, yellow `#FFCC66`,
  blue `#56D4FF`, magenta `#C792EA`, cyan `#56D4FF`, white `#C9D1D9`; bright
  variants: `#6B7A8C`, `#FF8A8A`, `#7CFFC0`, `#FFDD99`, `#8AE2FF`, `#DDB3F5`,
  `#8AE2FF`, `#E6EDF3`.
- Tab bar: active tab bright text with green top border (as in the approved
  mockup `terminal-layout.html`), busy tabs show a green `●`.

## Architecture

New library target **`SproutTerminal`** (depends on `SproutCore`, `SwiftTerm`).

| Unit | Responsibility |
|---|---|
| `TerminalHandle` (protocol) | What sessions need from a shell: `id`, `title`, `isBusy`, `terminate()`, `onExit` callback. |
| `ShellTerminal` | Real handle: owns a `LocalProcessTerminalView`, starts `zsh -l` in the folder, applies the theme, computes title/busy from the foreground process + shell title, calls `onExit` on `processTerminated`. |
| `TerminalSessions` | `@MainActor ObservableObject`. Tabs per worktree path, active tab per path; `tabs(for:)`, `activeTab(for:)`, `openTab(in:)`, `closeTab(_:)`, `activate(_:)`, `prune(keeping: Set<String>)`, `busyTabs() -> [(worktreePath, title)]`, `terminateAll()`. Creates handles through an injected `(String) -> TerminalHandle` factory so its logic is testable with fakes. |
| `TerminalTheme` | Palette → SwiftTerm colours/caret/selection/font. |
| `TerminalPane` (SwiftUI) | Tab bar + `NSViewRepresentable` hosting the active tab's view + empty states. |
| `SplitPane` (SwiftUI) | Top/bottom split with draggable divider, persisted fraction, collapse. |

Changes to existing code:
- `PanelView`: right pane becomes `SplitPane(top: content, bottom: TerminalPane)`;
  ``⌃` `` / `⌘T` / `⌘⇧W` handling; focus hand-off.
- `FooterBar`: hints.
- `SproutApp` / `AppDelegate`: owns one `TerminalSessions`, passes it via
  `environmentObject`; prunes on `WorktreeStore.projects` change;
  `applicationShouldTerminate` shows the busy alert and terminates shells.
- `SproutSnapshots`: renders with a fake-handle `TerminalSessions` (the AppKit
  terminal itself doesn't render in `ImageRenderer`).

## Error handling

| Situation | Behaviour |
|---|---|
| `zsh` fails to start | Tab shows `✗ could not start shell` in red, `⌘T` retries. |
| Foreground lookup fails (fd closed) | Treated as idle, title falls back to `zsh`. |
| Worktree folder gone before first open | Tab is not created; pane shows the "select a worktree" state after the next refresh prunes it. |

## Testing

- **`SproutTerminalChecks`** (new executable target, same harness style as
  `SproutCoreChecks`):
  - Fake handles: open/close/activate per worktree, tabs isolated per path,
    active tab moves to a neighbour on close, exit removes the tab, prune
    removes and terminates vanished worktrees' tabs, `busyTabs` lists only busy
    ones, `terminateAll` terminates every handle.
  - Live (`ShellTerminal`): starts in a temp folder (`pwd` output contains it),
    `sleep 3` → busy with title `sleep`, back to idle after, `exit` fires
    `onExit`.
- Existing suites (`tests/*.sh`, `SproutCoreChecks`) keep passing.
- Snapshots updated for the split layout (terminal area shows tab bar + empty
  state under fakes).
- End-to-end by the user: checklist covering serve in one tab, `vim` + `esc`,
  switching worktrees, ``⌃` `` focus, collapse, quit warning, delete closes
  terminals.
