# Sprout — macOS menu bar app for sprout-parallel

Date: 2026-09-29
Status: Design approved in chat, pending spec review

## Goal

A macOS menu bar app to view and manage sprout-parallel worktrees across all
projects under `$SPROUT_PROJECTS_ROOT`, without using the terminal.

**In scope**

- View all projects and their worktrees: branch, uncommitted changes,
  commits ahead/behind base, last commit, MySQL DB, Redis DB and prefix.
- Create a worktree (project, branch, base branch, setup on/off).
- Delete a worktree (with `--force` and `--keep-db` equivalents).
- Open a worktree in VS Code, Warp, or Finder.
- Launch at login (off by default).

**Out of scope**

- Deleting the git branch itself (the CLI keeps it; so does the app).
- Pushing, pulling, merging, or other git operations.
- Editors other than VS Code; terminals other than Warp.
- Distribution to other machines (ad-hoc signed, local install only).

## Architecture

The bash script stays the single source of truth for all worktree logic.
The app is a UI over it:

```
Sprout.app ──(zsh -lc)──▶ sprout-parallel status --json   → reads state
                         ▶ sprout-parallel create …        → mutates
                         ▶ sprout-parallel delete …        → mutates
           ──(open -a)───▶ VS Code / Warp / Finder
```

All commands run through `/bin/zsh -lc` so the app gets the user's login-shell
`PATH` (GUI apps don't inherit it; `mysql`, `redis-cli`, `composer`, `npm`, and
`~/.local/bin` would otherwise be missing).

## Part 1 — Script changes (`sprout-parallel`)

### 1.1 `status --json`

New command. Prints one JSON document to stdout and exits 0. Exit 1 if
`--json` is omitted (the command is JSON-only for now).

Includes every directory under `$SPROUT_PROJECTS_ROOT` that is a git repo and
does not end in `-worktrees`. Projects with at least one worktree are sorted
first, then alphabetically within each group.

```json
{"projects":[{
  "name":"scooda",
  "path":"/Users/mehdi/projects/scooda",
  "branches":["develop","main","production"],
  "worktrees":[{
    "branch":"feature/payments-v2",
    "folder":"feature-payments-v2",
    "path":"/Users/mehdi/projects/scooda-worktrees/feature-payments-v2",
    "base":"main",
    "changes":3,
    "ahead":3,
    "behind":1,
    "lastCommit":{"hash":"a1f9c2e","subject":"Add Stripe webhook","when":"2 hours ago"},
    "mysqlDb":"scooda_feature_payments_v2",
    "redisDb":3,
    "redisPrefix":"scooda_feature_payments_v2_"
  }]
}]}
```

Field rules:

| Field | Source | When unavailable |
|---|---|---|
| `branches` | `git for-each-ref refs/heads` in the main project, sorted | `[]` |
| `worktrees` | same discovery as `cmd_list` (`<project>-worktrees/*/` with `.git`) | `[]` |
| `branch` | `git rev-parse --abbrev-ref HEAD` | `"unknown"` |
| `base` | `git config branch.<branch>.sproutBase` | `"main"` |
| `changes` | line count of `git status --porcelain` | `0` |
| `ahead` / `behind` | `git rev-list --left-right --count <base>...HEAD` | `null` if base ref missing |
| `lastCommit` | `git log -1 --format=%h` / `%s` / `%cr` | `null` |
| `mysqlDb` | `DB_DATABASE` in worktree `.env` | `null` |
| `redisDb` | `REDIS_DB` in worktree `.env`, as a number | `null` |
| `redisPrefix` | `REDIS_PREFIX` in worktree `.env` | `null` |

All strings pass through a `json_escape` helper that escapes `\`, `"`, and
control characters (`\n`, `\t`, `\r`, others as `\u00XX`).

### 1.2 `create` records the base branch

After `git worktree add`, run
`git -C <project> config branch.<branch>.sproutBase <base>`.
Worktrees created earlier fall back to `main` in `status`.

### 1.3 Help

`help` lists `status --json`; `help status` describes it.

No other CLI behaviour changes.

## Part 2 — The app (`app/`)

SwiftPM package, macOS 14+ (needed for `onKeyPress`), Swift 6 toolchain from Command Line Tools
(no Xcode required).

### 2.1 Targets

- **`SproutCore`** (library) — all non-UI logic, unit-tested.
- **`Sprout`** (executable) — SwiftUI `MenuBarExtra` with `.window` style;
  thin layer over `SproutCore`.
- **`SproutCoreTests`** — tests for `SproutCore`.

### 2.2 SproutCore units

| Unit | Responsibility | Depends on |
|---|---|---|
| `Shell` (protocol) + `LoginShell` | Run a command via `/bin/zsh -lc`, stream stdout+stderr lines, return exit code. `shellQuote()` for arguments. | Foundation `Process` |
| `SproutCLI` | Build argument lists: `status --json`; `create <branch> --project <p> --from <base> [--no-setup]`; `delete <branch> --project <p> [--force] [--keep-db]`. Detect "script not found" (exit 127). | `Shell` |
| `Models` | `Codable` types for the status JSON (`Status`, `Project`, `Worktree`, `LastCommit`). | — |
| `WorktreeStore` | `@MainActor ObservableObject`: `projects`, `selectedProject`, `selectedWorktree`, `operation` (idle / running / failed(message)), `log: [String]`, `error: String?`. Methods `refresh()`, `create(...)`, `delete(...)`. Only one create/delete at a time. Keeps last good data when refresh fails. Refreshes after each create/delete regardless of outcome. | `SproutCLI`, `Models` |
| `Openers` | VS Code: `open -a "Visual Studio Code" <path>`. Warp: `open -a Warp <path>`. Finder: `NSWorkspace.activateFileViewerSelecting`. | AppKit |

