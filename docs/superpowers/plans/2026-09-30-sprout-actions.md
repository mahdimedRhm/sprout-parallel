# Sprout Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `⌘⇧P` command palette with per-worktree serve/queue start/restart/stop (in named terminal tabs) and database create/refresh/drop.

**Architecture:** The script gets `sprout-parallel db create|refresh|drop`. SproutCore gets pure helpers (palette matching, service commands, db command strings) and a background `database` operation on `WorktreeStore`. SproutTerminal gets `TerminalHandle.send(_:)` and a service-tab API on `TerminalSessions`. SproutUI gets the palette overlay (catalog + availability), service labels and status rows, and the new keys.

**Tech Stack:** bash 3.2 + python3 (tests); Swift 5.9 tools / CLT 6.2, SwiftUI/AppKit, SwiftTerm 1.20.x.

**Spec:** `docs/superpowers/specs/2026-09-30-sprout-actions-design.md`

## Global Constraints

- Script stays bash 3.2 + `set -euo pipefail`; exit codes: 0 ok, 1 user error, 2 MySQL/git failure; every failure prints an `Error:` line last.
- The worktree database name is always `<main DB_DATABASE>_<db_safe_name(folder)>`. Never run DROP/CREATE against the main database name; refuse when the main `DB_DATABASE` is empty.
- `.env` is only changed after the MySQL steps succeed.
- Palette titles verbatim: `serve: start|restart|stop`, `queue: start|restart|stop`, `db: create from main`, `db: refresh from main`, `db: drop`, `db: migrate:fresh --seed`, `open: VS Code|Warp|Finder|Herd URL|serve URL`, `worktree: new|delete|clear all in project`, `refresh`.
- Keys: `⌘⇧P` palette from anywhere (SwiftUI shortcut `"P"` with `[.command, .shift]` — shifted shortcuts need the shifted character); `s`/`q`/`d` in the list open it prefiltered with `serve `/`queue `/`db `. In the palette: `↑`/`↓`, `⏎`, `esc`.
- Serve command `php artisan serve`; queue `php artisan horizon` if the worktree's `composer.json` contains `"laravel/horizon"`, else `php artisan queue:work`. Restart/stop: send `\u{3}`, wait ≤ 5 s for idle (poll 0.1 s), then rerun / close; still busy → terminate.
- Tests: `bash tests/*.sh`, `cd app && swift run SproutCoreChecks`, `swift run SproutTerminalChecks`, `swift run SproutKeyChecks` (real window, ~60 s; the Mac must not be used meanwhile), `swift run SproutSnapshots`. No new warnings from our sources.
- Every commit ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never commit build output or `.superpowers/`.

## Review Focus

1. **A worktree whose `.env` has `DB_DATABASE` empty or wrong** (failed setup, earlier drop) → `db create` still targets `<main>_<folder>` and fixes `.env`; never the main DB. Pinned: Task 1 (`create repairs an emptied DB_DATABASE`).
2. **`db refresh` where the clone fails midway** → exit 2, `.env` untouched (the old name stays; the dropped DB is gone but main is untouched). Pinned: Task 1 (`failed refresh leaves .env alone`).
3. **A service command that ignores ⌃C** → restart/stop don't hang: after 5 s the tab is terminated. Pinned: Task 3 (`restart terminates a tab that ignores ⌃C`).
4. **Typing in the palette** never reaches the list shortcuts or the shell (e.g. typing `n` or `d`). Pinned: Task 4 key checks (`typing in the palette triggers no list action`).
5. **Running a db action while another operation runs** → shown unavailable ("busy: …"), not started. Pinned: Task 2 (`database is refused while busy`), Task 4 availability.

---

### Task 1: `sprout-parallel db create|refresh|drop`

**Files:**
- Modify: `sprout-parallel` (add `cmd_db` + helpers after `cmd_clear`, dispatcher line, help)
- Create: `tests/db_test.sh`

**Interfaces:**
- Consumes: existing `die`, `die2`, `resolve_project` (sets `REPLY_PROJECT_NAME`/`REPLY_PROJECT_PATH`), `safe_name`, `db_safe_name`, `parse_env_value`, `set_env_var`, `$SPROUT_PROJECTS_ROOT`, `$SCRIPT_NAME`.
- Produces: `sprout-parallel db <create|refresh|drop> <branch-or-folder> [--project <name>]`.

- [ ] **Step 1: Write the failing test**

`tests/db_test.sh`:

