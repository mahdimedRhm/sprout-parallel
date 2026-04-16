# Tasks: Worktree Manager CLI (sprout-parallel)

**Input**: Design documents from `/specs/001-worktree-manager/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli-contract.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths included in every task description

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create project file structure and install helper.

- [x] T001 Create project directory structure: `docs/` and `tests/` directories at repo root, and empty `sprout-parallel` script file (no extension) at repo root
- [x] T00X [P] Write `install.sh` at repo root: symlinks `sprout-parallel` to `~/.local/bin/sprout-parallel` (falls back to `/usr/local/bin` if `~/.local/bin` doesn't exist); makes the script executable; prints confirmation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core bash scaffolding shared by all three user stories. Must be complete before any command can be implemented.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T00X Implement script bootstrap in `sprout-parallel`: shebang `#!/usr/bin/env bash`, `set -euo pipefail`, `main()` dispatcher using `case "$1"` for create/delete/list/help/--help/-h, and `main "$@"` invocation at end of file
- [x] T00X Implement `die()` helper in `sprout-parallel`: prints `"Error: $*"` to stderr and exits with code 1; implement `die2()` variant that exits with code 2 for git failures
- [x] T00X Implement `safe_name()` function in `sprout-parallel`: takes a branch name, replaces all `/` with `-`, strips leading and trailing `-` characters (e.g. `feature/my-thing` → `feature-my-thing`)
- [x] T00X Implement `resolve_project()` function in `sprout-parallel`: reads `SPROUT_PROJECTS_ROOT` env var (defaults to `/Users/mehdi/projects`); if `--project <name>` is provided, validates that `$SPROUT_PROJECTS_ROOT/<name>` exists and contains `.git`; if no `--project`, calls `git rev-parse --show-toplevel` from `$PWD` and matches the result against a direct child of `$SPROUT_PROJECTS_ROOT` (handles case where `$PWD` is inside a `<project>-worktrees/` sibling); errors with clear messages per `contracts/cli-contract.md`
- [x] T00X Implement `cmd_help()` in `sprout-parallel`: prints full usage text to stdout covering all three commands (create, delete, list) with their flags, defaults, examples, and the `SPROUT_PROJECTS_ROOT` environment variable; supports `help <command>` for per-command detail; exit code 0

**Checkpoint**: Foundation ready — user story implementation can now begin.

---

## Phase 3: User Story 1 — Create a Worktree (Priority: P1) 🎯 MVP

**Goal**: `sprout-parallel create <branch-name> [--project <name>] [--from <base>]` creates a new branch and a new worktree folder at `<projects-root>/<project>-worktrees/<safe-branch-name>/`.

**Independent Test**: Run `sprout-parallel create feature/test-branch` from inside any project directory; verify the folder exists at the expected path; run `git worktree list` and confirm the new entry appears.

### Implementation for User Story 1

- [x] T00X [US1] Implement `cmd_create()` argument parsing in `sprout-parallel`: parse positional `<branch-name>` (required — error if missing), `--project <name>`, and `--from <base>` (default: `main`); call `resolve_project()` to get project name and path
- [x] T00X [US1] Implement branch existence validation in `cmd_create()` in `sprout-parallel`: run `git -C "$project_path" rev-parse --verify "refs/heads/$branch"` and `git -C "$project_path" rev-parse --verify "refs/remotes/origin/$branch"` — if either succeeds, call `die()` with the "branch already exists" message from `contracts/cli-contract.md`
- [x] T010 [US1] Implement worktrees directory creation and `git worktree add` invocation in `cmd_create()` in `sprout-parallel`: compute `worktrees_dir="$SPROUT_PROJECTS_ROOT/${project_name}-worktrees"` and `worktree_path="$worktrees_dir/$(safe_name "$branch")`; create `$worktrees_dir` if it doesn't exist (`mkdir -p`); run `git -C "$project_path" worktree add -b "$branch" "$worktree_path" "$base_branch"` — on failure call `die2()`; print success output matching the format in `contracts/cli-contract.md` exactly

**Checkpoint**: User Story 1 fully functional. `sprout-parallel create` works end-to-end.

---

## Phase 4: User Story 2 — Delete a Worktree (Priority: P2)

**Goal**: `sprout-parallel delete <branch-name> [--project <name>] [--force]` removes the worktree directory and prunes its git registration; warns and blocks on dirty state without `--force`.

**Independent Test**: Create a worktree manually with `git worktree add`, then run `sprout-parallel delete <branch-name>`; verify the folder is gone and `git worktree list` no longer shows the entry.

### Implementation for User Story 2

