# Sprout Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A terminal-styled macOS menu bar app ("Sprout") that lists, creates, deletes, and opens sprout-parallel worktrees across all projects.

**Architecture:** The bash script stays the single source of truth: a new `status --json` command reports state, and the existing `create`/`delete` commands mutate it. A SwiftPM package in `app/` wraps it: `SproutCore` (shell runner, CLI wrapper, models, observable store — all tested by a `SproutCoreChecks` executable), `SproutUI` (SwiftUI views), a thin `Sprout` app target, and `SproutSnapshots` which renders views to PNG for visual verification.

**Tech Stack:** Bash 3.2, git, python3 (tests only); Swift 5.9 tools / Swift 6.2 toolchain from Command Line Tools, SwiftUI `MenuBarExtra`, AppKit, ServiceManagement. No third-party dependencies. No Xcode.

**Spec:** `docs/superpowers/specs/2026-09-29-sprout-menubar-app-design.md`

## Global Constraints

- Bash must run on macOS bash 3.2 (`/bin/bash`): no associative arrays, no `mapfile`, no `${var,,}`; empty arrays under `set -u` break, so accumulate strings instead.
- The script keeps `set -euo pipefail`; every pipeline whose first command may fail must be guarded (`{ cmd || true; } | …`).
- Swift package: `// swift-tools-version:5.9`, `platforms: [.macOS(.v14)]`, no external packages.
- `XCTest` and `Testing` are unavailable (no Xcode). Swift tests live in the `SproutCoreChecks` executable; run with `cd app && swift run SproutCoreChecks`; it exits non-zero on any failure.
- All commands from the app run through `/bin/zsh -lc "<command>"`.
- Bundle id `agency.manza.sprout`, `LSUIElement=true`, `LSMinimumSystemVersion=14.0`, ad-hoc signed, installed to `~/Applications/Sprout.app`.
- Palette (exact): bg `#0B0F14`, bar `#0E141B`, sidebar `#0A0E12`, selection `#12202B`, selection edge `#1D3A4A`, border `#1F2A36`, log bg `#070A0D`, green `#39FFA0`, amber `#FFCC66`, red `#FF6B6B`, cyan `#56D4FF`, violet `#C792EA`, muted `#6B7A8C`, text `#C9D1D9`, bright `#E6EDF3`.
- Font: JetBrains Mono if installed, else `.system(design: .monospaced)`. Always dark.
- The CLI's existing behaviour for `create`, `delete`, `list`, `help` must not change except where a task says so.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Login shell prints text to stdout before the JSON** (a `.zshrc` banner) → status must still load: take the last stdout line starting with `{`. Pinned in Task 4 (`status ignores login-shell banner`).
2. **Branch names with spaces, quotes, a leading `-`, or `..`** → Create is disabled with a message; commands are shell-quoted. Pinned in Task 4 (`validateBranch` + quoting checks).
3. **Commit subjects with `"`, `\`, tabs, and emoji** → JSON stays valid and round-trips exactly. Pinned in Task 1 (`subject round-trips`).
4. **A worktree whose recorded base branch no longer exists** → `ahead`/`behind` are `null`, status still exits 0. Pinned in Task 1 (`missing base gives null sync`).
5. **Detached-HEAD worktree** → listed with branch `HEAD` and deletable (delete passes the folder name, not the branch). Pinned in Task 1 (`detached HEAD listed`) and Task 5 (`delete uses folder name`).

---

## File Map

| File | Responsibility |
|---|---|
| `sprout-parallel` (modify) | + JSON helpers, `cmd_status`, record `sproutBase` in `cmd_create`, help text, dispatcher |
| `tests/status_test.sh` (create) | Bash tests for `status --json` and `sproutBase` |
| `app/Package.swift` | Package manifest (grows per task) |
| `app/Sources/SproutCore/Models.swift` | `Status`, `Project`, `Worktree`, `LastCommit` |
| `app/Sources/SproutCore/Shell.swift` | `ShellResult`, `Shell`, `shellQuote`, `LoginShell`, `LineCollector` |
| `app/Sources/SproutCore/SproutCLI.swift` | `CLIError`, `SproutCLI` (commands, validation, status/run) |
| `app/Sources/SproutCore/WorktreeStore.swift` | Observable app state and operations |
| `app/Sources/SproutCoreChecks/*.swift` | Check harness, fixtures, fakes, checks |
| `app/Sources/SproutUI/Theme.swift` | Colours, font |
| `app/Sources/SproutUI/Openers.swift` | VS Code / Warp / Finder |
| `app/Sources/SproutUI/Chrome.swift` | Hairline, header, sidebar, footer, key hints, banners, chips |
| `app/Sources/SproutUI/WorktreeListView.swift` | Table rows + detail box |
| `app/Sources/SproutUI/PanelView.swift` | Root view, mode switch, keyboard |
| `app/Sources/SproutUI/CreateForm.swift` | Create form |
| `app/Sources/SproutUI/DeleteConfirm.swift` | Delete confirmation |
| `app/Sources/SproutUI/LogView.swift` | Streaming command log |
| `app/Sources/SproutUI/LoginItemToggle.swift` | Launch-at-login toggle |
| `app/Sources/Sprout/SproutApp.swift` | `@main` MenuBarExtra |
| `app/Sources/SproutSnapshots/main.swift` | Renders views to `app/build/snapshots/*.png` |
| `app/Info.plist`, `app/build.sh` | Bundle + build/install |
| `docs/README.md` (modify) | App section |

---

### Task 1: `status --json` in the script

**Files:**
- Modify: `sprout-parallel` (add a "Status (JSON)" section before `# ─── Commands`, add `cmd_status`, help, dispatcher)
- Create: `tests/status_test.sh`

**Interfaces:**
- Consumes: existing `parse_env_value KEY FILE` (strips quotes, `null` → empty), `die`, `$SPROUT_PROJECTS_ROOT`, `$SCRIPT_NAME`.
- Produces: `sprout-parallel status --json` printing one line `{"projects":[…]}` with the schema in spec §1.1 (`lastCommit` has `hash`, `subject`, `when`). Base is read from `git config branch.<branch>.sproutBase`, default `main`. Task 2 writes that config.

- [ ] **Step 1: Write the failing test**

Create `tests/status_test.sh`:

```bash
#!/usr/bin/env bash
# Tests for `sprout-parallel status --json`. Run: bash tests/status_test.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SP="$REPO/sprout-parallel"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export SPROUT_PROJECTS_ROOT="$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export PYTHONIOENCODING=utf-8

FAILS=0
OUT="$ROOT/out.json"

# q: print a Python expression evaluated against the status JSON.
#    d = whole document, P(name) = project, W(folder) = worktree
q() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
P = lambda n: next(p for p in d['projects'] if p['name'] == n)
W = lambda f: next(w for p in d['projects'] for w in p['worktrees'] if w['folder'] == f)
print($1)" "$OUT"
}

assert_eq() {
  if [[ "$1" == "$2" ]]; then
    echo "ok   - $3"
  else
    echo "FAIL - $3: expected [$2], got [$1]"
    FAILS=$((FAILS + 1))
  fi
}

# ─── Fixture ──────────────────────────────────────────────────────────────────

SUBJECT=$'Say "hi" \\ tab\there 🌱'

mkdir "$ROOT/alpha"
git -C "$ROOT/alpha" init -q -b main
git -C "$ROOT/alpha" commit -q --allow-empty -m init
git -C "$ROOT/alpha" branch develop

"$SP" create feature/one --project alpha --no-setup > /dev/null
WT1="$ROOT/alpha-worktrees/feature-one"
git -C "$WT1" commit -q --allow-empty -m "$SUBJECT"
printf 'DB_DATABASE=alpha_one\nREDIS_DB=3\nREDIS_PREFIX="alpha_feature_one_"\n' > "$WT1/.env"
echo x > "$WT1/dirty.txt"

git -C "$ROOT/alpha" commit -q --allow-empty -m "main moves on"

"$SP" create feature/two --project alpha --no-setup > /dev/null
git -C "$ROOT/alpha" config branch.feature/two.sproutBase gone

git -C "$ROOT/alpha" worktree add -q --detach "$ROOT/alpha-worktrees/detached" main

mkdir "$ROOT/aaa-empty"
git -C "$ROOT/aaa-empty" init -q -b main
git -C "$ROOT/aaa-empty" commit -q --allow-empty -m init

mkdir "$ROOT/notes"   # not a git repo: must be ignored

# ─── status --json ────────────────────────────────────────────────────────────

status_rc=0
"$SP" status --json > "$OUT" || status_rc=$?
assert_eq "$status_rc" "0" "status exits 0"
assert_eq "$(q "'parsed'")" "parsed" "output is valid JSON"
assert_eq "$(q "[p['name'] for p in d['projects']]")" "['alpha', 'aaa-empty']" \
  "projects with worktrees first; -worktrees dirs and non-git dirs skipped"
assert_eq "$(q "P('alpha')['branches']")" "['develop', 'feature/one', 'feature/two', 'main']" "branches sorted"
assert_eq "$(q "P('aaa-empty')['worktrees']")" "[]" "project without worktrees has empty list"
assert_eq "$(q "P('alpha')['path']")" "$ROOT/alpha" "project path"

assert_eq "$(q "W('feature-one')['branch']")" "feature/one" "branch"
assert_eq "$(q "W('feature-one')['path']")" "$WT1" "worktree path"
assert_eq "$(q "W('feature-one')['base']")" "main" "base defaults to main"
assert_eq "$(q "W('feature-one')['changes']")" "2" "changes counts untracked files"
assert_eq "$(q "W('feature-one')['ahead']")" "1" "ahead of base"
assert_eq "$(q "W('feature-one')['behind']")" "1" "behind base"
assert_eq "$(q "W('feature-one')['lastCommit']['subject']")" "$SUBJECT" "subject round-trips"
assert_eq "$(q "len(W('feature-one')['lastCommit']['hash']) >= 7")" "True" "short hash"
assert_eq "$(q "W('feature-one')['lastCommit']['when'] != ''")" "True" "relative date"
assert_eq "$(q "W('feature-one')['mysqlDb']")" "alpha_one" "mysqlDb from .env"
assert_eq "$(q "W('feature-one')['redisDb']")" "3" "redisDb is a number"
assert_eq "$(q "type(W('feature-one')['redisDb']).__name__")" "int" "redisDb type"
assert_eq "$(q "W('feature-one')['redisPrefix']")" "alpha_feature_one_" "redisPrefix unquoted"

assert_eq "$(q "W('feature-two')['base']")" "gone" "base read from git config"
assert_eq "$(q "(W('feature-two')['ahead'], W('feature-two')['behind'])")" "(None, None)" "missing base gives null sync"
assert_eq "$(q "(W('feature-two')['mysqlDb'], W('feature-two')['redisDb'], W('feature-two')['redisPrefix'])")" \
  "(None, None, None)" "no .env gives nulls"
assert_eq "$(q "W('feature-two')['changes']")" "0" "clean worktree"

assert_eq "$(q "W('detached')['branch']")" "HEAD" "detached HEAD listed"

no_json_rc=0
"$SP" status > /dev/null 2>&1 || no_json_rc=$?
assert_eq "$no_json_rc" "1" "status without --json exits 1"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$FAILS test(s) failed"
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/status_test.sh`
Expected: `FAIL - status exits 0: expected [0], got [1]` (unknown command), followed by more failures and `exit 1`.

- [ ] **Step 3: Add JSON helpers and `cmd_status`**

In `sprout-parallel`, insert this block immediately before the line `# ─── Commands ─────…`:

```bash
# ─── Status (JSON) ────────────────────────────────────────────────────────────

# json_escape: escape a string for use inside a JSON string literal.
# Escapes \ " newline tab CR; strips other ASCII control characters.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\014\016-\037'
}

json_str() {
  printf '"%s"' "$(json_escape "$1")"
}

json_str_or_null() {
  if [[ -n "$1" ]]; then json_str "$1"; else printf 'null'; fi
}

json_int_or_null() {
  if [[ "$1" =~ ^[0-9]+$ ]]; then printf '%s' "$1"; else printf 'null'; fi
}

# worktree_json: print one worktree as a JSON object
#   $1: main project path
#   $2: worktree path (trailing slash allowed)
worktree_json() {
  local proj_path="$1"
  local wt="${2%/}"
  local env_file="$wt/.env"

  local branch base changes
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
  base="$(git -C "$proj_path" config --get "branch.${branch}.sproutBase" 2>/dev/null || true)"
  base="${base:-main}"
  changes="$( { git -C "$wt" status --porcelain 2>/dev/null || true; } | wc -l | tr -d ' ')"

  local base_ref="" ahead="" behind="" counts=""
  if git -C "$wt" rev-parse --verify -q "refs/heads/$base" > /dev/null 2>&1; then
    base_ref="refs/heads/$base"
  elif git -C "$wt" rev-parse --verify -q "refs/remotes/origin/$base" > /dev/null 2>&1; then
    base_ref="refs/remotes/origin/$base"
  fi
  if [[ -n "$base_ref" ]]; then
    counts="$(git -C "$wt" rev-list --left-right --count "${base_ref}...HEAD" 2>/dev/null || true)"
    if [[ -n "$counts" ]]; then
      behind="$(echo "$counts" | awk '{print $1}')"
      ahead="$(echo "$counts" | awk '{print $2}')"
    fi
  fi

  local last="null" hash subject when
  hash="$(git -C "$wt" log -1 --format=%h 2>/dev/null || true)"
  if [[ -n "$hash" ]]; then
    subject="$(git -C "$wt" log -1 --format=%s)"
    when="$(git -C "$wt" log -1 --format=%cr)"
    last="{\"hash\":$(json_str "$hash"),\"subject\":$(json_str "$subject"),\"when\":$(json_str "$when")}"
  fi

  local mysql_db="" redis_db="" redis_prefix=""
  if [[ -f "$env_file" ]]; then
    mysql_db="$(parse_env_value DB_DATABASE "$env_file")"
    redis_db="$(parse_env_value REDIS_DB "$env_file")"
    redis_prefix="$(parse_env_value REDIS_PREFIX "$env_file")"
  fi

  printf '{"branch":%s,"folder":%s,"path":%s,"base":%s,"changes":%s,"ahead":%s,"behind":%s,"lastCommit":%s,"mysqlDb":%s,"redisDb":%s,"redisPrefix":%s}' \
    "$(json_str "$branch")" \
    "$(json_str "$(basename "$wt")")" \
    "$(json_str "$wt")" \
    "$(json_str "$base")" \
    "${changes:-0}" \
    "$(json_int_or_null "$ahead")" \
    "$(json_int_or_null "$behind")" \
    "$last" \
    "$(json_str_or_null "$mysql_db")" \
    "$(json_int_or_null "$redis_db")" \
    "$(json_str_or_null "$redis_prefix")"
}

# project_json: print one project (with branches and worktrees) as JSON
#   $1: project name  $2: project path
project_json() {
  local name="$1"
  local path="$2"

  local branches="" b
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    branches+="${branches:+,}$(json_str "$b")"
  done < <(git -C "$path" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | LC_ALL=C sort)

  local worktrees="" entry
  for entry in "$SPROUT_PROJECTS_ROOT/${name}-worktrees"/*/; do
    [[ -d "${entry}.git" || -f "${entry}.git" ]] || continue
    worktrees+="${worktrees:+,}$(worktree_json "$path" "$entry")"
  done

  printf '{"name":%s,"path":%s,"branches":[%s],"worktrees":[%s]}' \
    "$(json_str "$name")" "$(json_str "$path")" "$branches" "$worktrees"
}
```

Then add this command after `cmd_list() { … }` (before `cmd_help`):

```bash
cmd_status() {
  local json=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      *)
        die "Unknown option: $1. Run '$SCRIPT_NAME help status' for usage."
        ;;
    esac
  done

  [[ "$json" == true ]] \
    || die "status currently requires --json. Run '$SCRIPT_NAME help status' for usage."
  [[ -d "$SPROUT_PROJECTS_ROOT" ]] \
    || die "Projects root '$SPROUT_PROJECTS_ROOT' does not exist."

  local with="" without="" dir name project
  for dir in "$SPROUT_PROJECTS_ROOT"/*/; do
    dir="${dir%/}"
    name="$(basename "$dir")"
    [[ "$name" == *-worktrees ]] && continue
    [[ -d "$dir/.git" || -f "$dir/.git" ]] || continue

    project="$(project_json "$name" "$dir")"
    if [[ "$project" == *'"worktrees":[]}' ]]; then
      without+="${without:+,}$project"
    else
      with+="${with:+,}$project"
    fi
  done

  local all="$with"
  if [[ -n "$without" ]]; then
    all+="${all:+,}$without"
  fi
  printf '{"projects":[%s]}\n' "$all"
}
```

In `main()`, add a dispatcher line after `list)`:

```bash
    status)    cmd_status "$@" ;;
```

- [ ] **Step 4: Add help text**

In `cmd_help`, add a new case before `""|help)`:

```bash
    status)
      cat <<EOF
COMMAND: $SCRIPT_NAME status --json

  Prints every project under \$SPROUT_PROJECTS_ROOT and its worktrees as one
  line of JSON. Used by the Sprout menu bar app.

  Per worktree: branch, folder, path, base, changes, ahead, behind,
  lastCommit {hash, subject, when}, mysqlDb, redisDb, redisPrefix.
  Unknown values are null. Projects with worktrees are listed first.

EXIT CODES:
  0  Success
  1  --json missing, or projects root not found
EOF
      ;;
```

In the main help's `COMMANDS:` list add, after the `list` line:

```
  status --json     Print all projects and worktrees as JSON
```

In the main help's "For command-specific help:" list add `  $SCRIPT_NAME help status`, and change the unknown-topic error to:

```bash
      die "Unknown help topic: '$topic'. Available: create, delete, list, status"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash -n sprout-parallel && bash tests/status_test.sh`
Expected: every line `ok   - …`, then `all tests passed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add sprout-parallel tests/status_test.sh
git commit -m "Add 'status --json' command for the Sprout app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `create` records the base branch

**Files:**
- Modify: `sprout-parallel` (`cmd_create`, `help create`)
- Modify: `tests/status_test.sh`

**Interfaces:**
- Consumes: `cmd_status` from Task 1 (reads `branch.<name>.sproutBase`).
- Produces: after `create <branch> --from <base>`, `git config branch.<branch>.sproutBase` equals `<base>`.

- [ ] **Step 1: Write the failing test**

In `tests/status_test.sh`, insert immediately before the line `# ─── Summary ─────…`:

```bash
# ─── create records sproutBase ────────────────────────────────────────────────

"$SP" create feature/dev --project alpha --from develop --no-setup > /dev/null
assert_eq "$(git -C "$ROOT/alpha" config --get branch.feature/dev.sproutBase || true)" "develop" \
  "create stores base in git config"

"$SP" status --json > "$OUT"
assert_eq "$(q "W('feature-dev')['base']")" "develop" "status reports recorded base"
assert_eq "$(q "(W('feature-dev')['ahead'], W('feature-dev')['behind'])")" "(0, 0)" "sync against recorded base"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/status_test.sh`
Expected: `FAIL - create stores base in git config: expected [develop], got []`, and exit 1.

- [ ] **Step 3: Implement**

In `cmd_create`, directly after the `git -C "$proj_path" worktree add … || die2 …` statement, add:

```bash
  # Remember the base so `status` can report ahead/behind against it
  git -C "$proj_path" config "branch.${branch}.sproutBase" "$base_branch"
```

In `help create`, under `WORKTREE PATH:` add a section before it:

```
BASE TRACKING:
  The base branch is stored in git config (branch.<name>.sproutBase) so
  'status --json' can report commits ahead/behind it.

```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/status_test.sh`
Expected: all `ok`, `all tests passed`.

- [ ] **Step 5: Commit**

```bash
git add sprout-parallel tests/status_test.sh
git commit -m "Record base branch on create for ahead/behind reporting

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Swift package, models, and check harness

**Files:**
- Create: `app/Package.swift`
- Create: `app/Sources/SproutCore/Models.swift`
- Create: `app/Sources/SproutCoreChecks/Check.swift`
- Create: `app/Sources/SproutCoreChecks/Fixtures.swift`
- Create: `app/Sources/SproutCoreChecks/ModelChecks.swift`
- Create: `app/Sources/SproutCoreChecks/main.swift`

**Interfaces:**
- Produces (module `SproutCore`, all `public`):
  - `struct Status: Codable, Equatable { let projects: [Project]; static func decode(_ data: Data) throws -> Status }`
  - `struct Project: Codable, Equatable, Hashable, Identifiable { let name: String; let path: String; let branches: [String]; let worktrees: [Worktree]; var id: String /* name */ }`
  - `struct Worktree: Codable, Equatable, Hashable, Identifiable { let branch, folder, path, base: String; let changes: Int; let ahead, behind: Int?; let lastCommit: LastCommit?; let mysqlDb: String?; let redisDb: Int?; let redisPrefix: String?; var id: String /* path */; var isDirty: Bool }`
  - `struct LastCommit: Codable, Equatable, Hashable { let hash, subject, when: String }`
- Produces (checks target, internal): `var failures: Int`, `check(_:_:)`, `checkEqual(_:_:_:)`, `let statusFixture: String`, `func statusJSON(_ branches: [String]) -> String`.

- [ ] **Step 1: Create the package and harness with a failing check**

`app/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sprout",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SproutCore"),
        .executableTarget(name: "SproutCoreChecks", dependencies: ["SproutCore"]),
    ]
)
```

`app/Sources/SproutCore/Models.swift` (empty for now so the target has a source file):

```swift
import Foundation
```

`app/Sources/SproutCoreChecks/Check.swift`:

```swift
import Foundation