```bash
#!/usr/bin/env bash
# Tests for `sprout-parallel db create|refresh|drop`. Run: bash tests/db_test.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SP="$REPO/sprout-parallel"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export SPROUT_PROJECTS_ROOT="$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Stub mysql: records every call; `SELECT COUNT` answers from $ROOT/tables;
# CREATE fails while $ROOT/fail exists; import mode (no -e) records stdin.
STUBS="$ROOT/stubs"
CALLS="$ROOT/calls.log"
mkdir "$STUBS"
: > "$CALLS"
cat > "$STUBS/mysql" <<STUB
#!/bin/sh
echo "mysql \$*" >> "$CALLS"
case "\$*" in
  *"SELECT COUNT"*) cat "$ROOT/tables" 2>/dev/null || echo 0 ;;
  *"CREATE DATABASE"*)
    if [ -f "$ROOT/fail" ]; then echo "ERROR 1044: Access denied"; exit 1; fi ;;
  *" -e "*) ;;
  *) echo "import: \$(cat)" >> "$CALLS" ;;
esac
exit 0
STUB
cat > "$STUBS/mysqldump" <<STUB
#!/bin/sh
for last; do :; done
echo "DUMP OF \$last"
STUB
chmod +x "$STUBS"/*
export PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin"

FAILS=0

assert_eq() {
  if [[ "$1" == "$2" ]]; then echo "ok   - $3"; else echo "FAIL - $3: expected [$2], got [$1]"; FAILS=$((FAILS + 1)); fi
}

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then echo "ok   - $3"; else
    echo "FAIL - $3: [$2] not found in:"; echo "$1" | sed 's/^/       /'; FAILS=$((FAILS + 1)); fi
}

WT="$ROOT/eta-worktrees/feature-a"
env_of() { grep "^$1=" "$WT/.env" | head -1 | cut -d= -f2-; }

mkdir "$ROOT/eta"
git -C "$ROOT/eta" init -q -b main
git -C "$ROOT/eta" commit -q --allow-empty -m init
printf '.env\n' > "$ROOT/eta/.git/info/exclude"
printf 'DB_CONNECTION=mysql\nDB_DATABASE=eta\nDB_USERNAME=root\nDB_PASSWORD=pw\n' > "$ROOT/eta/.env"
"$SP" create feature/a --project eta --no-setup > /dev/null 2>&1
# As if setup had failed: DB_DATABASE cleared, marker set, no DB_USERNAME
printf 'DB_CONNECTION=mysql\nDB_DATABASE=\nSPROUT_DB_FAILED=1\n' > "$WT/.env"

# ─── create ───────────────────────────────────────────────────────────────────

rc=0; out="$("$SP" db create feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "0" "create exits 0"
assert_contains "$(cat "$CALLS")" 'CREATE DATABASE IF NOT EXISTS `eta_feature_a`' "create targets <main>_<folder>"
assert_contains "$(cat "$CALLS")" "import: DUMP OF eta" "create clones main into it"
assert_eq "$(env_of DB_DATABASE)" "eta_feature_a" "create repairs an emptied DB_DATABASE"
assert_eq "$(env_of SPROUT_DB_FAILED)" "" "create clears the failure marker"
assert_contains "$(cat "$CALLS")" "-uroot" "credentials fall back to the main project's .env"

: > "$CALLS"; echo 5 > "$ROOT/tables"
out="$("$SP" db create feature/a --project eta 2>&1)"
assert_contains "$out" "already exists" "create skips cloning a database that has tables"
assert_eq "$(grep -c 'import:' "$CALLS" || true)" "0" "no clone when it already has tables"
rm "$ROOT/tables"

# ─── refresh ──────────────────────────────────────────────────────────────────

: > "$CALLS"
rc=0; "$SP" db refresh feature-a --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "refresh exits 0 (folder name accepted too)"
order="$(grep -oE 'DROP DATABASE|CREATE DATABASE|import:' "$CALLS" | tr '\n' ' ')"
assert_eq "$order" "DROP DATABASE CREATE DATABASE import: " "refresh drops, creates, then clones"
assert_contains "$(cat "$CALLS")" 'DROP DATABASE IF EXISTS `eta_feature_a`' "refresh drops only the worktree database"

: > "$CALLS"; touch "$ROOT/fail"
rc=0; out="$("$SP" db refresh feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "2" "a MySQL failure exits 2"
assert_contains "$(echo "$out" | tail -1)" "Error:" "the failure ends with an Error: line"
assert_eq "$(env_of DB_DATABASE)" "eta_feature_a" "failed refresh leaves .env alone"
rm "$ROOT/fail"

# ─── drop ─────────────────────────────────────────────────────────────────────

: > "$CALLS"
rc=0; "$SP" db drop feature/a --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "drop exits 0"
assert_contains "$(cat "$CALLS")" 'DROP DATABASE IF EXISTS `eta_feature_a`' "drop drops the worktree database"
assert_eq "$(grep -c 'DROP DATABASE IF EXISTS `eta`;' "$CALLS" || true)" "0" "drop never touches the main database"
assert_eq "$(env_of DB_DATABASE)" "" "drop clears DB_DATABASE"

# ─── guards and errors ────────────────────────────────────────────────────────

printf 'DB_CONNECTION=mysql\nDB_USERNAME=root\n' > "$ROOT/eta/.env"
rc=0; out="$("$SP" db create feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "1" "no main DB_DATABASE → exit 1"
assert_contains "$out" "Error:" "…with an Error: line"
printf 'DB_CONNECTION=mysql\nDB_DATABASE=eta\nDB_USERNAME=root\nDB_PASSWORD=pw\n' > "$ROOT/eta/.env"

rc=0; "$SP" db explode feature/a --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "1" "unknown action exits 1"
rc=0; "$SP" db create feature/nope --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "1" "unknown worktree exits 1"

mv "$STUBS/mysql" "$ROOT/mysql.off"
rc=0; out="$("$SP" db create feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "1" "missing mysql exits 1"
assert_contains "$out" "mysql is not installed" "…and says so"
mv "$ROOT/mysql.off" "$STUBS/mysql"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
if [[ "$FAILS" -eq 0 ]]; then echo "all tests passed"; else echo "$FAILS test(s) failed"; exit 1; fi
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/db_test.sh < /dev/null`
Expected: `FAIL - create exits 0: expected [0], got [1]` (unknown command) and more; exit 1.

- [ ] **Step 3: Implement**

In `sprout-parallel`, add after `cmd_clear() { … }`:

