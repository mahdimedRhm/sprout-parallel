# Research: Worktree Manager CLI (sprout-parallel)

**Phase**: 0 | **Date**: 2026-03-31 | **Branch**: `001-worktree-manager`

---

## Decision 1: Implementation Language

**Decision**: Bash (single executable script)

**Rationale**: The tool wraps `git` shell commands, targets macOS/Linux, and has no data processing needs beyond string manipulation. A bash script requires zero runtime installation, is trivially placed on `$PATH`, and is directly readable/editable by the user. Alternatives like Python or Go would add runtime dependencies or a build step with no benefit at this scope.

**Alternatives considered**:
- Python 3: readable, cross-platform, but requires python3 on PATH and a shebang/venv setup
- Go: single binary, fast, but requires compilation and a Go toolchain
- zsh: narrower compatibility than bash on Linux systems

---

## Decision 2: git worktree Command Reference

**Decision**: Use `git worktree add -b`, `git worktree remove`, `git worktree list --porcelain`, `git worktree prune`

**Key commands**:

| Operation | Command |
|-----------|---------|
| Create new branch + worktree | `git -C <project> worktree add -b <branch> <path> <base>` |
| Delete worktree (clean) | `git -C <project> worktree remove <path>` |
| Delete worktree (force) | `git -C <project> worktree remove --force <path>` |
| List worktrees (machine-readable) | `git -C <project> worktree list --porcelain` |
| Prune stale entries | `git -C <project> worktree prune` |
| Check if branch exists | `git -C <project> rev-parse --verify "refs/heads/<branch>"` |
| Check worktree is dirty | `git -C <wt-path> status --porcelain` (non-empty = dirty) |
| Get repo root from inside | `git -C <path> rev-parse --show-toplevel` |

**Minimum git version**: 2.17 (for `git worktree remove`, released April 2018). All modern macOS/Linux systems satisfy this.

**Rationale**: Using `-C <path>` instead of `cd` keeps the script stateless — no need to track or restore `$PWD`.

---

## Decision 3: Subcommand Dispatch Pattern

**Decision**: `case "$1" in create|delete|list|help)` dispatch with per-function argument parsing

**Pattern**:
```bash
main() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true
  case "$cmd" in
    create) cmd_create "$@" ;;
    delete) cmd_delete "$@" ;;
    list)   cmd_list   "$@" ;;
    help|--help|-h) cmd_help ;;
    *) die "Unknown command: $cmd. Run 'sprout-parallel help'." ;;
  esac
}
```

**Rationale**: Simple and readable. No external argument-parsing library needed. Each subcommand function parses its own flags via a `while` loop over `"$@"`.

---

## Decision 4: Project Auto-detection

**Decision**: Walk up from `$PWD` to find the git root, then match against `$SPROUT_PROJECTS_ROOT`

**Logic**:
1. Run `git rev-parse --show-toplevel 2>/dev/null` from `$PWD`
2. If it returns a path that is a direct child of `$SPROUT_PROJECTS_ROOT` → project detected
3. If it returns a path inside a `<project>-worktrees/` sibling → also valid (user is inside an existing worktree)
4. If neither → require `--project <name>` or error

**Rationale**: Handles the case where the user is inside a worktree (edge case in spec) — the tool looks at the path, not the git object model, to determine the project name.

---

## Decision 5: Worktree Path Naming (Branch → Folder)

**Decision**: Replace `/` with `-`, lowercase, strip leading/trailing dashes

**Example**:
- `feature/my-thing` → `feature-my-thing`
- `fix/TICKET-123` → `fix-TICKET-123`

**Implementation**:
```bash
safe_name() { echo "$1" | tr '/' '-' | sed 's/^-//;s/-$//'; }
```

**Rationale**: Minimal transformation — preserves readability while ensuring filesystem safety. Does not lowercase to preserve case-sensitive branch names.

---

## Decision 6: Installation Approach

**Decision**: `install.sh` helper that symlinks the script to `~/.local/bin/sprout-parallel`

**Rationale**: Symlinking means updates to the source file are immediately reflected without reinstalling. `~/.local/bin` is on `$PATH` by default on modern macOS (via `/etc/paths.d` or `.zshrc`). Falls back to `/usr/local/bin` if `~/.local/bin` doesn't exist and user has write permission.

---

## Decision 7: Testing Approach

**Decision**: [bats-core](https://github.com/bats-core/bats-core) with temporary git repos created in `$BATS_TMPDIR`

**Rationale**: BATS is the de-facto standard for bash script testing. Each test creates a throwaway git repo in a temp directory, runs the script against it, and asserts filesystem and git state. No mocking needed — git operations on temp repos are fast and deterministic.

**Test categories**:
- Unit: `safe_name()` and other pure functions
- Integration: create/delete/list against real temp git repos
- Edge cases: dirty worktree, branch exists, non-git directory