var failures = 0

func check(_ condition: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    if condition {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name) (\(file):\(line))")
    }
}

func checkEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ name: String,
    file: StaticString = #fileID, line: UInt = #line
) {
    if actual == expected {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name): expected \(expected), got \(actual) (\(file):\(line))")
    }
}
```

`app/Sources/SproutCoreChecks/Fixtures.swift`:

```swift
import Foundation

/// Hand-written `status --json` output covering every field shape.
let statusFixture = #"""
{"projects":[
 {"name":"scooda","path":"/Users/me/projects/scooda","branches":["develop","main"],"worktrees":[
  {"branch":"feature/payments-v2","folder":"feature-payments-v2","path":"/Users/me/projects/scooda-worktrees/feature-payments-v2","base":"main","changes":3,"ahead":3,"behind":1,"lastCommit":{"hash":"a1f9c2e","subject":"Say \"hi\" \\ ok","when":"2 hours ago"},"mysqlDb":"scooda_feature_payments_v2","redisDb":3,"redisPrefix":"scooda_feature_payments_v2_"},
  {"branch":"HEAD","folder":"detached","path":"/Users/me/projects/scooda-worktrees/detached","base":"main","changes":0,"ahead":null,"behind":null,"lastCommit":null,"mysqlDb":null,"redisDb":null,"redisPrefix":null}
 ]},
 {"name":"prayercal","path":"/Users/me/projects/prayercal","branches":["main"],"worktrees":[]}
]}
"""#

/// Single-line status JSON with project "scooda" holding one clean worktree per
/// branch, plus an empty project "prayercal".
func statusJSON(_ branches: [String]) -> String {
    let worktrees = branches.map { branch -> String in
        let folder = branch.replacingOccurrences(of: "/", with: "-")
        return #"{"branch":"\#(branch)","folder":"\#(folder)","path":"/p/scooda-worktrees/\#(folder)","base":"main","changes":0,"ahead":0,"behind":0,"lastCommit":null,"mysqlDb":null,"redisDb":null,"redisPrefix":null}"#
    }.joined(separator: ",")
    return #"{"projects":[{"name":"scooda","path":"/p/scooda","branches":["main"],"worktrees":[\#(worktrees)]},{"name":"prayercal","path":"/p/prayercal","branches":["main"],"worktrees":[]}]}"#
}
```

`app/Sources/SproutCoreChecks/ModelChecks.swift`:

```swift
import Foundation
import SproutCore

func modelChecks() {
    guard let status = try? Status.decode(Data(statusFixture.utf8)) else {
        check(false, "fixture decodes")
        return
    }
    checkEqual(status.projects.map(\.name), ["scooda", "prayercal"], "decodes projects in order")

    let wt = status.projects[0].worktrees[0]
    checkEqual(wt.branch, "feature/payments-v2", "decodes branch")
    checkEqual(wt.id, wt.path, "worktree id is its path")
    checkEqual(wt.ahead, 3, "decodes ahead")
    checkEqual(wt.behind, 1, "decodes behind")
    checkEqual(wt.redisDb, 3, "decodes redisDb as Int")
    checkEqual(wt.lastCommit?.subject, "Say \"hi\" \\ ok", "decodes escaped subject")
    checkEqual(wt.lastCommit?.hash, "a1f9c2e", "decodes hash")
    check(wt.isDirty, "changes > 0 is dirty")

    let bare = status.projects[0].worktrees[1]
    check(bare.ahead == nil && bare.behind == nil, "null sync decodes as nil")
    check(bare.lastCommit == nil && bare.mysqlDb == nil, "null commit and db decode as nil")
    check(bare.redisDb == nil && bare.redisPrefix == nil, "null redis decodes as nil")
    check(!bare.isDirty, "changes == 0 is clean")

    checkEqual(status.projects[1].worktrees.count, 0, "project without worktrees")
    checkEqual(status.projects[1].id, "prayercal", "project id is its name")
    check((try? Status.decode(Data("not json".utf8))) == nil, "invalid JSON throws")
    check((try? Status.decode(Data(statusJSON(["feature/a"]).utf8))) != nil, "statusJSON helper decodes")
}
```

`app/Sources/SproutCoreChecks/main.swift`:

```swift
import Foundation

modelChecks()

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd app && swift run SproutCoreChecks`
Expected: compile error `cannot find 'Status' in scope`.

- [ ] **Step 3: Implement the models**

Replace `app/Sources/SproutCore/Models.swift`:

```swift
import Foundation

/// Output of `sprout-parallel status --json`.
public struct Status: Codable, Equatable {
    public let projects: [Project]

    public static func decode(_ data: Data) throws -> Status {
        try JSONDecoder().decode(Status.self, from: data)
    }
}

public struct Project: Codable, Equatable, Hashable, Identifiable {
    public let name: String
    public let path: String
    public let branches: [String]
    public let worktrees: [Worktree]

    public var id: String { name }
}

public struct Worktree: Codable, Equatable, Hashable, Identifiable {
    public let branch: String
    public let folder: String
    public let path: String
    public let base: String
    public let changes: Int
    public let ahead: Int?
    public let behind: Int?
    public let lastCommit: LastCommit?
    public let mysqlDb: String?
    public let redisDb: Int?
    public let redisPrefix: String?

    public var id: String { path }
    public var isDirty: Bool { changes > 0 }
}

public struct LastCommit: Codable, Equatable, Hashable {
    public let hash: String
    public let subject: String
    public let when: String
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd app && swift run SproutCoreChecks`
Expected: all `ok`, `all checks passed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add app/Package.swift app/Sources
git commit -m "Add Sprout Swift package with status models and check harness

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Shell runner and CLI wrapper

**Files:**
- Create: `app/Sources/SproutCore/Shell.swift`
- Create: `app/Sources/SproutCore/SproutCLI.swift`
- Create: `app/Sources/SproutCoreChecks/Fakes.swift`
- Create: `app/Sources/SproutCoreChecks/ShellChecks.swift`
- Create: `app/Sources/SproutCoreChecks/CLIChecks.swift`
- Create: `app/Sources/SproutCoreChecks/LiveChecks.swift`
- Modify: `app/Sources/SproutCoreChecks/main.swift`

**Interfaces:**
- Consumes: `Status.decode` (Task 3); the script's `status --json`, `create`, `delete` (Tasks 1–2).
- Produces (public, `SproutCore`):
  - `struct ShellResult: Equatable { let exitCode: Int32; let stdout: String; let stderr: String; init(exitCode: Int32, stdout: String = "", stderr: String = "") }`
  - `protocol Shell: AnyObject { func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult }` — `onLine` receives each stdout/stderr line as it arrives, on a background thread.
  - `func shellQuote(_ s: String) -> String`
  - `final class LoginShell: Shell { init(shellPath: String = "/bin/zsh") }`
  - `enum CLIError: Error, Equatable { case notFound, failed(String), badOutput(String); var message: String }`
  - `struct SproutCLI { init(shell: Shell); static let statusCommand: String; static func createCommand(project:branch:base:runSetup:) -> String; static func deleteCommand(project:folder:force:keepData:) -> String; static func folderName(for:) -> String; static func validateBranch(_:) -> String?; func status() async throws -> Status; func run(_ command: String, onLine: @escaping (String) -> Void) async throws }`
- Produces (checks target): `final class FakeShell: Shell { init(_ respond: @escaping (String) -> ShellResult); var commands: [String]; var delayNanos: UInt64 }`, `final class LinesBox`.

- [ ] **Step 1: Write the failing checks**

`app/Sources/SproutCoreChecks/Fakes.swift`:

```swift
import Foundation
import SproutCore

/// Shell double: answers each command via `respond`, emitting its stdout and
/// stderr lines through `onLine`, and records every command it was given.
final class FakeShell: Shell {
    private let respond: (String) -> ShellResult
    private(set) var commands: [String] = []
    var delayNanos: UInt64 = 0

    init(_ respond: @escaping (String) -> ShellResult) {
        self.respond = respond
    }

    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        commands.append(command)
        if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
        let result = respond(command)
        for line in (result.stdout + "\n" + result.stderr).split(separator: "\n") {
            onLine(String(line))
        }
        return result
    }
}

/// Thread-safe line accumulator for streaming callbacks.
final class LinesBox {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock(); storage.append(line); lock.unlock()
    }

    var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
```

`app/Sources/SproutCoreChecks/ShellChecks.swift`:

```swift
import Foundation
import SproutCore

func shellChecks() async {
    checkEqual(shellQuote("feature/x-1"), "feature/x-1", "safe strings stay unquoted")
    checkEqual(shellQuote("a b"), "'a b'", "spaces get quoted")
    checkEqual(shellQuote("it's"), "'it'\\''s'", "single quotes are escaped")
    checkEqual(shellQuote(""), "''", "empty string is quoted")
    checkEqual(shellQuote("$(rm -rf ~)"), "'$(rm -rf ~)'", "command substitution is neutralised")

    let box = LinesBox()
    let result = await LoginShell().run("printf 'one\\ntwo\\n'; echo oops >&2; printf 'tail'; exit 3") {
        box.append($0)
    }
    checkEqual(result.exitCode, 3, "login shell returns exit code")
    checkEqual(result.stdout, "one\ntwo\ntail", "stdout collected, trailing partial line kept")
    checkEqual(result.stderr, "oops\n", "stderr collected separately")
    checkEqual(Set(box.lines), Set(["one", "two", "oops", "tail"]), "every line streamed")

    let missing = await LoginShell().run("definitely-not-a-command-xyz") { _ in }
    checkEqual(missing.exitCode, 127, "missing command exits 127")
}
```

`app/Sources/SproutCoreChecks/CLIChecks.swift`:

```swift
import Foundation
import SproutCore

func cliChecks() async {
    checkEqual(
        SproutCLI.createCommand(project: "scooda", branch: "feature/x", base: "main", runSetup: true),
        "sprout-parallel create feature/x --project scooda --from main",
        "create command")
    checkEqual(
        SproutCLI.createCommand(project: "scooda", branch: "feature/x", base: "develop", runSetup: false),
        "sprout-parallel create feature/x --project scooda --from develop --no-setup",
        "create command without setup")
    checkEqual(
        SproutCLI.createCommand(project: "my proj", branch: "it's", base: "main", runSetup: true),
        "sprout-parallel create 'it'\\''s' --project 'my proj' --from main",
        "create command quotes arguments")

    checkEqual(
        SproutCLI.deleteCommand(project: "scooda", folder: "feature-x", force: false, keepData: false),
        "sprout-parallel delete feature-x --project scooda", "delete command")
    checkEqual(
        SproutCLI.deleteCommand(project: "scooda", folder: "feature-x", force: true, keepData: false),
        "sprout-parallel delete feature-x --project scooda --force", "delete --force")
    checkEqual(
        SproutCLI.deleteCommand(project: "scooda", folder: "feature-x", force: false, keepData: true),
        "sprout-parallel delete feature-x --project scooda --keep-db", "delete --keep-db")
    checkEqual(
        SproutCLI.deleteCommand(project: "scooda", folder: "feature-x", force: true, keepData: true),
        "sprout-parallel delete feature-x --project scooda --force --keep-db", "delete both flags")

    checkEqual(SproutCLI.folderName(for: "feature/my-thing"), "feature-my-thing", "folder name")
    checkEqual(SproutCLI.folderName(for: "/x/"), "x", "folder name trims edge dashes")

    checkEqual(SproutCLI.validateBranch("feature/ok-1"), nil, "valid branch")
    check(SproutCLI.validateBranch("") != nil, "empty branch rejected")
    check(SproutCLI.validateBranch("-rf") != nil, "leading dash rejected")
    check(SproutCLI.validateBranch("has space") != nil, "space rejected")
    check(SproutCLI.validateBranch("a..b") != nil, "double dot rejected")
    check(SproutCLI.validateBranch("trailing/") != nil, "trailing slash rejected")
    check(SproutCLI.validateBranch("x.lock") != nil, ".lock suffix rejected")
    check(SproutCLI.validateBranch("quo\"te") != nil, "quote rejected")

    // status()
    let banner = FakeShell { _ in ShellResult(exitCode: 0, stdout: "Welcome to zsh!\n" + statusJSON(["feature/a"]) + "\n") }
    let status = try? await SproutCLI(shell: banner).status()
    checkEqual(status?.projects.first?.worktrees.first?.branch, "feature/a", "status ignores login-shell banner")
    checkEqual(banner.commands, ["sprout-parallel status --json"], "status runs the status command")

    await expectError(ShellResult(exitCode: 127, stderr: "zsh: command not found: sprout-parallel"),
                      .notFound, "exit 127 means script not found")
    await expectError(ShellResult(exitCode: 1, stderr: "Error: Projects root '/x' does not exist.\n"),
                      .failed("Error: Projects root '/x' does not exist."), "status failure carries Error: line")
    let garbage = FakeShell { _ in ShellResult(exitCode: 0, stdout: "garbage") }
    do {
        _ = try await SproutCLI(shell: garbage).status()
        check(false, "non-JSON output throws")
    } catch let error as CLIError {
        if case .badOutput = error { check(true, "non-JSON output throws badOutput") }
        else { check(false, "non-JSON output throws badOutput, got \(error)") }
    } catch {
        check(false, "non-JSON output throws CLIError")
    }

    // run()
    let failing = FakeShell { _ in
        ShellResult(exitCode: 1, stdout: "Preparing…\n", stderr: "Error: Branch 'x' already exists in 'scooda'.\n")
    }
    let box = LinesBox()
    do {
        try await SproutCLI(shell: failing).run("sprout-parallel create x --project scooda --from main") { box.append($0) }
        check(false, "failed run throws")
    } catch let error as CLIError {
        checkEqual(error, .failed("Error: Branch 'x' already exists in 'scooda'."), "run failure carries Error: line")
    } catch {
        check(false, "run throws CLIError")
    }
    checkEqual(box.lines, ["Preparing…", "Error: Branch 'x' already exists in 'scooda'."], "run streams lines")

    let noErrorLine = FakeShell { _ in ShellResult(exitCode: 2, stdout: "", stderr: "fatal: bad thing\n") }
    do {
        try await SproutCLI(shell: noErrorLine).run("x") { _ in }
    } catch let error as CLIError {
        checkEqual(error.message, "fatal: bad thing", "falls back to last non-empty line")
    } catch {
        check(false, "run throws CLIError")
    }
    checkEqual(CLIError.notFound.message, "sprout-parallel not found — run install.sh", "notFound message")
}

private func expectError(_ result: ShellResult, _ expected: CLIError, _ name: String) async {
    let shell = FakeShell { _ in result }
    do {
        _ = try await SproutCLI(shell: shell).status()
        check(false, name)
    } catch let error as CLIError {
        checkEqual(error, expected, name)
    } catch {
        check(false, "\(name): unexpected \(error)")
    }
}
```

`app/Sources/SproutCoreChecks/LiveChecks.swift`:

```swift
import Foundation
import SproutCore

/// Prepends environment setup to every command, so the live check runs this
/// repo's script against a scratch projects root.
final class EnvShell: Shell {
    private let base: Shell
    private let prefix: String

    init(base: Shell, prefix: String) {
        self.base = base
        self.prefix = prefix
    }

    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        await base.run(prefix + command, onLine: onLine)
    }
}

/// End-to-end: real zsh, real script (from this checkout), scratch git repo.
func liveChecks() async {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SproutCoreChecks
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // app
        .deletingLastPathComponent()   // repo root
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sprout-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let shell = EnvShell(
        base: LoginShell(),
        prefix: "export SPROUT_PROJECTS_ROOT=\(shellQuote(root.path)); export PATH=\(shellQuote(repo.path)):\"$PATH\"; ")

    let setup = await shell.run("""
        mkdir -p "$SPROUT_PROJECTS_ROOT/demo" && cd "$SPROUT_PROJECTS_ROOT/demo" \
        && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
        """) { _ in }
    checkEqual(setup.exitCode, 0, "live: scratch project created")

    let cli = SproutCLI(shell: shell)
    do {
        try await cli.run(SproutCLI.createCommand(project: "demo", branch: "feature/live", base: "main", runSetup: false)) { _ in }
        let status = try await cli.status()
        let worktree = status.projects.first { $0.name == "demo" }?.worktrees.first
        checkEqual(worktree?.branch, "feature/live", "live: real script output decodes")
        checkEqual(worktree?.base, "main", "live: base recorded")
        checkEqual(worktree?.ahead, 0, "live: ahead computed")

        try await cli.run(SproutCLI.deleteCommand(project: "demo", folder: "feature-live", force: false, keepData: false)) { _ in }
        let after = try await cli.status()
        checkEqual(after.projects.first { $0.name == "demo" }?.worktrees.count, 0, "live: delete by folder works")
    } catch {
        check(false, "live: \(error)")
    }
}
```

Replace `app/Sources/SproutCoreChecks/main.swift`:

```swift
import Foundation

modelChecks()
await shellChecks()
await cliChecks()
await liveChecks()

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd app && swift run SproutCoreChecks`
Expected: compile errors, e.g. `cannot find type 'Shell' in scope`.

- [ ] **Step 3: Implement `Shell.swift`**

`app/Sources/SproutCore/Shell.swift`:

```swift
import Foundation

public struct ShellResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol Shell: AnyObject {
    /// Runs `command` and returns once it exits. `onLine` receives each line of
    /// stdout and stderr as it arrives, on a background thread.
    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult
}

/// Quotes `s` for a POSIX shell, leaving plainly safe strings untouched so
/// commands shown to the user stay readable.
public func shellQuote(_ s: String) -> String {
    let safe = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/@%+=:,-")
    if !s.isEmpty, s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
        return s
    }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Runs commands through a login shell (`zsh -lc`) so GUI launches get the
/// user's PATH (Homebrew, ~/.local/bin, …).
public final class LoginShell: Shell {
    private let shellPath: String

    public init(shellPath: String = "/bin/zsh") {
        self.shellPath = shellPath
    }

    public func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shellPath)
            process.arguments = ["-lc", command]
            process.standardInput = FileHandle.nullDevice
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ShellResult(exitCode: 127, stderr: error.localizedDescription))
                return
            }

            let out = LineCollector(onLine: onLine)
            let err = LineCollector(onLine: onLine)
            let group = DispatchGroup()

            for (pipe, collector) in [(outPipe, out), (errPipe, err)] {
                group.enter()
                DispatchQueue.global().async {
                    let handle = pipe.fileHandleForReading
                    while true {
                        let data = handle.availableData
                        if data.isEmpty { break }
                        collector.append(data)
                    }
                    group.leave()
                }
            }

            group.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                group.leave()
            }

            group.notify(queue: .global()) {
                continuation.resume(returning: ShellResult(
                    exitCode: process.terminationStatus,
                    stdout: out.finish(),
                    stderr: err.finish()))
            }
        }
    }
}

/// Splits a byte stream into lines, reporting each complete line as it arrives.
final class LineCollector {
    private let lock = NSLock()
    private var buffer = Data()
    private var text = ""
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        emitCompleteLines()
    }

    /// Flushes a trailing partial line and returns everything collected.
    func finish() -> String {
        lock.lock(); defer { lock.unlock() }
        emitCompleteLines()
        if !buffer.isEmpty {
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            text += line
            onLine(line)
        }
        return text
    }

    private func emitCompleteLines() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            text += line + "\n"
            onLine(line)
        }
    }
}
```

- [ ] **Step 4: Implement `SproutCLI.swift`**

`app/Sources/SproutCore/SproutCLI.swift`:

```swift
import Foundation

public enum CLIError: Error, Equatable {
    case notFound
    case failed(String)
    case badOutput(String)

    public var message: String {
        switch self {
        case .notFound: "sprout-parallel not found — run install.sh"
        case .failed(let message), .badOutput(let message): message
        }
    }
}

/// Builds and runs `sprout-parallel` commands.
public struct SproutCLI {
    public let shell: Shell

    public init(shell: Shell) {
        self.shell = shell
    }

    public static let statusCommand = "sprout-parallel status --json"

    public static func createCommand(project: String, branch: String, base: String, runSetup: Bool) -> String {
        var parts = ["sprout-parallel", "create", shellQuote(branch),
                     "--project", shellQuote(project), "--from", shellQuote(base)]
        if !runSetup { parts.append("--no-setup") }
        return parts.joined(separator: " ")
    }

    /// `folder` is the worktree folder name; the script's safe_name() maps it
    /// to itself, so this also works for detached-HEAD worktrees.
    public static func deleteCommand(project: String, folder: String, force: Bool, keepData: Bool) -> String {
        var parts = ["sprout-parallel", "delete", shellQuote(folder), "--project", shellQuote(project)]
        if force { parts.append("--force") }
        if keepData { parts.append("--keep-db") }
        return parts.joined(separator: " ")
    }

    /// Mirrors the script's safe_name(): `feature/x` → `feature-x`.
    public static func folderName(for branch: String) -> String {
        var name = branch.replacingOccurrences(of: "/", with: "-")
        if name.hasPrefix("-") { name.removeFirst() }
        if name.hasSuffix("-") { name.removeLast() }
        return name
    }

    /// Returns why `branch` can't be used, or nil if it's fine.
    public static func validateBranch(_ branch: String) -> String? {
        if branch.isEmpty { return "branch name required" }
        if branch.hasPrefix("-") { return "branch can't start with '-'" }
        if branch.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return "branch can't contain spaces" }
        let forbidden = CharacterSet(charactersIn: "\"'`$\\~^:?*[")
        if branch.rangeOfCharacter(from: forbidden) != nil { return "branch contains a character git doesn't allow" }
        if branch.contains("..") || branch.hasSuffix("/") || branch.hasSuffix(".lock") {
            return "not a valid git branch name"
        }
        return nil
    }

    public func status() async throws -> Status {
        let result = await shell.run(Self.statusCommand) { _ in }
        try Self.throwIfFailed(result)
        // Login shells may print banners first; the JSON is the last line starting with "{".
        guard let json = result.stdout.split(separator: "\n").last(where: { $0.hasPrefix("{") }) else {
            throw CLIError.badOutput("no JSON in status output")
        }
        do {
            return try Status.decode(Data(json.utf8))
        } catch {
            throw CLIError.badOutput("could not read status JSON: \(error.localizedDescription)")
        }
    }

    public func run(_ command: String, onLine: @escaping (String) -> Void) async throws {
        let result = await shell.run(command, onLine: onLine)
        try Self.throwIfFailed(result)
    }

    private static func throwIfFailed(_ result: ShellResult) throws {
        if result.exitCode == 127 { throw CLIError.notFound }
        guard result.exitCode == 0 else { throw CLIError.failed(errorLine(result)) }
    }

    private static func errorLine(_ result: ShellResult) -> String {
        let lines = (result.stderr + "\n" + result.stdout).split(separator: "\n").map(String.init)
        if let error = lines.last(where: { $0.hasPrefix("Error:") }) { return error }
        return lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? "exited with code \(result.exitCode)"
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd app && swift run SproutCoreChecks`
Expected: all `ok` (including the `live:` checks), `all checks passed`. If the `login shell returns exit code` / stdout check fails because your `~/.zprofile` prints text, that's Review Focus #1 showing up in the raw shell — note it in the task report; `status()` handles it.

- [ ] **Step 6: Commit**

```bash
git add app/Sources
git commit -m "Add login-shell runner and sprout-parallel CLI wrapper

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: WorktreeStore

**Files:**
- Create: `app/Sources/SproutCore/WorktreeStore.swift`
- Create: `app/Sources/SproutCoreChecks/StoreChecks.swift`
- Modify: `app/Sources/SproutCoreChecks/main.swift`

**Interfaces:**
- Consumes: `SproutCLI`, `CLIError`, `Status`, `Project`, `Worktree` (Tasks 3–4).
- Produces (public, `@MainActor final class WorktreeStore: ObservableObject`):
  - `enum Mode: Equatable { case list, create, delete(Worktree) }`
  - `enum Operation: Equatable { case idle, running, succeeded, failed(String) }`
  - Published read-only: `projects: [Project]`, `mode: Mode`, `operation: Operation`, `log: [String]`, `error: String?`, `scriptMissing: Bool`, `isRefreshing: Bool`, `lastRefresh: Date?`
  - Published settable: `selectedProjectName: String?`, `selectedWorktreePath: String?`
  - Computed: `selectedProject: Project?`, `selectedWorktree: Worktree?`, `worktreeCount: Int`, `isBusy: Bool`
  - Methods: `init(cli: SproutCLI)`, `refresh() async`, `selectProject(_ name: String)`, `moveProject(by: Int)`, `moveWorktree(by: Int)`, `beginCreate()`, `beginDelete()`, `backToList()`, `create(branch: String, base: String, runSetup: Bool) async`, `delete(_ worktree: Worktree, force: Bool, dropData: Bool) async`

- [ ] **Step 1: Write the failing checks**

`app/Sources/SproutCoreChecks/StoreChecks.swift`:

```swift
import Foundation
import SproutCore

@MainActor
func storeChecks() async {
    await refreshChecks()
    await createChecks()
    await deleteChecks()
    await navigationChecks()
}

@MainActor
private func refreshChecks() async {
    var fail = false
    let shell = FakeShell { _ in
        fail ? ShellResult(exitCode: 1, stderr: "Error: boom\n")
             : ShellResult(exitCode: 0, stdout: statusJSON(["feature/a", "feature/b"]))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()
    checkEqual(store.projects.map(\.name), ["scooda", "prayercal"], "refresh loads projects")
    checkEqual(store.selectedProjectName, "scooda", "first project selected")
    checkEqual(store.selectedWorktree?.branch, "feature/a", "first worktree selected")
    checkEqual(store.worktreeCount, 2, "worktree count")
    check(store.lastRefresh != nil, "lastRefresh set")
    check(!store.isRefreshing, "not refreshing afterwards")

    fail = true
    await store.refresh()
    checkEqual(store.projects.count, 2, "failed refresh keeps previous data")
    checkEqual(store.error, "Error: boom", "failed refresh shows error")

    fail = false
    await store.refresh()
    checkEqual(store.error, nil, "successful refresh clears error")

    let missing = WorktreeStore(cli: SproutCLI(shell: FakeShell { _ in ShellResult(exitCode: 127) }))
    await missing.refresh()
    check(missing.scriptMissing, "exit 127 flags script missing")
}

@MainActor
private func createChecks() async {
    var branches = ["feature/a"]
    let shell = FakeShell { command in
        if command.contains(" create ") {
            if command.contains("feature/taken") {
                return ShellResult(exitCode: 1, stderr: "Error: Branch 'feature/taken' already exists in 'scooda'.\n")
            }
            branches.append("feature/new")
            return ShellResult(exitCode: 0, stdout: "Created worktree\n  → Copying .env from main project\n")
        }
        return ShellResult(exitCode: 0, stdout: statusJSON(branches))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()

    store.beginCreate()
    checkEqual(store.mode, .create, "beginCreate switches mode")
    await store.create(branch: "feature/new", base: "main", runSetup: true)
    checkEqual(store.log.first, "$ sprout-parallel create feature/new --project scooda --from main", "log starts with command")
    check(store.log.contains("  → Copying .env from main project"), "log streams script output")
    checkEqual(store.operation, .succeeded, "create succeeded")
    checkEqual(store.selectedWorktree?.branch, "feature/new", "new worktree selected after create")
    checkEqual(shell.commands.last, "sprout-parallel status --json", "refreshes after create")
    checkEqual(store.mode, .create, "stays in create mode to show the log")

    store.backToList()
    checkEqual(store.mode, .list, "backToList returns to list")
    checkEqual(store.log, [], "backToList clears log")
    checkEqual(store.operation, .idle, "backToList resets operation")

    store.beginCreate()
    await store.create(branch: "feature/taken", base: "main", runSetup: false)
    checkEqual(store.operation, .failed("Error: Branch 'feature/taken' already exists in 'scooda'."), "create failure shown")
    checkEqual(shell.commands.last, "sprout-parallel status --json", "refreshes after failed create")

    let slow = FakeShell { command in
        command.contains(" create ") ? ShellResult(exitCode: 0, stdout: "ok")
                                     : ShellResult(exitCode: 0, stdout: statusJSON([]))
    }
    slow.delayNanos = 50_000_000
    let busy = WorktreeStore(cli: SproutCLI(shell: slow))
    await busy.refresh()
    async let first: Void = busy.create(branch: "feature/one", base: "main", runSetup: true)
    async let second: Void = busy.create(branch: "feature/two", base: "main", runSetup: true)
    _ = await (first, second)
    checkEqual(slow.commands.filter { $0.contains(" create ") }.count, 1, "only one operation at a time")
}

@MainActor
private func deleteChecks() async {
    var branches = ["feature/a", "feature/b"]
    let shell = FakeShell { command in
        if command.contains(" delete ") {
            branches.removeFirst()
            return ShellResult(exitCode: 0, stdout: "Deleted worktree 'feature-a'\n")
        }
        return ShellResult(exitCode: 0, stdout: statusJSON(branches))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()

    store.beginDelete()
    guard case .delete(let worktree) = store.mode else {
        check(false, "beginDelete enters delete mode")
        return
    }
    checkEqual(worktree.branch, "feature/a", "delete targets selected worktree")

    await store.delete(worktree, force: false, dropData: false)
    check(shell.commands.contains("sprout-parallel delete feature-a --project scooda --keep-db"),
          "delete uses folder name and --keep-db when not dropping data")
    checkEqual(store.operation, .succeeded, "delete succeeded")
    checkEqual(store.selectedWorktree?.branch, "feature/b", "selection moves to remaining worktree")
    checkEqual(store.worktreeCount, 1, "list refreshed after delete")
}

@MainActor
private func navigationChecks() async {
    let shell = FakeShell { _ in ShellResult(exitCode: 0, stdout: statusJSON(["feature/a", "feature/b"])) }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()

    store.moveWorktree(by: 1)
    checkEqual(store.selectedWorktree?.branch, "feature/b", "move down")
    store.moveWorktree(by: 5)
    checkEqual(store.selectedWorktree?.branch, "feature/b", "move clamps at end")
    store.moveWorktree(by: -9)
    checkEqual(store.selectedWorktree?.branch, "feature/a", "move clamps at start")

    store.moveProject(by: 1)
    checkEqual(store.selectedProjectName, "prayercal", "move to next project")
    checkEqual(store.selectedWorktree, nil, "empty project has no selection")
    store.beginDelete()
    checkEqual(store.mode, .list, "beginDelete ignored without a worktree")
    store.selectProject("scooda")
    checkEqual(store.selectedWorktree?.branch, "feature/a", "selectProject picks its first worktree")
}
```

Replace `app/Sources/SproutCoreChecks/main.swift`:

```swift
import Foundation

modelChecks()
await shellChecks()
await cliChecks()
await liveChecks()
await storeChecks()

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd app && swift run SproutCoreChecks`
Expected: compile error `cannot find 'WorktreeStore' in scope`.

- [ ] **Step 3: Implement**

`app/Sources/SproutCore/WorktreeStore.swift`:

```swift
import Foundation

/// App state: what's on disk (via `status --json`), what's selected, and the
/// create/delete operation in flight.
@MainActor
public final class WorktreeStore: ObservableObject {
    public enum Mode: Equatable {
        case list
        case create
        case delete(Worktree)
    }

    public enum Operation: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    @Published public private(set) var projects: [Project] = []
    @Published public var selectedProjectName: String?
    @Published public var selectedWorktreePath: String?
    @Published public private(set) var mode: Mode = .list
    @Published public private(set) var operation: Operation = .idle
    @Published public private(set) var log: [String] = []
    @Published public private(set) var error: String?
    @Published public private(set) var scriptMissing = false
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?

    private let cli: SproutCLI
    private var refreshQueued = false

    public init(cli: SproutCLI) {
        self.cli = cli
    }

    public var selectedProject: Project? {
        projects.first { $0.name == selectedProjectName }
    }

    public var selectedWorktree: Worktree? {
        selectedProject?.worktrees.first { $0.path == selectedWorktreePath }
    }

    public var worktreeCount: Int {
        projects.reduce(0) { $0 + $1.worktrees.count }
    }

    public var isBusy: Bool { operation == .running }

    // MARK: Loading

    /// UI-triggered refresh. Overlapping calls coalesce into one extra load.
    public func refresh() async {
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        repeat {
            refreshQueued = false
            await loadStatus()
        } while refreshQueued
        isRefreshing = false
    }

    private func loadStatus() async {
        do {
            let status = try await cli.status()
            projects = status.projects
            scriptMissing = false
            error = nil
            lastRefresh = Date()
            repairSelection()
        } catch CLIError.notFound {
            scriptMissing = true
        } catch let cliError as CLIError {
            error = cliError.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func repairSelection() {
        if selectedProject == nil {
            selectedProjectName = projects.first?.name
        }
        if selectedWorktree == nil {
            selectedWorktreePath = selectedProject?.worktrees.first?.path
        }
    }

    // MARK: Navigation

    public func selectProject(_ name: String) {
        selectedProjectName = name
        selectedWorktreePath = selectedProject?.worktrees.first?.path
    }

    public func moveProject(by offset: Int) {
        guard let index = projects.firstIndex(where: { $0.name == selectedProjectName }) else { return }
        let target = min(max(index + offset, 0), projects.count - 1)
        selectProject(projects[target].name)
    }

    public func moveWorktree(by offset: Int) {
        guard let worktrees = selectedProject?.worktrees, !worktrees.isEmpty else { return }
        let index = worktrees.firstIndex { $0.path == selectedWorktreePath } ?? 0
        let target = min(max(index + offset, 0), worktrees.count - 1)
        selectedWorktreePath = worktrees[target].path
    }

    // MARK: Modes

    public func beginCreate() {
        guard !isBusy, selectedProject != nil else { return }
        resetOperation()
        mode = .create
    }

    public func beginDelete() {
        guard !isBusy, let worktree = selectedWorktree else { return }
        resetOperation()
        mode = .delete(worktree)
    }

    public func backToList() {
        guard !isBusy else { return }
        resetOperation()
        mode = .list
    }

    private func resetOperation() {
        operation = .idle
        log = []
    }

    // MARK: Operations

    public func create(branch: String, base: String, runSetup: Bool) async {
        guard !isBusy, let project = selectedProject else { return }
        let command = SproutCLI.createCommand(project: project.name, branch: branch, base: base, runSetup: runSetup)
        let succeeded = await perform(command)
        await loadStatus()
        if succeeded,
           let created = selectedProject?.worktrees.first(where: { $0.branch == branch }) {
            selectedWorktreePath = created.path
        }
    }

    public func delete(_ worktree: Worktree, force: Bool, dropData: Bool) async {
        guard !isBusy, let project = selectedProject else { return }
        let command = SproutCLI.deleteCommand(
            project: project.name, folder: worktree.folder, force: force, keepData: !dropData)
        let succeeded = await perform(command)
        if succeeded, selectedWorktreePath == worktree.path {
            selectedWorktreePath = nil
        }
        await loadStatus()
    }

    private func perform(_ command: String) async -> Bool {
        log = ["$ " + command]
        operation = .running
        do {
            try await cli.run(command) { line in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.log.append(line) }
                }
            }
            await drainMainQueue()
            operation = .succeeded
            return true
        } catch {
            await drainMainQueue()
            operation = .failed((error as? CLIError)?.message ?? error.localizedDescription)
            return false
        }
    }

    /// Lets log lines already queued on the main queue land before we report
    /// the final status.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd app && swift run SproutCoreChecks`
Expected: all `ok`, `all checks passed`.

- [ ] **Step 5: Commit**

```bash
git add app/Sources
git commit -m "Add WorktreeStore with refresh, create, delete, and navigation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Terminal-styled list UI, app entry, snapshots

**Files:**
- Modify: `app/Package.swift`
- Create: `app/Sources/SproutUI/Theme.swift`
- Create: `app/Sources/SproutUI/Openers.swift`
- Create: `app/Sources/SproutUI/Chrome.swift`
- Create: `app/Sources/SproutUI/WorktreeListView.swift`
- Create: `app/Sources/SproutUI/PanelView.swift`
- Create: `app/Sources/Sprout/SproutApp.swift`
- Create: `app/Sources/SproutSnapshots/main.swift`

**Interfaces:**
- Consumes: `WorktreeStore` and its API (Task 5), `Project`, `Worktree`, `SproutCLI`, `LoginShell`, `Shell`, `ShellResult`.
- Produces (module `SproutUI`): `public struct PanelView: View { public init() }` (expects `WorktreeStore` as `environmentObject`); `public enum Openers { static func vscode(_:), warp(_:), finder(_:) }`; internal `Theme`, `KV`, `KeyHint`, `ActionChip`, `Hairline`. Task 7 replaces `PanelView.content`'s `.create`/`.delete` cases; Task 8 adds `LoginItemToggle()` to `FooterBar`.

- [ ] **Step 1: Add targets to the package**

Replace `app/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sprout",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SproutCore"),
        .target(name: "SproutUI", dependencies: ["SproutCore"]),
        .executableTarget(name: "Sprout", dependencies: ["SproutCore", "SproutUI"]),
        .executableTarget(name: "SproutCoreChecks", dependencies: ["SproutCore"]),
        .executableTarget(name: "SproutSnapshots", dependencies: ["SproutCore", "SproutUI"]),
    ]
)
```

- [ ] **Step 2: Write the snapshot renderer (the "test" for views)**

`app/Sources/SproutSnapshots/main.swift`:

```swift
import AppKit
import SproutCore
import SproutUI
import SwiftUI

/// Answers commands from canned results so views can be rendered offline.
final class FixtureShell: Shell {
    private let respond: (String) -> ShellResult

    init(_ respond: @escaping (String) -> ShellResult) {
        self.respond = respond
    }

    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        let result = respond(command)
        for line in (result.stdout + "\n" + result.stderr).split(separator: "\n") {
            onLine(String(line))
        }
        return result
    }
}

let fixture = #"""
{"projects":[
 {"name":"scooda","path":"/Users/mehdi/projects/scooda","branches":["develop","main","production"],"worktrees":[
  {"branch":"feature/payments-v2","folder":"feature-payments-v2","path":"/Users/mehdi/projects/scooda-worktrees/feature-payments-v2","base":"main","changes":3,"ahead":3,"behind":1,"lastCommit":{"hash":"a1f9c2e","subject":"Add Stripe webhook","when":"2 hours ago"},"mysqlDb":"scooda_feature_payments_v2","redisDb":3,"redisPrefix":"scooda_feature_payments_v2_"},
  {"branch":"fix/TICKET-123","folder":"fix-TICKET-123","path":"/Users/mehdi/projects/scooda-worktrees/fix-TICKET-123","base":"main","changes":0,"ahead":1,"behind":0,"lastCommit":{"hash":"77be01d","subject":"Guard null invoice","when":"5 days ago"},"mysqlDb":"scooda_fix_TICKET_123","redisDb":4,"redisPrefix":"scooda_fix_ticket_123_"}
 ]},
 {"name":"orphan7","path":"/Users/mehdi/projects/orphan7","branches":["main"],"worktrees":[
  {"branch":"feature/donor-export","folder":"feature-donor-export","path":"/Users/mehdi/projects/orphan7-worktrees/feature-donor-export","base":"main","changes":0,"ahead":5,"behind":12,"lastCommit":{"hash":"0c4d9aa","subject":"CSV export","when":"3 weeks ago"},"mysqlDb":null,"redisDb":null,"redisPrefix":null}
 ]},
 {"name":"bookcast","path":"/Users/mehdi/projects/bookcast","branches":["main"],"worktrees":[]}
]}
"""#.replacingOccurrences(of: "\n", with: "")

let outDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // SproutSnapshots
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // app
    .appendingPathComponent("build/snapshots")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

_ = NSApplication.shared

@MainActor
func makeStore(_ respond: @escaping (String) -> ShellResult) async -> WorktreeStore {
    let store = WorktreeStore(cli: SproutCLI(shell: FixtureShell(respond)))
    await store.refresh()
    return store
}

@MainActor
func render(_ name: String, _ store: WorktreeStore) {
    let renderer = ImageRenderer(content: PanelView().environmentObject(store))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("FAIL - could not render \(name)")
        exit(1)
    }
    let url = outDir.appendingPathComponent("\(name).png")
    try! png.write(to: url)
    print("wrote \(url.path)")
}

let ok: (String) -> ShellResult = { _ in ShellResult(exitCode: 0, stdout: fixture) }

let list = await makeStore(ok)
render("list", list)

let empty = await makeStore(ok)
empty.selectProject("bookcast")
render("list-empty-project", empty)

let missing = await makeStore { _ in ShellResult(exitCode: 127) }
render("script-missing", missing)

var failRefresh = false
let erroring = await makeStore { _ in
    failRefresh ? ShellResult(exitCode: 1, stderr: "Error: Projects root '/nope' does not exist.")
                : ShellResult(exitCode: 0, stdout: fixture)
}
failRefresh = true
await erroring.refresh()
render("refresh-error", erroring)
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd app && swift run SproutSnapshots`
Expected: build error — no sources for targets `SproutUI` / `Sprout`, or `cannot find 'PanelView' in scope`.

- [ ] **Step 4: Implement Theme and Openers**

`app/Sources/SproutUI/Theme.swift`:

```swift
import AppKit
import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0B0F14)
    static let bar = Color(hex: 0x0E141B)
    static let sidebar = Color(hex: 0x0A0E12)
    static let selection = Color(hex: 0x12202B)
    static let selectionEdge = Color(hex: 0x1D3A4A)
    static let border = Color(hex: 0x1F2A36)
    static let logBg = Color(hex: 0x070A0D)
    static let green = Color(hex: 0x39FFA0)
    static let amber = Color(hex: 0xFFCC66)
    static let red = Color(hex: 0xFF6B6B)
    static let cyan = Color(hex: 0x56D4FF)
    static let violet = Color(hex: 0xC792EA)
    static let muted = Color(hex: 0x6B7A8C)
    static let text = Color(hex: 0xC9D1D9)
    static let bright = Color(hex: 0xE6EDF3)

    private static let hasJetBrainsMono = NSFont(name: "JetBrainsMono-Regular", size: 12) != nil

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        hasJetBrainsMono
            ? .custom("JetBrains Mono", size: size).weight(weight)
            : .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
```

`app/Sources/SproutUI/Openers.swift`:

```swift
import AppKit

public enum Openers {
    public static func vscode(_ path: String) {
        open(["-a", "Visual Studio Code", path])
    }

    public static func warp(_ path: String) {
        open(["-a", "Warp", path])
    }

    public static func finder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private static func open(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try? process.run()
    }
}
```

- [ ] **Step 5: Implement Chrome (shared pieces)**

`app/Sources/SproutUI/Chrome.swift`:

```swift
import AppKit
import SproutCore
import SwiftUI

struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Label/value row used in detail boxes and forms.
struct KV<Content: View>: View {
    let key: String
    let content: Content

    init(_ key: String, @ViewBuilder content: () -> Content) {
        self.key = key
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(key).foregroundStyle(Theme.muted).frame(width: 64, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

struct KeyHint: View {
    let key: String
    let label: String
    var tint: Color = Theme.muted

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.bg)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(tint))
            Text(label).foregroundStyle(Theme.muted)
        }
    }
}

/// A clickable key hint. Callers attach `.keyboardShortcut` where one applies.
struct ActionChip: View {
    let key: String
    let label: String
    var tint: Color = Theme.muted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyHint(key: key, label: label, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

struct HeaderBar: View {
    @EnvironmentObject private var store: WorktreeStore

    var body: some View {
        HStack(spacing: 6) {
            Text("❯").foregroundStyle(Theme.green)
            Text("sprout").foregroundStyle(Theme.bright).fontWeight(.semibold)
            Text(rootLabel).foregroundStyle(Theme.muted)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(statusLabel(now: context.date)).foregroundStyle(Theme.muted)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Text(store.isRefreshing ? "◌" : "⟳").foregroundStyle(Theme.cyan)
            }
            .buttonStyle(.plain)
            .help("refresh (r)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bar)
    }

    private var rootLabel: String {
        guard let path = store.projects.first?.path else { return "" }
        let root = (path as NSString).deletingLastPathComponent
        return (root as NSString).abbreviatingWithTildeInPath
    }

    private func statusLabel(now: Date) -> String {
        let count = "\(store.worktreeCount) wt"
        guard let last = store.lastRefresh else { return count }
        return "\(count) · refreshed \(max(0, Int(now.timeIntervalSince(last))))s ago"
    }
}

struct ProjectSidebar: View {
    @EnvironmentObject private var store: WorktreeStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("PROJECTS")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                ForEach(store.projects) { project in
                    row(project)
                }
            }
        }
        .background(Theme.sidebar)
    }

    private func row(_ project: Project) -> some View {
        let selected = project.name == store.selectedProjectName
        return HStack {
            Text(project.name)
                .foregroundStyle(selected ? Theme.bright : (project.worktrees.isEmpty ? Theme.muted : Theme.text))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(selected && store.isBusy ? "◌" : "[\(project.worktrees.count)]")
                .foregroundStyle(selected && store.isBusy ? Theme.green : Theme.muted)
        }
        .padding(.leading, selected ? 10 : 12)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(selected ? Theme.selection : Color.clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Theme.green).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if store.mode == .list { store.selectProject(project.name) }
        }
    }
}

struct FooterBar: View {
    @EnvironmentObject private var store: WorktreeStore

    private struct Hint: Hashable {
        let key: String
        let label: String
        var primary = false
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(hints, id: \.self) { hint in
                KeyHint(key: hint.key, label: hint.label, tint: hint.primary ? Theme.green : Theme.muted)
            }
            Spacer()
            Button("quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .keyboardShortcut("q")
        }
        .font(Theme.mono(11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.bar)
    }

    private var hints: [Hint] {
        switch store.mode {
        case .list:
            [Hint(key: "⏎", label: "code", primary: true), Hint(key: "t", label: "warp"),
             Hint(key: "f", label: "finder"), Hint(key: "n", label: "new"),
             Hint(key: "⌫", label: "delete"), Hint(key: "r", label: "refresh"),
             Hint(key: "↑↓", label: "move")]
        case .create:
            [Hint(key: "⌘⏎", label: "create", primary: true), Hint(key: "esc", label: "back")]
        case .delete:
            [Hint(key: "⌘⏎", label: "delete", primary: true), Hint(key: "esc", label: "back")]
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Text("✗").foregroundStyle(Theme.red)
            Text(message).foregroundStyle(Theme.red).lineLimit(2)
            Spacer()
        }
        .font(Theme.mono(11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.red.opacity(0.08))
    }
}

struct ScriptMissingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("✗ sprout-parallel not found on your login-shell PATH").foregroundStyle(Theme.red)
            (Text("$ ").foregroundStyle(Theme.green) + Text("bash install.sh").foregroundStyle(Theme.bright))
            Text("then reopen this panel").foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 6: Implement the list + detail**

`app/Sources/SproutUI/WorktreeListView.swift`:

```swift
import AppKit
import SproutCore
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
                VStack(alignment: .leading, spacing: 0) {
                    WorktreeRow.header
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(project.worktrees) { worktree in
                                WorktreeRow(worktree: worktree, selected: worktree.path == store.selectedWorktreePath)
                                    .onTapGesture(count: 2) { Openers.vscode(worktree.path) }
                                    .onTapGesture { store.selectedWorktreePath = worktree.path }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    if let worktree = store.selectedWorktree {
                        WorktreeDetail(worktree: worktree).padding(.top, 10)
                    }
                }
            }
        } else {
            Text(store.isRefreshing ? "loading…" : "no projects found").foregroundStyle(Theme.muted)
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
    let worktree: Worktree

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            KV("base") { Text(worktree.base) }
            KV("head") { head }
            KV("dirty") {
                Text(worktree.isDirty ? "\(worktree.changes) file\(worktree.changes == 1 ? "" : "s")" : "clean")
                    .foregroundStyle(worktree.isDirty ? Theme.amber : Theme.green)
            }
            KV("mysql") {
                Text(worktree.mysqlDb ?? "—").foregroundStyle(worktree.mysqlDb == nil ? Theme.muted : Theme.violet)
            }
            KV("redis") { redis }
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
```

- [ ] **Step 7: Implement PanelView and the app entry**

`app/Sources/SproutUI/PanelView.swift`:

```swift
import AppKit
import SproutCore
import SwiftUI

public struct PanelView: View {
    @EnvironmentObject private var store: WorktreeStore
    @FocusState private var focused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Hairline()
            if store.scriptMissing {
                ScriptMissingView()
            } else {
                HStack(spacing: 0) {
                    ProjectSidebar().frame(width: 170)
                    Hairline(vertical: true)
                    content
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            if let error = store.error {
                ErrorBanner(message: error)
            }
            Hairline()
            FooterBar()
        }
        .frame(width: 620, height: 400)
        .background(Theme.bg)
        .font(Theme.mono())
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(action: handleKey)
        .onChange(of: store.mode) { _, mode in
            focused = mode == .list
        }
        .task {
            focused = true
            await store.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focused = store.mode == .list
            Task { await store.refresh() }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.mode {
        case .list:
            WorktreeListView()
        case .create:
            Text("create form — Task 7").foregroundStyle(Theme.muted)
        case .delete:
            Text("delete confirm — Task 7").foregroundStyle(Theme.muted)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard store.mode == .list else { return .ignored }
        let shift = press.modifiers.contains(.shift)
        let worktree = store.selectedWorktree

        switch press.key {
        case .upArrow:
            shift ? store.moveProject(by: -1) : store.moveWorktree(by: -1)
            return .handled
        case .downArrow:
            shift ? store.moveProject(by: 1) : store.moveWorktree(by: 1)
            return .handled
        case .return:
            if let worktree { Openers.vscode(worktree.path) }
            return .handled
        case .delete:
            store.beginDelete()
            return .handled
        default:
            break
        }

        switch press.characters {
        case "t":
            if let worktree { Openers.warp(worktree.path) }
        case "f":
            if let worktree { Openers.finder(worktree.path) }
        case "n":
            store.beginCreate()
        case "r":
            Task { await store.refresh() }
        default:
            return .ignored
        }
        return .handled
    }
}
```

`app/Sources/Sprout/SproutApp.swift`:

```swift
import SproutCore
import SproutUI
import SwiftUI

@main
struct SproutApp: App {
    @StateObject private var store = WorktreeStore(cli: SproutCLI(shell: LoginShell()))

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            Image(systemName: "leaf.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 8: Render snapshots and inspect them**

Run: `cd app && swift build && swift run SproutSnapshots`
Expected: four `wrote …/app/build/snapshots/<name>.png` lines, exit 0. Open each PNG (Read tool or Quick Look) and confirm against the approved mockup (`.superpowers/brainstorm/*/content/terminal-style.html`): dark background, monospace, `❯ sprout ~/projects` header, sidebar with a green left edge on `scooda`, amber dot on `feature/payments-v2`, `↑3 ↓1` green/red, cyan `db:3`, detail box with amber hash and violet DB names, footer key hints. `list-empty-project.png` shows the "create one" chip; `script-missing.png` shows the install hint; `refresh-error.png` shows the red banner **and** the previous list. If `ScrollView` content renders blank in `ImageRenderer`, say so in the report — it's a renderer limitation, not an app bug; confirm in Task 8's live run.

- [ ] **Step 9: Re-run checks, then commit**

Run: `cd app && swift run SproutCoreChecks`
Expected: `all checks passed`.

```bash
git add app/Package.swift app/Sources
git commit -m "Add terminal-styled menu bar panel with worktree list and detail

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Create form, delete confirmation, live log

**Files:**
- Create: `app/Sources/SproutUI/LogView.swift`
- Create: `app/Sources/SproutUI/CreateForm.swift`
- Create: `app/Sources/SproutUI/DeleteConfirm.swift`
- Modify: `app/Sources/SproutUI/PanelView.swift` (`content` switch)
- Modify: `app/Sources/SproutSnapshots/main.swift` (append renders)

**Interfaces:**
- Consumes: `WorktreeStore.create/delete/backToList/beginCreate/beginDelete`, `operation`, `log`, `isBusy`; `SproutCLI.validateBranch`, `SproutCLI.folderName`; `KV`, `ActionChip`, `Theme` (Task 6).
- Produces: `CreateForm(project:)`, `DeleteConfirm(worktree:)`, `LogView()`.

- [ ] **Step 1: Add the snapshot cases (failing)**

Append to the end of `app/Sources/SproutSnapshots/main.swift`:

```swift
let createOK: (String) -> ShellResult = { command in
    command.contains(" create ")
        ? ShellResult(exitCode: 0, stdout: """
            Created worktree for branch 'feature-invoices'
            Running setup in /Users/mehdi/projects/scooda-worktrees/feature-invoices ...
              → Copying .env from main project
              → Creating database 'scooda_feature_invoices' (clone of 'scooda')
              Warning: mysqldump not found — database created but not populated.
              → Updated .env: REDIS_DB=5, REDIS_CACHE_DB=5
            """)
        : ShellResult(exitCode: 0, stdout: fixture)
}

let creating = await makeStore(createOK)
creating.beginCreate()
render("create-empty", creating)
await creating.create(branch: "feature/invoices", base: "main", runSetup: true)
render("create-done", creating)

let createFail = await makeStore { command in
    command.contains(" create ")
        ? ShellResult(exitCode: 1, stderr: "Error: Branch 'feature/payments-v2' already exists in 'scooda'.")
        : ShellResult(exitCode: 0, stdout: fixture)
}
createFail.beginCreate()
await createFail.create(branch: "feature/payments-v2", base: "main", runSetup: true)
render("create-failed", createFail)

let deleting = await makeStore(ok)
deleting.beginDelete()
render("delete-dirty", deleting)
```

Run: `cd app && swift run SproutSnapshots`
Expected: it runs, but `create-empty.png` / `delete-dirty.png` show the Task 6 stand-in text ("create form — Task 7") — this is the failing state.

- [ ] **Step 2: Implement LogView**

`app/Sources/SproutUI/LogView.swift`:

```swift
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
        .frame(maxWidth: .infinity, maxHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.logBg))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
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
```

- [ ] **Step 3: Implement CreateForm**

`app/Sources/SproutUI/CreateForm.swift`:

```swift
import SproutCore
import SwiftUI

struct CreateForm: View {
    @EnvironmentObject private var store: WorktreeStore
    let project: Project

    @State private var branch = ""
    @State private var base = "main"
    @State private var runSetup = true
    @FocusState private var branchFocused: Bool

    private var problem: String? { SproutCLI.validateBranch(branch) }
    private var locked: Bool { store.isBusy || store.operation == .succeeded }
    private var canSubmit: Bool { problem == nil && !locked }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("new worktree · ").foregroundStyle(Theme.muted) + Text(project.name).foregroundStyle(Theme.bright))
                .padding(.bottom, 4)

            KV("branch") {
                TextField("", text: $branch, prompt: Text("feature/…").foregroundStyle(Theme.muted))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.bright)
                    .tint(Theme.green)
                    .focused($branchFocused)
                    .disabled(locked)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.green).frame(height: 1) }
                    .onSubmit(submit)
            }
            KV("from") {
                Picker("", selection: $base) {
                    ForEach(project.branches, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(locked)
            }
            KV("setup") {
                Button { runSetup.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(runSetup ? "[x]" : "[ ]").foregroundStyle(runSetup ? Theme.green : Theme.muted)
                        Text(".env mysql redis composer npm").foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(locked)
            }
            KV("path") {
                (Text("~/…/\(project.name)-worktrees/").foregroundStyle(Theme.muted)
                    + Text(SproutCLI.folderName(for: branch)).foregroundStyle(Theme.bright))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if !branch.isEmpty, let problem {
                Text("✗ \(problem)").foregroundStyle(Theme.red).font(Theme.mono(11))
            }
            if !store.log.isEmpty {
                LogView().padding(.top, 4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ActionChip(key: "⌘⏎", label: "create", tint: Theme.green, action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)
                ActionChip(key: "esc", label: store.operation == .succeeded ? "done" : "back") { store.backToList() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isBusy)
            }
            .font(Theme.mono(11))
        }
        .onAppear {
            base = project.branches.contains("main") ? "main" : (project.branches.first ?? "main")
            branchFocused = true
        }
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await store.create(branch: branch, base: base, runSetup: runSetup) }
    }
}
```

- [ ] **Step 4: Implement DeleteConfirm**

`app/Sources/SproutUI/DeleteConfirm.swift`:

```swift
import SproutCore
import SwiftUI

struct DeleteConfirm: View {
    @EnvironmentObject private var store: WorktreeStore
    let worktree: Worktree

    @State private var force = false
    @State private var dropData = true

    private var locked: Bool { store.isBusy || store.operation == .succeeded }
    private var canDelete: Bool { (!worktree.isDirty || force) && !locked }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("delete ").foregroundStyle(Theme.red)
                + Text(worktree.branch).foregroundStyle(Theme.bright)
                + Text(" ?").foregroundStyle(Theme.red))
                .padding(.bottom, 4)
            if worktree.isDirty {
                Text("⚠ \(worktree.changes) uncommitted change\(worktree.changes == 1 ? "" : "s") — will be lost")
                    .foregroundStyle(Theme.amber)
            }
            CheckRow(on: $force, label: "discard uncommitted changes",
                     note: worktree.isDirty ? "--force · required" : "--force", tint: Theme.red)
                .disabled(locked)
            CheckRow(on: $dropData, label: "drop mysql db & clear redis keys",
                     note: "off = --keep-db", tint: Theme.green)
                .disabled(locked)
            Text("branch \(worktree.branch) is kept").foregroundStyle(Theme.muted).font(Theme.mono(11))
            if !store.log.isEmpty {
                LogView().padding(.top, 4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ActionChip(key: "⌘⏎", label: "delete", tint: Theme.red, action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canDelete)
                    .opacity(canDelete ? 1 : 0.4)
                ActionChip(key: "esc", label: store.operation == .succeeded ? "done" : "back") { store.backToList() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isBusy)
            }
            .font(Theme.mono(11))
        }
    }

    private func submit() {
        guard canDelete else { return }
        Task { await store.delete(worktree, force: force, dropData: dropData) }
    }
}

struct CheckRow: View {
    @Binding var on: Bool
    let label: String
    let note: String
    let tint: Color

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 6) {
                Text(on ? "[x]" : "[ ]").foregroundStyle(on ? tint : Theme.muted)
                Text(label).foregroundStyle(Theme.text)
                Text(note).foregroundStyle(Theme.muted).font(Theme.mono(11))
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 5: Wire the modes into PanelView**

In `app/Sources/SproutUI/PanelView.swift`, replace the `content` property with:

```swift
    @ViewBuilder private var content: some View {
        switch store.mode {
        case .list:
            WorktreeListView()
        case .create:
            if let project = store.selectedProject {
                CreateForm(project: project)
            }
        case .delete(let worktree):
            DeleteConfirm(worktree: worktree)
        }
    }
```

- [ ] **Step 6: Render and inspect**

Run: `cd app && swift build && swift run SproutSnapshots`
Expected: eight PNGs written. Check:
- `create-empty.png` — form with `branch` / `from` / `setup [x]` / `path`, the `⌘⏎ create` chip at 40% opacity (empty branch). The TextField and Picker may render as placeholders under `ImageRenderer` (AppKit-backed controls); verify those in Task 8's live run.
- `create-done.png` — log starting `$ sprout-parallel create feature/invoices --project scooda --from main` (green `$`), `→` lines normal, the `Warning:` line amber, footer status `✓ done · esc to go back`, and `feature/invoices`'s absence from the fixture is fine (fixture status is static).
- `create-failed.png` — red `✗ Error: Branch 'feature/payments-v2' already exists in 'scooda'.`
- `delete-dirty.png` — red `delete feature/payments-v2 ?`, amber `⚠ 3 uncommitted changes`, `[ ] discard … --force · required`, `[x] drop mysql db & clear redis keys`, dimmed delete chip.

- [ ] **Step 7: Re-run checks, then commit**

Run: `cd app && swift run SproutCoreChecks`
Expected: `all checks passed`.

```bash
git add app/Sources
git commit -m "Add create form, delete confirmation, and streaming log

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Bundle, launch at login, install, docs, live verification

**Files:**
- Create: `app/Info.plist`
- Create: `app/build.sh`
- Create: `app/Sources/SproutUI/LoginItemToggle.swift`
- Modify: `app/Sources/SproutUI/Chrome.swift` (`FooterBar`)
- Modify: `docs/README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: `bash app/build.sh [--open]` → `~/Applications/Sprout.app`.

- [ ] **Step 1: Write the bundle files**

`app/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Sprout</string>
    <key>CFBundleIdentifier</key>
    <string>agency.manza.sprout</string>
    <key>CFBundleName</key>
    <string>Sprout</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

`app/build.sh`:

```bash
#!/usr/bin/env bash
# Build Sprout.app and install it to ~/Applications. Pass --open to launch it.
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release --product Sprout
BIN="$(swift build -c release --show-bin-path)/Sprout"

APP="build/Sprout.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Sprout"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

pkill -x Sprout 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Sprout.app"
cp -R "$APP" "$HOME/Applications/"
echo "Installed: $HOME/Applications/Sprout.app"

if [[ "${1:-}" == "--open" ]]; then
  open "$HOME/Applications/Sprout.app"
fi
```

Run: `chmod +x app/build.sh && plutil -lint app/Info.plist`
Expected: `app/Info.plist: OK`.

- [ ] **Step 2: Add the launch-at-login toggle**

`app/Sources/SproutUI/LoginItemToggle.swift`:

```swift
import ServiceManagement
import SwiftUI

struct LoginItemToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var failed = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Text(enabled ? "[x]" : "[ ]").foregroundStyle(enabled ? Theme.green : Theme.muted)
                Text("login").foregroundStyle(failed ? Theme.red : Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .help(failed ? "couldn't change the login item — is Sprout in ~/Applications?" : "launch at login")
    }

    private func toggle() {
        do {
            if enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            failed = false
        } catch {
            failed = true
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}
```

In `app/Sources/SproutUI/Chrome.swift`, in `FooterBar.body`, insert `LoginItemToggle()` between `Spacer()` and the `Button("quit")`:

```swift
            Spacer()
            LoginItemToggle()
            Button("quit") { NSApp.terminate(nil) }
```

- [ ] **Step 3: Build and install**

Run: `bash app/build.sh`
Expected: `Build complete!`, codesign succeeds silently, `Installed: /Users/mehdi/Applications/Sprout.app`.

Run: `codesign -dv ~/Applications/Sprout.app 2>&1 | grep -E 'Identifier|Signature'`
Expected: `Identifier=agency.manza.sprout` and `Signature=adhoc`.

- [ ] **Step 4: Live run against a scratch projects root**

```bash
SCRATCH="$(mktemp -d)"
mkdir "$SCRATCH/demo" && git -C "$SCRATCH/demo" init -q -b main && git -C "$SCRATCH/demo" commit -q --allow-empty -m init
SPROUT_PROJECTS_ROOT="$SCRATCH" ~/Applications/Sprout.app/Contents/MacOS/Sprout &
echo "$SCRATCH"
```

The app inherits `SPROUT_PROJECTS_ROOT`, and `zsh -lc` passes it through. Then ask the human partner to click the leaf icon in the menu bar and walk this checklist, reporting anything off:

1. Panel opens dark and monospace; header `❯ sprout …`; sidebar shows `demo [0]`.
2. `n` → create form with the branch field focused (green caret); type `feature/ui-test`; path preview updates; `⌘⏎` → log streams starting with `$ sprout-parallel create …`, ends `✓ done`.
3. `esc` → list shows `feature/ui-test` selected with green dot and `↑0 ↓0`.
4. `⏎` opens VS Code, `t` opens Warp, `f` reveals in Finder, all at the worktree folder.
5. Create `bad name` → `✗ branch can't contain spaces`, create disabled.
6. `⌫` → delete confirm; `⌘⏎` → log ends `✓ done`; `esc` → list is empty again.
7. Toggle `[ ] login` → `[x] login`; appears under System Settings → General → Login Items; toggle back.
8. Close and reopen the panel → "refreshed 0s ago".

Afterwards: `pkill -x Sprout; rm -rf "$SCRATCH"`.

- [ ] **Step 5: Document the app**

Append to `docs/README.md`:

````markdown
---

## Sprout menu bar app

A terminal-styled macOS menu bar app for viewing and managing worktrees across
every project under `$SPROUT_PROJECTS_ROOT`. It drives the `sprout-parallel`
CLI (`status --json`, `create`, `delete`), so both always agree.

### Install

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
bash install.sh          # the app calls sprout-parallel from your login shell
bash app/build.sh --open # builds Sprout.app into ~/Applications and launches it
```

### Keys

| Key | Action |
|---|---|
| `↑` `↓` | select worktree |
| `⇧↑` `⇧↓` | select project |
| `⏎` | open in VS Code |
| `t` | open in Warp |
| `f` | reveal in Finder |
| `n` | new worktree in the selected project |
| `⌫` | delete the selected worktree |
| `r` | refresh |
| `⌘⏎` / `esc` | confirm / back (in forms) |

### Development

```bash
cd app
swift run SproutCoreChecks   # logic checks (no Xcode needed)
swift run SproutSnapshots    # renders views to app/build/snapshots/*.png
bash ../tests/status_test.sh # status --json tests
```
````

- [ ] **Step 6: Final verification, then commit**

Run: `bash tests/status_test.sh && (cd app && swift run SproutCoreChecks)`
Expected: `all tests passed` and `all checks passed`.

```bash
git add app/Info.plist app/build.sh app/Sources docs/README.md
git commit -m "Add app bundle build, launch-at-login toggle, and docs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