```bash
# db_env: a DB_* value from the worktree .env, falling back to the main one
#   $1: key  $2: worktree .env  $3: main .env
db_env() {
  local value
  value="$(parse_env_var "$1" "$2")"
  [[ -n "$value" ]] || value="$(parse_env_var "$1" "$3")"
  echo "$value"
}

cmd_db() {
  local action="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$action" in
    create|refresh|drop) ;;
    *) die "Usage: $SCRIPT_NAME db <create|refresh|drop> <branch> [--project <name>]" ;;
  esac

  local branch="" project_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        [[ -n "${2:-}" ]] || die "Missing value for --project."
        project_arg="$2"
        shift 2
        ;;
      -*) die "Unknown option: $1. Run '$SCRIPT_NAME help db' for usage." ;;
      *)
        [[ -z "$branch" ]] || die "Unexpected argument: $1. Run '$SCRIPT_NAME help db' for usage."
        branch="$1"
        shift
        ;;
    esac
  done
  [[ -n "$branch" ]] || die "Missing required argument: <branch>. Run '$SCRIPT_NAME help db' for usage."

  resolve_project "$project_arg"
  local proj_name="$REPLY_PROJECT_NAME"
  local proj_path="$REPLY_PROJECT_PATH"
  local folder
  folder="$(safe_name "$branch")"
  local worktree_path="$SPROUT_PROJECTS_ROOT/${proj_name}-worktrees/$folder"
  [[ -d "$worktree_path" ]] || die "No worktree found for '$branch' in project '$proj_name'."

  local wt_env="$worktree_path/.env"
  local main_env="$proj_path/.env"
  [[ -f "$wt_env" ]] || die "Worktree '$folder' has no .env."

  local main_db
  main_db="$(parse_env_value DB_DATABASE "$main_env")"
  [[ -n "$main_db" ]] || die "The main project's .env has no DB_DATABASE — nothing to clone from."
  local target="${main_db}_$(db_safe_name "$folder")"
  [[ "$target" != "$main_db" ]] || die "Refusing to touch the main database '$main_db'."

  command -v mysql > /dev/null 2>&1 || die "mysql is not installed."

  local db_user db_pass db_host db_port
  db_user="$(db_env DB_USERNAME "$wt_env" "$main_env")"
  db_pass="$(db_env DB_PASSWORD "$wt_env" "$main_env")"
  db_host="$(db_env DB_HOST "$wt_env" "$main_env")"
  db_port="$(db_env DB_PORT "$wt_env" "$main_env")"
  [[ -n "$db_user" ]] || die "No DB_USERNAME in the worktree's or the main project's .env."
  export MYSQL_PWD="$db_pass"
  local mysql_opts="-h${db_host:-127.0.0.1} -P${db_port:-3306} -u${db_user}"

  case "$action" in
    create)
      echo "Creating database '$target'"
      # shellcheck disable=SC2086
      mysql $mysql_opts -e "CREATE DATABASE IF NOT EXISTS \`${target}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
        || die2 "MySQL could not create '$target'."
      local tables
      # shellcheck disable=SC2086
      tables="$(mysql $mysql_opts -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${target}';" 2>/dev/null || true)"
      if [[ "${tables:-0}" =~ ^[0-9]+$ && "${tables:-0}" -gt 0 ]]; then
        echo "Database '$target' already exists ($tables tables) — not cloning."
      else
        db_clone "$mysql_opts" "$main_db" "$target"
      fi
      ;;
    refresh)
      echo "Refreshing '$target' from '$main_db'"
      # shellcheck disable=SC2086
      mysql $mysql_opts -e "DROP DATABASE IF EXISTS \`${target}\`;" || die2 "MySQL could not drop '$target'."
      # shellcheck disable=SC2086
      mysql $mysql_opts -e "CREATE DATABASE \`${target}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
        || die2 "MySQL could not create '$target'."
      db_clone "$mysql_opts" "$main_db" "$target"
      ;;
    drop)
      echo "Dropping database '$target'"
      # shellcheck disable=SC2086
      mysql $mysql_opts -e "DROP DATABASE IF EXISTS \`${target}\`;" || die2 "MySQL could not drop '$target'."
      unset MYSQL_PWD
      set_env_var DB_DATABASE "" "$wt_env"
      echo "Dropped '$target'; DB_DATABASE cleared in the worktree .env."
      return 0
      ;;
  esac

  unset MYSQL_PWD
  set_env_var DB_DATABASE "$target" "$wt_env"
  set_env_var SPROUT_DB_FAILED "" "$wt_env"
  echo "Updated .env: DB_DATABASE=$target"
}

# db_clone: copy the main database into the worktree one
#   $1: mysql options  $2: source  $3: target
db_clone() {
  command -v mysqldump > /dev/null 2>&1 || die "mysqldump is not installed."
  echo "Cloning data from '$2' into '$3'"
  # shellcheck disable=SC2086
  mysqldump $1 --single-transaction --set-gtid-purged=OFF "$2" | mysql $1 "$3" \
    || die2 "Cloning '$2' into '$3' failed."
}
```

Dispatcher (in `main()`, after the `clear)` line):

```bash
    db)        cmd_db     "$@" ;;
```

Help: add a `db)` topic before `delete)` in `cmd_help`:

```bash
    db)
      cat <<EOF
COMMAND: $SCRIPT_NAME db <create|refresh|drop> <branch> [--project <name>]

  Manages a worktree's own MySQL database, <main DB_DATABASE>_<folder>.
  Never touches the main project's database.

ACTIONS:
  create    Create it if missing; clone the main database into it when it has
            no tables yet. Points the worktree .env at it.
  refresh   Drop it, create it again and clone the main database into it.
  drop      Drop it and clear DB_DATABASE in the worktree .env.

EXIT CODES:
  0  Success
  1  User error (no worktree, no main DB_DATABASE, mysql missing)
  2  MySQL failed (the worktree .env is left unchanged)
EOF
      ;;
```

In the main help's COMMANDS list add after the `clear` line: `  db <action> <b>   Create / refresh / drop a worktree's database`. Add `  $SCRIPT_NAME help db` to the help list and `db` to the unknown-topic message (`Available: create, delete, clear, db, list, status`).

- [ ] **Step 4: Run to verify it passes**

Run: `bash -n sprout-parallel && for t in db db_setup status clear serve; do bash tests/${t}_test.sh < /dev/null | tail -1; done`
Expected: `all tests passed` ×5.

- [ ] **Step 5: Commit**

```bash
git add sprout-parallel tests/db_test.sh
git commit -m "Add 'db create|refresh|drop' for a worktree's own database

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: SproutCore — palette matching, service commands, database operation

**Files:**
- Create: `app/Sources/SproutCore/PaletteMatcher.swift`, `app/Sources/SproutCore/ServiceCommand.swift`
- Modify: `app/Sources/SproutCore/SproutCLI.swift`, `app/Sources/SproutCore/WorktreeStore.swift`
- Create: `app/Sources/SproutCoreChecks/ActionChecks.swift`; Modify: `app/Sources/SproutCoreChecks/main.swift`

**Interfaces:**
- Consumes: `WorktreeStore` (`activity`, `isBusy`, `perform` pattern in `create/delete/clear`, `loadStatus()`), `SproutCLI` command builders, `shellQuote`.
- Produces (public):
  - `enum PaletteMatcher { static func matches(_ title: String, query: String) -> Bool; static func order<T>(_ items: [T], query: String, title: (T) -> String) -> [T] }`
  - `enum ServiceCommand { static let serve: String; static func queue(worktreePath: String) -> String }`
  - `enum DatabaseAction: String { case create, refresh, drop }`
  - `SproutCLI.dbCommand(action: DatabaseAction, project: String, folder: String) -> String`
  - `WorktreeStore.Activity.Kind.database(DatabaseAction, branch: String)`; `WorktreeStore.database(_ action: DatabaseAction, worktree: Worktree) async`
  - `WorktreeStore.palette: String?` (`@Published public var`; nil = closed) and `paletteSelection: Int` (`@Published public var`, default 0)

- [ ] **Step 1: Write the failing checks**

`app/Sources/SproutCoreChecks/ActionChecks.swift`:

```swift
import CheckKit
import Foundation
import SproutCore

@MainActor
func actionChecks() async {
    // Palette matching
    check(PaletteMatcher.matches("serve: restart", query: "ser re"), "every token must appear")
    check(!PaletteMatcher.matches("serve: restart", query: "ser xyz"), "a missing token fails the match")
    check(PaletteMatcher.matches("DB: Drop", query: "db drop"), "matching ignores case")
    check(PaletteMatcher.matches("anything", query: "  "), "an empty query matches everything")
    let titles = ["open: serve URL", "serve: start", "queue: start", "serve: stop"]
    checkEqual(PaletteMatcher.order(titles, query: "serve", title: { $0 }),
               ["serve: start", "serve: stop", "open: serve URL"],
               "titles starting with the first token come first, then catalog order")

    // Service commands
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprout-svc-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    checkEqual(ServiceCommand.serve, "php artisan serve", "serve command")
    checkEqual(ServiceCommand.queue(worktreePath: dir.path), "php artisan queue:work", "queue:work without composer.json")
    try? #"{"require":{"laravel/framework":"^11.0","laravel/horizon":"^5.0"}}"#
        .write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
    checkEqual(ServiceCommand.queue(worktreePath: dir.path), "php artisan horizon", "horizon when required")

    // db command strings
    checkEqual(SproutCLI.dbCommand(action: .refresh, project: "scooda", folder: "feature-x"),
               "sprout-parallel db refresh feature-x --project scooda", "db command")

    // Store: database operation
    var calls: [String] = []
    let shell = FakeShell { command in
        calls.append(command)
        if command.contains(" db ") { return ShellResult(exitCode: 0, stdout: "Refreshing 'x'\n") }
        return ShellResult(exitCode: 0, stdout: statusJSON(["feature/a"]))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()
    guard let worktree = store.selectedWorktree else { return check(false, "fixture has a worktree") }
    await store.database(.refresh, worktree: worktree)
    check(calls.contains("sprout-parallel db refresh feature-a --project scooda"), "database runs the db command")
    checkEqual(store.operation, .succeeded, "database succeeds")
    checkEqual(store.activity?.doneTitle, "database refreshed for feature/a", "database done title")
    checkEqual(store.activity?.runningTitle, "refreshing the database of feature/a", "database running title")
    checkEqual(WorktreeStore.Activity(kind: .database(.drop, branch: "b"), project: "p").failedTitle,
               "database drop failed", "database failed title")
    checkEqual(calls.last, "sprout-parallel status --json", "refreshes after a database action")

    // Refused while another operation runs
    shell.delayNanos = 200_000_000
    store.beginCreate()
    let running = Task { await store.create(branch: "feature/z", base: "main", runSetup: true) }
    try? await Task.sleep(nanoseconds: 50_000_000)
    let before = calls.count
    await store.database(.drop, worktree: worktree)
    check(!calls.dropFirst(before).contains { $0.contains(" db ") }, "database is refused while busy")
    await running.value

    // Palette state
    checkEqual(store.palette, nil, "palette starts closed")
    store.palette = "serve "
    checkEqual(store.paletteSelection, 0, "selection starts at the top")
}
```

Replace `app/Sources/SproutCoreChecks/main.swift`'s last lines so it also runs `await actionChecks()` before `finishChecks()`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd app && swift build --product SproutCoreChecks 2>&1 | grep -m2 error:`
Expected: `cannot find 'PaletteMatcher' in scope`.

- [ ] **Step 3: Implement**

`app/Sources/SproutCore/PaletteMatcher.swift`:

```swift
import Foundation

/// Command-palette matching: every whitespace-separated token of the query must
/// appear (case-insensitive) in the title.
public enum PaletteMatcher {
    public static func matches(_ title: String, query: String) -> Bool {
        let haystack = title.lowercased()
        return tokens(query).allSatisfy { haystack.contains($0) }
    }

    /// Matching items: titles starting with the first token first, then the
    /// rest, each group in the original (catalog) order.
    public static func order<T>(_ items: [T], query: String, title: (T) -> String) -> [T] {
        let matching = items.filter { matches(title($0), query: query) }
        guard let first = tokens(query).first else { return matching }
        let leading = matching.filter { title($0).lowercased().hasPrefix(first) }
        let rest = matching.filter { !title($0).lowercased().hasPrefix(first) }
        return leading + rest
    }

    private static func tokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
```

`app/Sources/SproutCore/ServiceCommand.swift`:

```swift
import Foundation

/// The commands behind the serve and queue services.
public enum ServiceCommand {
    public static let serve = "php artisan serve"

    /// Horizon when the worktree requires it, else a plain queue worker.
    public static func queue(worktreePath: String) -> String {
        let composer = URL(fileURLWithPath: worktreePath).appendingPathComponent("composer.json")
        let contents = (try? String(contentsOf: composer, encoding: .utf8)) ?? ""
        return contents.contains("\"laravel/horizon\"") ? "php artisan horizon" : "php artisan queue:work"
    }
}
```

In `SproutCLI.swift`, add above `public struct SproutCLI`:

```swift
public enum DatabaseAction: String {
    case create, refresh, drop
}
```

and inside `SproutCLI`, after `clearCommand`:

```swift
    public static func dbCommand(action: DatabaseAction, project: String, folder: String) -> String {
        ["sprout-parallel", "db", action.rawValue, shellQuote(folder), "--project", shellQuote(project)]
            .joined(separator: " ")
    }
```

In `WorktreeStore.swift`:
1. `Activity.Kind`: add `case database(DatabaseAction, branch: String)`.
2. Titles — add cases:
   - `runningTitle`: `.database(let action, let branch)` → `create`: `"creating the database of \(branch)"`, `refresh`: `"refreshing the database of \(branch)"`, `drop`: `"dropping the database of \(branch)"`.
   - `doneTitle`: `"database created for \(branch)"` / `"database refreshed for \(branch)"` / `"database dropped for \(branch)"`.
   - `failedTitle`: `"database \(action.rawValue) failed"`.
3. Below `@Published public var showingKeys = false` add:

```swift
    /// The command palette's query; nil when it's closed.
    @Published public var palette: String? {
        didSet { if palette != oldValue { paletteSelection = 0 } }
    }
    /// The highlighted row in the palette.
    @Published public var paletteSelection = 0
```

4. After `clear(_:force:dropData:)` add:

```swift
    public func database(_ action: DatabaseAction, worktree: Worktree) async {
        guard !isBusy, let project = selectedProject else { return }
        resetOperation()
        activity = Activity(kind: .database(action, branch: worktree.branch), project: project.name)
        let command = SproutCLI.dbCommand(action: action, project: project.name, folder: worktree.folder)
        let outcome = await perform(command)
        await loadStatus()
        operation = outcome
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd app && swift run SproutCoreChecks 2>&1 | grep -E 'FAIL|all checks'`
Expected: `all checks passed`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/SproutCore app/Sources/SproutCoreChecks
git commit -m "Add palette matching, service commands and the database operation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Terminal services (send + service tabs)

**Files:**
- Modify: `app/Sources/SproutTerminal/TerminalHandle.swift`, `ShellTerminal.swift`, `TerminalSessions.swift`
- Modify: `app/Sources/SproutTerminalChecks/FakeTerminal.swift`, `app/Sources/SproutSnapshots/main.swift` (`SnapshotTerminal`)
- Create: `app/Sources/SproutTerminalChecks/ServiceChecks.swift`; Modify: `app/Sources/SproutTerminalChecks/main.swift`

