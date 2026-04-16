# CLI Contract: sprout-parallel

**Phase**: 1 | **Date**: 2026-03-31 | **Branch**: `001-worktree-manager`

---

## Interface Type: Command-Line Tool

`sprout-parallel` exposes all functionality through a subcommand-based CLI. This document is the authoritative contract for command signatures, option semantics, exit codes, and output formats.

---

## Global Conventions

- **Stdout**: Human-readable output (success messages, listings)
- **Stderr**: Error messages and warnings
- **Exit codes**: `0` = success, `1` = user error (bad args, not found, already exists), `2` = internal/git error

---

## Commands

### `sprout-parallel create <branch-name> [options]`

Creates a new git branch and a new worktree for it.

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `<branch-name>` | Yes | Name of the new branch to create. Must not already exist in the repo. |

**Options**:

| Flag | Default | Description |
|------|---------|-------------|
| `--project <name>` | Auto-detected | Name of the project under `$SPROUT_PROJECTS_ROOT`. Required when not inside a project directory. |
| `--from <base-branch>` | `main` | Branch to use as the base for the new branch. |

**Output (stdout on success)**:
```
Created worktree for branch 'feature-my-thing'
  Project : scooda
  Branch  : feature/my-thing
  Path    : /Users/mehdi/projects/scooda-worktrees/feature-my-thing
  Base    : main
```

**Error cases**:

| Condition | Stderr message | Exit code |
|-----------|---------------|-----------|
| Branch already exists | `Error: Branch 'X' already exists in 'Y'. sprout-parallel only creates new branches.` | 1 |
| Project not found | `Error: Project 'X' not found under '$SPROUT_PROJECTS_ROOT'.` | 1 |
| Not in a project directory, no --project | `Error: Not inside a project directory. Use --project <name> to specify one.` | 1 |
| Base branch not found | `Error: Base branch 'X' does not exist in project 'Y'.` | 1 |
| git command fails | `Error: git worktree add failed. Run with --verbose for details.` | 2 |

---

### `sprout-parallel delete <branch-name> [options]`

Removes a worktree folder and its git registration.

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `<branch-name>` | Yes | Name of the branch whose worktree should be deleted. |

**Options**:

| Flag | Default | Description |
|------|---------|-------------|
| `--project <name>` | Auto-detected | Target project name. |
| `--force` | off | Required when the worktree has uncommitted changes. |

**Output (stdout on success)**:
```
Deleted worktree 'feature-my-thing'
  Project : scooda
  Path    : /Users/mehdi/projects/scooda-worktrees/feature-my-thing
```

**Error cases**:

| Condition | Stderr message | Exit code |
|-----------|---------------|-----------|
| Worktree not found | `Error: No worktree found for branch 'X' in project 'Y'.` | 1 |
| Dirty worktree, no --force | `Error: Worktree 'X' has uncommitted changes. Use --force to delete anyway.` | 1 |
| Project not found | `Error: Project 'X' not found under '$SPROUT_PROJECTS_ROOT'.` | 1 |
| git command fails | `Error: git worktree remove failed.` | 2 |

---

### `sprout-parallel list [options]`

Lists all worktrees for a project.

**Options**:

| Flag | Default | Description |
|------|---------|-------------|
| `--project <name>` | Auto-detected | Target project name. |

**Output (stdout)**:

When worktrees exist:
```
Worktrees for project: scooda
  /Users/mehdi/projects/scooda-worktrees/feature-my-thing  [feature/my-thing]  clean
  /Users/mehdi/projects/scooda-worktrees/fix-TICKET-123    [fix/TICKET-123]    dirty
```

When no worktrees exist:
```
No parallel worktrees found for project: scooda
```

**Error cases**:

| Condition | Stderr message | Exit code |
|-----------|---------------|-----------|
| Project not found | `Error: Project 'X' not found under '$SPROUT_PROJECTS_ROOT'.` | 1 |

---

### `sprout-parallel help [<command>]`

Displays help text.

**Variants**:
- `sprout-parallel help` — full usage overview
- `sprout-parallel help create` — help for the `create` command
- `sprout-parallel --help` / `sprout-parallel -h` — alias for `help`

**Output**: Written to stdout. Exit code: `0`.

---

## Exit Code Summary

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | User error (bad arguments, entity not found, pre-condition not met) |
| `2` | Internal / git failure |