- [x] T011 [US2] Implement `cmd_delete()` argument parsing in `sprout-parallel`: parse positional `<branch-name>` (required), `--project <name>`, and `--force` flag; call `resolve_project()` to get project name and path
- [x] T012 [US2] Implement worktree existence check in `cmd_delete()` in `sprout-parallel`: compute `worktree_path="$SPROUT_PROJECTS_ROOT/${project_name}-worktrees/$(safe_name "$branch")`; if `$worktree_path` does not exist as a directory, call `die()` with the "not found" message from `contracts/cli-contract.md`
- [x] T013 [US2] Implement dirty-state guard and `git worktree remove` invocation in `cmd_delete()` in `sprout-parallel`: run `git -C "$worktree_path" status --porcelain`; if output is non-empty and `--force` is not set, call `die()` with the dirty worktree message; run `git -C "$project_path" worktree remove${force:+ --force} "$worktree_path"` then `git -C "$project_path" worktree prune` — on git failure call `die2()`; print success output matching `contracts/cli-contract.md`

**Checkpoint**: User Stories 1 and 2 both functional independently.

---

## Phase 5: User Story 3 — List Worktrees (Priority: P3)

**Goal**: `sprout-parallel list [--project <name>]` prints all parallel worktrees for a project with branch name, path, and clean/dirty status.

**Independent Test**: Create two worktrees for a project; run `sprout-parallel list`; verify both entries appear with correct paths and status. Then run with no worktrees and verify the "no worktrees" message appears.

### Implementation for User Story 3

- [x] T014 [US3] Implement `cmd_list()` argument parsing in `sprout-parallel`: parse `--project <name>` flag; call `resolve_project()` to get project name and path; compute `worktrees_dir="$SPROUT_PROJECTS_ROOT/${project_name}-worktrees"`
- [x] T015 [US3] Implement worktree enumeration and output in `cmd_list()` in `sprout-parallel`: if `$worktrees_dir` does not exist or is empty, print the "No parallel worktrees found" message from `contracts/cli-contract.md` and exit 0; otherwise iterate over each subdirectory in `$worktrees_dir`, retrieve its branch name via `git -C "$entry" rev-parse --abbrev-ref HEAD`, determine status via `git -C "$entry" status --porcelain` (empty = clean, non-empty = dirty), print each line in the format from `contracts/cli-contract.md`

**Checkpoint**: All three user stories functional independently.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, installability validation, and end-to-end smoke test.

- [x] T016 Write `docs/README.md`: cover installation (via `install.sh` and manual `PATH` setup), `SPROUT_PROJECTS_ROOT` configuration, all three commands with their flags and examples, directory layout diagram from `quickstart.md`, and exit code reference from `contracts/cli-contract.md`
- [x] T017 [P] Verify `sprout-parallel` is executable (`chmod +x sprout-parallel`) and that running `bash install.sh` creates a working symlink; confirm `sprout-parallel --help` succeeds after install
- [x] T018 Run end-to-end validation using the scenarios in `specs/001-worktree-manager/quickstart.md`: create a worktree, list it, verify dirty detection, delete with and without `--force`, and confirm `SPROUT_PROJECTS_ROOT` override works

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — **blocks all user stories**
- **US1 (Phase 3)**: Depends on Phase 2 only — no dependency on US2 or US3
- **US2 (Phase 4)**: Depends on Phase 2 only — no dependency on US1 or US3
- **US3 (Phase 5)**: Depends on Phase 2 only — no dependency on US1 or US2
- **Polish (Phase 6)**: Depends on all desired user story phases being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — independent
- **US2 (P2)**: Can start after Phase 2 — independent (uses same `resolve_project()` + `safe_name()` helpers)
- **US3 (P3)**: Can start after Phase 2 — independent

### Within Each User Story (Phase 3–5)

- Argument parsing task before validation/logic task
- Validation/logic task before git invocation + output task
- All tasks within a story touch `sprout-parallel` — run sequentially within the story

---

## Parallel Opportunities

```bash
# Phase 1: T001 and T002 can run in parallel (different files)
Task T001: "Create directory structure and sprout-parallel file"
Task T002: "Write install.sh"

# Phase 2: T003–T007 must run sequentially (all in sprout-parallel, building on each other)

# Phase 3–5: Once Phase 2 is done, all three user stories can start in parallel
# (each story adds a new cmd_X() function to sprout-parallel)
Story US1: T008 → T009 → T010
Story US2: T011 → T012 → T013
Story US3: T014 → T015

# Phase 6: T016 and T017 can run in parallel
Task T016: "Write docs/README.md"
Task T017: "Verify executable + install"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1 (T008–T010)
4. **STOP and VALIDATE**: Run `sprout-parallel create feature/test-branch` — confirm worktree created at correct path
5. Working `create` command is a usable MVP

### Incremental Delivery

1. Setup + Foundational → script skeleton with `--help`
2. US1 (create) → validate independently → usable MVP
3. US2 (delete) → validate independently → full create/delete lifecycle
4. US3 (list) → validate independently → complete tool
5. Polish → docs and install verification

---

## Notes

- All command implementations go into the single `sprout-parallel` file — no separate modules
- [P] tasks = operate on different files or are order-independent
- Each user story adds exactly one `cmd_X()` function; the main dispatcher in T003 references them all
- Commit after each phase checkpoint
- Use `git -C <path>` throughout — never `cd` in the script
- `resolve_project()` (T006) is the most complex foundational task; validate it manually before building US1