**Interfaces:**
- Consumes: `TerminalSessions` internals (`tabsByPath`, `activeByPath`, `openTab`, `closeTab`, `remove`, `prune`, `terminateAll`).
- Produces (public): `TerminalHandle.send(_ text: String)`; `enum Service: String, CaseIterable { case serve, queue }` in SproutTerminal; on `TerminalSessions`: `var serviceTimeout: TimeInterval` (default 5), `@Published private(set) var servicesByPath: [String: [Service: UUID]]`, `serviceTab(_:in:) -> (any TerminalHandle)?`, `service(of id: UUID, in path: String) -> Service?`, `isServiceRunning(_:in:) -> Bool`, `@discardableResult startService(_:command:in:) -> Bool`, `restartService(_:command:in:) async`, `stopService(_:in:) async`.

- [ ] **Step 1: Write the failing checks**

`app/Sources/SproutTerminalChecks/FakeTerminal.swift` — add to `FakeTerminal`:

```swift
    private(set) var sent: [String] = []
    /// When true, ⌃C doesn't stop the running command.
    var ignoresInterrupt = false

    /// Records input; a line starts a command, ⌃C stops it (unless ignored).
    func send(_ text: String) {
        sent.append(text)
        if text == "\u{3}" {
            if !ignoresInterrupt { isBusy = false }
        } else if text.hasSuffix("\n") {
            isBusy = true
        }
    }
```

`app/Sources/SproutTerminalChecks/ServiceChecks.swift`:

```swift
import CheckKit
import Foundation
import SproutTerminal

@MainActor
func serviceChecks() async {
    var made: [FakeTerminal] = []
    let sessions = TerminalSessions { _ in
        let terminal = FakeTerminal()
        made.append(terminal)
        return terminal
    }
    sessions.serviceTimeout = 0.3
    let path = "/p/demo-worktrees/feature-a"

    check(sessions.startService(.serve, command: "php artisan serve", in: path), "start opens a serve tab")
    let serve = made.last!
    checkEqual(serve.sent, ["php artisan serve\n"], "start types the command")
    check(sessions.isServiceRunning(.serve, in: path), "serve is running")
    checkEqual(sessions.service(of: serve.id, in: path), .serve, "the tab is known as serve")
    check(sessions.activeTab(for: path) === serve, "start activates the service tab")
    check(!sessions.startService(.serve, command: "php artisan serve", in: path), "start refuses when already running")
    checkEqual(made.count, 1, "no second serve tab")

    await sessions.restartService(.serve, command: "php artisan serve", in: path)
    checkEqual(serve.sent, ["php artisan serve\n", "\u{3}", "php artisan serve\n"], "restart sends ⌃C then the command")
    check(sessions.isServiceRunning(.serve, in: path), "running again after restart")

    await sessions.stopService(.serve, in: path)
    check(serve.terminated, "stop closes the serve tab")
    check(sessions.serviceTab(.serve, in: path) == nil, "serve is forgotten after stop")
    check(!sessions.isServiceRunning(.serve, in: path), "serve not running after stop")

    // A command that ignores ⌃C
    sessions.startService(.queue, command: "php artisan queue:work", in: path)
    let stubborn = made.last!
    stubborn.ignoresInterrupt = true
    await sessions.restartService(.queue, command: "php artisan queue:work", in: path)
    check(stubborn.terminated, "restart terminates a tab that ignores ⌃C")
    let fresh = sessions.serviceTab(.queue, in: path) as? FakeTerminal
    check(fresh != nil && fresh !== stubborn, "restart starts a fresh queue tab")
    checkEqual(fresh?.sent, ["php artisan queue:work\n"], "the fresh tab runs the command")

    // Reusing an idle service tab
    fresh?.isBusy = false
    let countBefore = made.count
    sessions.startService(.queue, command: "php artisan queue:work", in: path)
    checkEqual(made.count, countBefore, "start reuses an idle service tab")

    // A service tab closed by hand is forgotten
    if let fresh { sessions.closeTab(fresh.id, in: path) }
    check(sessions.serviceTab(.queue, in: path) == nil, "a hand-closed service tab is forgotten")
    sessions.startService(.serve, command: "php artisan serve", in: path)
    made.last!.exitShell()
    check(sessions.serviceTab(.serve, in: path) == nil, "a service whose shell exits is forgotten")

    // Prune forgets services of vanished worktrees
    sessions.startService(.serve, command: "php artisan serve", in: path)
    sessions.prune(keeping: [])
    check(sessions.serviceTab(.serve, in: path) == nil, "prune forgets services")
    await sessions.stopService(.queue, in: path)   // nothing to stop: no crash
}
```

Append to `app/Sources/SproutTerminalChecks/ShellChecks.swift`, inside `shellChecks()` just before its final closing brace, a live service check:

```swift
    // A real service: start, restart, stop
    let services = TerminalSessions { ShellTerminal(directory: $0) }
    services.serviceTimeout = 5
    check(services.startService(.serve, command: "sleep 30", in: dir.path), "live: service starts")
    check(await waitUntil(8) { services.isServiceRunning(.serve, in: dir.path) }, "live: service is running")
    await services.restartService(.serve, command: "sleep 30", in: dir.path)
    check(await waitUntil(8) { services.isServiceRunning(.serve, in: dir.path) }, "live: running after restart")
    await services.stopService(.serve, in: dir.path)
    check(services.serviceTab(.serve, in: dir.path) == nil, "live: stop closes the tab")
    services.terminateAll()
```

In `app/Sources/SproutTerminalChecks/main.swift`, add `await serviceChecks()` after `await shellChecks()`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd app && swift build --product SproutTerminalChecks 2>&1 | grep -m2 error:`
Expected: errors such as `value of type 'TerminalSessions' has no member 'startService'` / `'Service'`.

- [ ] **Step 3: Implement**

`TerminalHandle.swift` — add to the protocol after `func terminate()`:

```swift
    /// Types text into the shell as if the user did (e.g. "ls\n", or "\u{3}" for ⌃C).
    func send(_ text: String)
```

`ShellTerminal.swift` — add after `terminate()`:

```swift
    public func send(_ text: String) {
        guard !ended else { return }
        terminalView.send(txt: text)
    }