### 2.3 Views (layout B — project sidebar + table)

Panel ~560pt wide.

- **Header:** "🌱 Worktrees", refresh button (spinner while refreshing).
- **Sidebar:** all projects with worktree count; selected project highlighted.
- **Right pane, default:** table of the selected project's worktrees —
  status dot (green clean / orange dirty), branch, `↑ahead ↓behind`, Redis DB.
  Selecting a row shows a detail box: base, last commit subject + when, MySQL
  DB, Redis DB + prefix, and buttons **VS Code · Warp · Finder · Delete…**.
- **Right pane, create:** "New worktree in <project>" — branch field with live
  folder preview (`/` → `-`), "From" picker (project `branches`, default
  `main` if present), "Run setup" checkbox (on). Cancel / Create. Live log below.
- **Right pane, delete:** "Delete <branch>?" — warning if `changes > 0`;
  "Discard uncommitted changes" checkbox (`--force`, required when dirty; Delete
  disabled until ticked); "Drop MySQL DB & clear Redis keys" checkbox (on;
  off = `--keep-db`); note that the branch is kept. Cancel / Delete. Live log.
- **Footer:** "＋ New worktree in <project>", "Launch at login" toggle
  (`SMAppService.mainApp`), Quit.
- The list refreshes when the panel opens and after every create/delete.

### 2.3a Visual style — terminal

Approved mockup: `.superpowers/brainstorm/*/content/terminal-style.html`.

- Always dark (`#0b0f14` background, `#1f2a36` borders), regardless of system
  appearance. Monospace everywhere: JetBrains Mono if installed, else SF Mono
  (`.monospaced` design).
- Palette: neon green `#39ffa0` actions/clean/prompt, amber `#ffcc66` dirty,
  red `#ff6b6b` behind/danger, cyan `#56d4ff` Redis, violet `#c792ea` DB names,
  muted `#6b7a8c` labels, bright `#e6edf3` primary text.
- Header reads like a prompt: `❯ sprout ~/projects` with worktree count and
  "refreshed Ns ago".
- Table: `●` status dot, branch, `↑n ↓n`, `db:N`; column headers uppercase muted.
  Detail is a key/value box (`base`, `head <hash> <subject> · <when>`, `dirty`,
  `mysql`, `redis`).
- Inputs are underlined fields with a blinking block caret.
- Every create/delete log starts with the exact command:
  `$ sprout-parallel create feature/x --project scooda --from main`.
- Keyboard-first, with hints in the footer. List: `⏎` VS Code, `t` Warp,
  `f` Finder, `n` new, `⌫` delete, `r` refresh, `↑↓` move row,
  `⇧↑`/`⇧↓` move project. Forms: `⌘⏎` confirm, `esc` cancel.

### 2.4 Error handling

| Situation | Behaviour |
|---|---|
| Script not on login-shell PATH (exit 127) | Panel shows "`sprout-parallel` not found — run install.sh" instead of the list. |
| `status` non-zero exit or invalid JSON | Keep previous data; red banner with the stderr / decode error. |
| `create` / `delete` non-zero exit | Log stays visible; red banner with the last `Error:` line; list refreshed. |
| MySQL / Redis unavailable | Script already warns and continues; warnings appear in the log. |

### 2.5 Build & install

`app/build.sh`:

1. `swift build -c release` in `app/`.
2. Assemble `app/build/Sprout.app` (`Contents/MacOS/Sprout`,
   `Contents/Info.plist` with `LSUIElement=true`, bundle id
   `agency.manza.sprout`, `LSMinimumSystemVersion=14.0`).
3. `codesign --force --sign - Sprout.app` (ad-hoc).
4. Copy to `~/Applications/Sprout.app`.

`app/.build/` and `app/build/` are gitignored, as is `.superpowers/`.

## Testing

- **Bash — `tests/status_test.sh`:** creates a scratch
  `SPROUT_PROJECTS_ROOT` with a project and worktrees; asserts `status --json`
  parses (`python3 -m json.tool`) and contains expected values, including:
  commit subject with `"` and `\`; ahead/behind against a recorded
  `sproutBase`; a worktree without `.env` (null DB fields); a project with no
  worktrees; `create` writes `sproutBase`. Exits non-zero on any failure.
- **Swift — `swift test`:** decoding a fixture captured from real
  `status --json` output; `SproutCLI` argument building for every flag
  combination and shell quoting of branch names; `WorktreeStore` with a fake
  `Shell`: refresh success, refresh failure keeps old data, script-not-found,
  single-operation guard, refresh after create/delete. If `swift test` cannot
  run under Command Line Tools, these become a `SproutCoreChecks` executable
  target that asserts and exits non-zero — verified before implementation.
- **End-to-end:** build and launch the app; against a scratch project, create
  and delete a worktree through the UI; screenshot each state.
