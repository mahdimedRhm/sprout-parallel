# Sprout — command palette, serve/queue control, database actions

Date: 2026-09-30
Status: Design approved in chat, pending spec review
Builds on: the Sprout app and embedded terminals specs (2026-09-29, 2026-09-30)

## Goal

Per worktree, start/restart/stop `php artisan serve` and the queue worker, and
create/refresh/drop its database — reachable from anywhere in Sprout, including
while a terminal has focus, without ever taking keys the shell needs.

**In scope**
- Command palette (`⌘⇧P`) listing every action for the selected worktree.
- Serve and queue as named terminal tabs with start / restart / stop.
- `sprout-parallel db create|refresh|drop` + palette actions, with the
  never-touch-the-main-database guard.
- "db: migrate:fresh --seed" in a terminal tab.

**Out of scope**
- Auto-starting serve/queue on create; custom commands per project.
- Other extras (tinker, logs, npm dev, pulling base) — piece 4.

## 1. Command palette

- `⌘⇧P` opens it from anywhere (window-level shortcut like `⌘T`; the shell
  never sees it). With the list focused, `s` / `q` / `d` open it pre-filtered
  with `serve` / `queue` / `db`.
- Overlay: a search field and a list of actions for the selected worktree;
  `↑`/`↓` select, `⏎` runs, `esc` or clicking outside closes. The field has
  focus while open, so typing never reaches the list or the terminal.
- Matching: the query is split on whitespace; an action matches when every
  token appears (case-insensitive) in its title. Order: actions whose title
  starts with the first token first, then the rest in catalog order.
- Catalog (titles verbatim; `·` groups):
  - `serve: start`, `serve: restart`, `serve: stop`
  - `queue: start`, `queue: restart`, `queue: stop`
  - `db: create from main`, `db: refresh from main`, `db: drop`,
    `db: migrate:fresh --seed`
  - `open: VS Code`, `open: Warp`, `open: Finder`, `open: Herd URL`,
    `open: serve URL`
  - `worktree: new`, `worktree: delete`, `worktree: clear all in project`,
    `refresh`
- Unavailable actions are listed dimmed with a reason and don't run:
  restart/stop when not running, start when running, `open: Herd URL` without
  one, any worktree action with no worktree selected, db/worktree actions while
  another operation runs ("busy: …").
- With nothing selected (empty project) only project-level actions show.

## 2. Serve and queue

- Commands: serve = `php artisan serve` (uses the worktree's `SERVER_PORT`).
  Queue = `php artisan horizon` when the worktree's `composer.json` requires
  `laravel/horizon`, else `php artisan queue:work`.
- Each runs in a **service tab** of the worktree's terminal: a normal terminal
  tab tracked as that worktree's `serve` or `queue` tab and labelled
  `serve` / `queue` in the tab bar (with the busy `●`).
- **start:** reuse the service tab if it exists and is idle, else open one;
  type the command + ⏎. Show the terminal (expand if collapsed) and activate
  that tab. Keyboard focus is not moved.
- **restart:** send `⌃C` (`\u{3}`) to the service tab, wait until it is idle
  (≤ 5 s, polling), then type the command + ⏎. If still busy after 5 s,
  terminate the tab and start fresh.
- **stop:** send `⌃C`, wait until idle (≤ 5 s), then close the tab (terminate
  if still busy).
- Running = the service tab exists and is busy. Details box gains
  `serve  ● running` / `○ stopped` and `queue  ● running` / `○ stopped`
  (next to the existing URLs); the SERVE column keeps reflecting the port.
- Closing a service tab by hand (×, ⌘⇧W, exit) just forgets it.
- Quit warning already lists busy tabs, so running services are included.

## 3. Database commands (script)

`sprout-parallel db <create|refresh|drop> <branch-or-folder> [--project <name>]`

- Worktree resolved like `delete` (safe_name → folder under
  `<project>-worktrees/`). The main database is `DB_DATABASE` in the main
  project's `.env`; the worktree's database name is always
  `<main>_<db_safe_name(folder)>` (what `create` would have made).
  Credentials (`DB_USERNAME`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`) come from the
  worktree's `.env`, falling back to the main project's.
- **Guard:** refuse (exit 1, `Error: …`) when the main database name is empty,
  or the target name equals the main database name.
- **create:** `CREATE DATABASE IF NOT EXISTS`; clone main into it with
  `mysqldump | mysql` only if it has no tables yet; set the worktree's
  `DB_DATABASE` to it and clear `SPROUT_DB_FAILED`. Says "already exists" and
  skips cloning when it has tables.
- **refresh:** `DROP DATABASE IF EXISTS`, `CREATE DATABASE`, clone; same `.env`
  update.
- **drop:** `DROP DATABASE IF EXISTS`; set the worktree's `DB_DATABASE=` (empty).
- MySQL failures exit 2 with the MySQL message and a final `Error:` line; `.env`
  is only updated after success. `mysql`/`mysqldump` missing → exit 1 with a
  clear `Error:`.
- `help db` documents it; `help` lists it.

In Sprout, the three db actions run as background operations (header log, `l`)
after a confirmation for **refresh** ("Replace <db> with a fresh copy of
<main>?") and **drop** ("Drop <db>?"). `db: migrate:fresh --seed` asks to confirm
("Rebuild <db> from migrations? All its data is lost."), then runs in a
`migrate` terminal tab (not tracked as a service).

## Architecture

| Unit | Where | Responsibility |
|---|---|---|
| `cmd_db` + helpers | `sprout-parallel` | the db commands |
| `PaletteMatcher` | SproutCore | query → matching titles, ordered (pure, tested) |
| `ServiceCommand` | SproutCore | serve/queue command for a worktree path (Horizon detection) |
| `SproutCLI.dbCommand(action:project:folder:)` + `WorktreeStore.database(_:worktree:)` | SproutCore | run db commands as background operations (`Activity.Kind.database(action, branch)`) |
| `TerminalHandle.send(_:)` | SproutTerminal | type text into a shell (fakes record it) |
| `TerminalSessions` service API | SproutTerminal | `serviceTab(_:in:)`, `isServiceRunning(_:in:)`, `startService`, `restartService`, `stopService`, service labels |
| `CommandPalette` view + action catalog | SproutUI | overlay, keyboard, availability, running actions |
| PanelView/Chrome changes | SproutUI | `⌘⇧P`, `s`/`q`/`d`, service labels in tab bar, details rows, cheat sheet, footer |

## Testing

- `tests/db_test.sh` (stub `mysql`/`mysqldump` recording calls): create
  (new / already has tables), refresh (drop+create+clone order), drop, the
  guard, credential fallback, MySQL failure exits 2 without touching `.env`,
  missing mysql.
- `SproutCoreChecks`: `PaletteMatcher` (tokens, order, case), `ServiceCommand`
  (horizon vs queue:work), db command strings, store db operation +
  activity titles.
- `SproutTerminalChecks`: service start/restart/stop with fake handles
  (recorded sends, ⌃C then command, reuse, timeout → terminate, stop closes,
  hand-closed tab forgotten); live: start `sleep 30` as a service in a real
  shell, restart, stop.
- `SproutKeyChecks`: `⌘⇧P` opens the palette from the list and from the
  terminal; typing filters; `⏎` runs (via `Openers.intercept`/fakes); `esc`
  closes and returns focus where it was; `s`/`q`/`d` prefilter; typing in the
  palette doesn't reach the list or the shell.
- Snapshots: palette open, details with service rows.