```

`SnapshotTerminal` in `app/Sources/SproutSnapshots/main.swift` — add `func send(_ text: String) {}`.

`TerminalSessions.swift`:

1. Above the class, add:

```swift
/// Long-running commands that get their own, named terminal tab per worktree.
public enum Service: String, CaseIterable {
    case serve, queue
}
```

2. Inside the class, after `private var startedPaths`:

```swift
    /// How long restart/stop wait for ⌃C to stop a service before terminating its tab.
    public var serviceTimeout: TimeInterval = 5
    @Published public private(set) var servicesByPath: [String: [Service: UUID]] = [:]
```

3. Add the service API after `activateTab(at:in:)`:

```swift
    public func serviceTab(_ service: Service, in path: String) -> (any TerminalHandle)? {
        guard let id = servicesByPath[path]?[service] else { return nil }
        return tabs(for: path).first { $0.id == id }
    }

    public func service(of id: UUID, in path: String) -> Service? {
        servicesByPath[path]?.first { $0.value == id }?.key
    }

    public func isServiceRunning(_ service: Service, in path: String) -> Bool {
        serviceTab(service, in: path)?.isBusy ?? false
    }

    /// Runs `command` in the service's tab (reusing it when idle) and shows that
    /// tab. False when it's already running or no shell could start.
    @discardableResult
    public func startService(_ service: Service, command: String, in path: String) -> Bool {
        if let tab = serviceTab(service, in: path) {
            guard !tab.isBusy else { return false }
            tab.send(command + "\n")
            activeByPath[path] = tab.id
            return true
        }
        guard let tab = openTab(in: path) else { return false }
        servicesByPath[path, default: [:]][service] = tab.id
        tab.send(command + "\n")
        return true
    }

    /// ⌃C, wait for the command to stop, run it again. A tab that ignores ⌃C
    /// is terminated and replaced.
    public func restartService(_ service: Service, command: String, in path: String) async {
        guard let tab = serviceTab(service, in: path) else {
            startService(service, command: command, in: path)
            return
        }
        tab.send("\u{3}")
        if await waitUntilIdle(tab) {
            tab.send(command + "\n")
            activeByPath[path] = tab.id
        } else {
            closeTab(tab.id, in: path)
            startService(service, command: command, in: path)
        }
    }

    /// ⌃C, wait for the command to stop, close the tab.
    public func stopService(_ service: Service, in path: String) async {
        guard let tab = serviceTab(service, in: path) else { return }
        tab.send("\u{3}")
        _ = await waitUntilIdle(tab)
        closeTab(tab.id, in: path)
    }

    private func waitUntilIdle(_ tab: any TerminalHandle) async -> Bool {
        let deadline = Date().addingTimeInterval(serviceTimeout)
        while tab.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !tab.isBusy
    }
```

4. Forget services when their tab goes: in `remove(_:in:)`, after `tabs.remove(at: index)`, add:

```swift
        if let service = service(of: id, in: path) { servicesByPath[path]?[service] = nil }
```

In `prune(keeping:)`, inside the loop after `activeByPath[path] = nil`, add `servicesByPath[path] = nil`. In `terminateAll()`, add `servicesByPath = [:]`.

- [ ] **Step 4: Run to verify it passes**

Run: `cd app && swift build 2>&1 | grep -E 'error:|warning:.*/Sources/'; swift run SproutTerminalChecks 2>&1 | grep -E 'FAIL|all checks'; swift run SproutCoreChecks 2>&1 | tail -1`
Expected: no errors/warnings; `all checks passed` twice.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/SproutTerminal app/Sources/SproutTerminalChecks app/Sources/SproutSnapshots
git commit -m "Add service tabs (start/restart/stop) and TerminalHandle.send

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Command palette UI, service labels/status, keys, docs

**Files:**
- Create: `app/Sources/SproutUI/CommandPalette.swift`
- Modify: `app/Sources/SproutUI/PanelView.swift`, `TerminalPane.swift`, `WorktreeListView.swift`, `Chrome.swift`, `KeyCheatSheet.swift`
- Modify: `app/Sources/SproutKeyChecks/main.swift`, `app/Sources/SproutSnapshots/main.swift`, `docs/README.md`

**Interfaces:**
- Consumes: `PaletteMatcher.order`, `ServiceCommand`, `DatabaseAction`, `WorktreeStore.palette`/`paletteSelection`/`database(_:worktree:)`/`isBusy`/`activity`, `TerminalSessions` service API + `openTab` + `send`, `Openers`, `confirmClosingTab`.
- Produces: the palette; `⌘⇧P`; `s`/`q`/`d`; service tab labels; details rows `serve`/`queue` status.

- [ ] **Step 1: Key checks first (failing)**

In `app/Sources/SproutKeyChecks/main.swift`, append inside `keyChecks()` just before the final `Openers.intercept = nil`:

```swift
    // ── Command palette ──────────────────────────────────────────────────
    await focusList()
    store.selectProject("demo")
    await shortcut("P", [.command, .shift], window)
    check(await waitUntil(2) { store.palette != nil }, "⌘⇧P opens the palette from the list")
    opened = []
    await type("open war", into: window)
    await pause(0.2)
    await press(.returnKey, window)
    checkEqual(opened, ["warp:\(pathX)"], "typing filters and ⏎ runs the action")
    check(store.palette == nil, "running an action closes the palette")
    checkEqual(store.mode, .list, "typing in the palette triggers no list action")

    await type("s", into: window)
    checkEqual(store.palette, "serve ", "s opens the palette filtered to serve")
    await press(.escape, window)
    check(store.palette == nil, "esc closes the palette")
    check(window.isVisible, "esc closing the palette doesn't hide the window")
    await type("d", into: window)
    checkEqual(store.palette, "db ", "d opens the palette filtered to db")
    await press(.escape, window)
    await type("q", into: window)
    checkEqual(store.palette, "queue ", "q opens the palette filtered to queue")
    await press(.escape, window)

    await shortcut("`", [.control], window)
    check(await waitUntil(3) { terminals.terminalHasFocus }, "back in the terminal")
    await shortcut("P", [.command, .shift], window)
    check(await waitUntil(2) { store.palette != nil }, "⌘⇧P opens the palette from the terminal")
    opened = []
    await type("open fin", into: window)
    await pause(0.2)
    await press(.returnKey, window)
    checkEqual(opened, ["finder:\(pathX)"], "the palette runs actions opened from the terminal")
    check(await waitUntil(2) { terminals.terminalHasFocus }, "closing the palette returns focus to the terminal")
```

Run: `cd app && swift build --product SproutKeyChecks 2>&1 | grep -m1 error: ; ./.build/debug/SproutKeyChecks 2>&1 | grep -E 'FAIL|checks'`
Expected: FAIL lines for the palette checks (nothing opens yet).

- [ ] **Step 2: Palette view and catalog**

`app/Sources/SproutUI/CommandPalette.swift`:

```swift
import AppKit
import SproutCore
import SproutTerminal
import SwiftUI

/// One command-palette entry. `unavailable` holds the reason it can't run now.
struct PaletteAction: Identifiable {
    let title: String
    var unavailable: String?
    let run: () -> Void
    var id: String { title }
}

/// Every action for the selected worktree, in catalog order, with availability.
@MainActor
func paletteCatalog(store: WorktreeStore, terminals: TerminalSessions, showTerminal: @escaping () -> Void) -> [PaletteAction] {
    let worktree = store.selectedWorktree
    let path = worktree?.path
    let noWorktree = worktree == nil ? "no worktree selected" : nil
    let busy = store.isBusy ? "busy: \(store.activity?.runningTitle ?? "an operation is running")" : nil

    func service(_ service: Service, command: @escaping (String) -> String) -> [PaletteAction] {
        let running = path.map { terminals.isServiceRunning(service, in: $0) } ?? false
        let name = service.rawValue
        return [
            PaletteAction(title: "\(name): start", unavailable: noWorktree ?? (running ? "already running" : nil)) {
                guard let path else { return }
                terminals.startService(service, command: command(path), in: path)
                showTerminal()
            },
            PaletteAction(title: "\(name): restart", unavailable: noWorktree ?? (running ? nil : "not running")) {
                guard let path else { return }
                Task { await terminals.restartService(service, command: command(path), in: path) }
                showTerminal()
            },
            PaletteAction(title: "\(name): stop", unavailable: noWorktree ?? (running ? nil : "not running")) {
                guard let path else { return }
                Task { await terminals.stopService(service, in: path) }
            },
        ]
    }

    func database(_ action: DatabaseAction, title: String, confirm: (String, String)?) -> PaletteAction {
        PaletteAction(title: title, unavailable: noWorktree ?? busy) {
            guard let worktree else { return }
            if let (message, detail) = confirm, !confirmAction(message, detail) { return }
            Task { await store.database(action, worktree: worktree) }
        }
    }

    let branch = worktree?.branch ?? ""
    return service(.serve) { _ in ServiceCommand.serve }
        + service(.queue) { ServiceCommand.queue(worktreePath: $0) }
        + [
            database(.create, title: "db: create from main", confirm: nil),
            database(.refresh, title: "db: refresh from main",
                     confirm: ("Refresh the database of \(branch)?",
                               "It's replaced with a fresh copy of the main project's database.")),
            database(.drop, title: "db: drop",
                     confirm: ("Drop the database of \(branch)?", "Its data is lost.")),
            PaletteAction(title: "db: migrate:fresh --seed", unavailable: noWorktree) {
                guard let path,
                      confirmAction("Rebuild the database of \(branch) from migrations?", "All its data is lost."),
                      let tab = terminals.openTab(in: path) else { return }
                tab.send("php artisan migrate:fresh --seed\n")
                showTerminal()
            },
            PaletteAction(title: "open: VS Code", unavailable: noWorktree) { if let path { Openers.vscode(path) } },
            PaletteAction(title: "open: Warp", unavailable: noWorktree) { if let path { Openers.warp(path) } },
            PaletteAction(title: "open: Finder", unavailable: noWorktree) { if let path { Openers.finder(path) } },
            PaletteAction(title: "open: Herd URL", unavailable: noWorktree ?? (worktree?.herdUrl == nil ? "no Herd site" : nil)) {
                if let url = worktree?.herdUrl { Openers.browser(url) }
            },
            PaletteAction(title: "open: serve URL", unavailable: noWorktree ?? (worktree?.serveUrl == nil ? "no serve port" : nil)) {
                if let url = worktree?.serveUrl { Openers.browser(url) }
            },
            PaletteAction(title: "worktree: new", unavailable: store.selectedProject == nil ? "no project selected" : busy) {
                store.beginCreate()
            },
            PaletteAction(title: "worktree: delete", unavailable: noWorktree ?? busy) { store.beginDelete() },
            PaletteAction(title: "worktree: clear all in project",
                          unavailable: (store.selectedProject?.worktrees.isEmpty ?? true) ? "no worktrees" : busy) {
                store.beginClear()
            },
            PaletteAction(title: "refresh") { Task { await store.refresh() } },
        ]
}

@MainActor
private func confirmAction(_ message: String, _ detail: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}

/// The ⌘⇧P overlay. Keys (↑ ↓ ⏎ esc) are handled by PanelView's key monitor.
struct CommandPalette: View {
    @EnvironmentObject private var store: WorktreeStore
    let actions: [PaletteAction]
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { store.palette = nil }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("❯").foregroundStyle(Theme.green)
                    TextField("", text: Binding(get: { store.palette ?? "" }, set: { store.palette = $0 }),
                              prompt: Text("run an action…").foregroundStyle(Theme.muted))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.bright)
                        .tint(Theme.green)
                        .focused($fieldFocused)
                }
                .padding(10)
                Hairline()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                                row(action, selected: index == store.paletteSelection)
                                    .id(index)
                                    .onTapGesture {
                                        store.paletteSelection = index
                                        guard action.unavailable == nil else { return }
                                        store.palette = nil
                                        action.run()
                                    }
                            }
                            if actions.isEmpty {
                                Text("no matching action").foregroundStyle(Theme.muted).padding(10)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: store.paletteSelection) { _, index in proxy.scrollTo(index) }
                }
            }
            .frame(width: 480)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bar))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            .padding(.top, 60)
        }
        .onAppear { fieldFocused = true }
    }

    private func row(_ action: PaletteAction, selected: Bool) -> some View {
        HStack {
            Text(action.title).foregroundStyle(action.unavailable == nil ? Theme.bright : Theme.muted)
            Spacer()
            if let reason = action.unavailable {
                Text(reason).foregroundStyle(Theme.muted).font(Theme.mono(11))
            } else if selected {
                KeyHint(key: "⏎", label: "run", tint: Theme.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? Theme.selection : Color.clear)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 3: PanelView wiring**

In `app/Sources/SproutUI/PanelView.swift`:

1. Below `@State private var keyMonitor = KeyMonitor()` add:

```swift
    @State private var paletteFromTerminal = false
```

2. After `.overlay { if store.showingKeys { KeyCheatSheet() } }` add:

```swift
        .overlay { if store.palette != nil { CommandPalette(actions: paletteActions) } }
```

3. In `terminalShortcuts`, after the `⌘R` button add:

```swift
            Button("", action: { openPalette("") }).keyboardShortcut("P", modifiers: [.command, .shift])
```

4. Add these members (e.g. after `focusList()`):

```swift
    private var paletteActions: [PaletteAction] {
        let all = paletteCatalog(store: store, terminals: terminals) { terminalCollapsed = false }
        return PaletteMatcher.order(all, query: store.palette ?? "", title: { $0.title })
    }

    private func openPalette(_ query: String) {
        guard store.palette == nil else { return }
        paletteFromTerminal = terminals.terminalHasFocus
        store.palette = query
    }

    /// Closes the palette and puts the keyboard back where it was.
    private func closePalette() {
        store.palette = nil
        if paletteFromTerminal, let path = terminalPath {
            focusTerminal(in: path)
        } else {
            focusList()
        }
    }

    /// ↑ ↓ ⏎ esc while the palette is open; other keys go to its search field.
    private func handlePaletteKey(_ event: NSEvent) -> Bool {
        let actions = paletteActions
        switch event.keyCode {
        case 53:  // esc
            closePalette()
        case 125:  // ↓
            store.paletteSelection = min(store.paletteSelection + 1, max(actions.count - 1, 0))
        case 126:  // ↑
            store.paletteSelection = max(store.paletteSelection - 1, 0)
        case 36, 76:  // ⏎
            guard actions.indices.contains(store.paletteSelection) else { return true }
            let action = actions[store.paletteSelection]
            guard action.unavailable == nil else { return true }
            closePalette()
            action.run()
        default:
            return false
        }
        return true
    }
```

5. At the very start of `handleListKey`, right after the `guard let window …` line, add:

```swift
        if store.palette != nil { return handlePaletteKey(event) }
```

6. In `handleListKey`'s character switch, after the `case "l":` case add:

```swift
        case "s":
            openPalette("serve ")
        case "q":
            openPalette("queue ")
        case "d":
            openPalette("db ")
```

- [ ] **Step 4: Service labels, status rows, cheat sheet, footer**

`TerminalPane.swift` — in the `TerminalTabButton(` call, replace `title: tab.title,` with:

```swift
                            title: terminals.service(of: tab.id, in: path)?.rawValue ?? tab.title,
```

`WorktreeListView.swift` — in `WorktreeDetail`, add `@EnvironmentObject private var terminals: TerminalSessions` and `import SproutTerminal`; replace the `if !worktree.isServing { Text("not running · php artisan serve") … }` block inside `KV("serve")` with:

```swift
                        serviceStatus(.serve)
```

and add a queue row after the `KV("serve") { … }` block:

```swift
            KV("queue") { serviceStatus(.queue) }
```

plus this member of `WorktreeDetail`:

```swift
    private func serviceStatus(_ service: Service) -> some View {
        let running = terminals.isServiceRunning(service, in: worktree.path)
        return HStack(spacing: 4) {
            Text(running ? "● running" : "○ stopped").foregroundStyle(running ? Theme.green : Theme.muted)
            if !running { Text("· \(service == .serve ? "s" : "q") to start").foregroundStyle(Theme.muted) }
        }
    }
```

(When `serveUrl` is nil the `KV("serve")` row still shows `serviceStatus(.serve)` instead of `—`.)

`KeyCheatSheet.swift` — in the WORKTREES section after `("l", …)` add `("⌘⇧P", "command palette")`, `("s  q  d", "serve / queue / database actions")`.

`Chrome.swift` — in `FooterBar.hints` `.list` case, replace `Hint(key: "⌘T", label: "tab")` with `Hint(key: "⌘⇧P", label: "actions")`. Add `case .activity` untouched. In `shortHints`, add `Hint(key: "⌘⇧P", label: "actions")` before the `?` hint.

- [ ] **Step 5: Snapshots + docs**

`app/Sources/SproutSnapshots/main.swift` — append:

```swift
let withPalette = await makeStore(ok)
withPalette.palette = "serve "
render("palette", withPalette)
```

`docs/README.md` — in the Keys table add rows `| ``⌘⇧P`` | command palette (every action, searchable) |` and `| ``s`` / ``q`` / ``d`` | serve / queue / database actions |`; add a "### Serve, queue and database" section after "### Background operations":

```markdown
### Serve, queue and database

`⌘⇧P` (from anywhere, including the terminal) opens the command palette for the
selected worktree; `s`, `q` and `d` open it filtered to serve, queue or database.

- **serve / queue: start · restart · stop** — run `php artisan serve` and the
  queue (`php artisan horizon` when the project uses Horizon, else
  `queue:work`) in their own `serve` / `queue` terminal tabs, so you see the
  output. Restart sends ⌃C and reruns; stop sends ⌃C and closes the tab.
- **db: create from main · refresh from main · drop** — run
  `sprout-parallel db create|refresh|drop`, which only ever touches the
  worktree's own database (`<main>_<folder>`). Refresh and drop ask first.
- **db: migrate:fresh --seed** — rebuilds the schema in a terminal tab.
```

In the Development block add `bash ../tests/db_test.sh     # db create/refresh/drop`.

- [ ] **Step 6: Verify everything**

Run:
```bash
cd app && swift build 2>&1 | grep -E 'error:|warning:.*/Sources/'
swift run SproutCoreChecks 2>&1 | tail -1; swift run SproutTerminalChecks 2>&1 | tail -1
for i in 1 2 3; do ./.build/debug/SproutKeyChecks 2>&1 | grep -E '^FAIL|checks'; done
swift run SproutSnapshots 2>&1 | grep -c wrote
cd .. && for t in db db_setup status clear serve; do bash tests/${t}_test.sh < /dev/null | tail -1; done
```
Expected: no errors/warnings; `all checks passed` for core, terminal, and at least 2 of 3 key runs (a single run failing in a different place each time is the known window-focus flake; report it); 17 snapshots; `all tests passed` ×5. Look at `app/build/snapshots/palette.png` (downscale with `sips -Z 1000`): the palette shows `serve: start` first, `serve: restart`/`stop` dimmed with "not running".

- [ ] **Step 7: Commit**

```bash
git add app/Sources docs/README.md
git commit -m "Add the command palette with serve, queue and database actions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Live checklist (controller runs it with the user)**

1. `⌘⇧P` from the list and from the terminal; type `ser st` ⏎ → a `serve` tab runs `php artisan serve`; details show `serve ● running`.
2. `⌘⇧P` → `serve: restart` → it restarts in the same tab; `serve: stop` → tab closes, `○ stopped`.
3. `q` → `queue: start` → Horizon or `queue:work` in a `queue` tab.
4. `d` → `db: create from main` on a worktree whose database failed → header shows the operation; details show the database.
5. `db: refresh from main` / `db: drop` ask first; cancelling does nothing.
6. Typing in the palette never triggers list keys or reaches the shell.
