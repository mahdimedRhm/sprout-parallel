# Data Model: Worktree Manager CLI (sprout-parallel)

**Phase**: 1 | **Date**: 2026-03-31 | **Branch**: `001-worktree-manager`

---

## Overview

`sprout-parallel` has no persistent data store. All state lives in the filesystem and git metadata. The "data model" describes the logical entities the tool reads and writes.

---

## Entities

### ProjectsRoot

The root directory that contains all managed projects.

| Attribute | Type | Source | Notes |
|-----------|------|--------|-------|
| `path` | absolute path | `$SPROUT_PROJECTS_ROOT` env var | Defaults to `/Users/mehdi/projects` |

**Validation**: Must exist and be a directory. Checked at startup when a project lookup is needed.

---

### Project

A git repository managed by the tool.

| Attribute | Type | Derivation | Notes |
|-----------|------|-----------|-------|
| `name` | string | Directory name under `ProjectsRoot.path` | e.g., `scooda` |
| `path` | absolute path | `ProjectsRoot.path + "/" + name` | e.g., `/Users/mehdi/projects/scooda` |
| `worktrees_dir` | absolute path | `ProjectsRoot.path + "/" + name + "-worktrees"` | e.g., `/Users/mehdi/projects/scooda-worktrees` |

**Validation**:
- `path` must contain a `.git` entry (directory or file for submodules)
- `name` must not contain path separators

**Identity**: Identified by `name` (unique within `ProjectsRoot`). When auto-detecting, the project `name` is the basename of the git root found by walking up from `$PWD`.

---

### Worktree

A parallel working directory linked to a branch within a project.

| Attribute | Type | Derivation | Notes |
|-----------|------|-----------|-------|
| `branch_name` | string | User-supplied to `create` / `delete` commands | e.g., `feature/my-thing` |
| `folder_name` | string | `safe_name(branch_name)` — `/` → `-`, strip leading/trailing dashes | e.g., `feature-my-thing` |
| `path` | absolute path | `Project.worktrees_dir + "/" + folder_name` | e.g., `.../scooda-worktrees/feature-my-thing` |
| `status` | enum: `clean` \| `dirty` | `git status --porcelain` on `path` (non-empty output = dirty) | Read at `list` time |
| `base_branch` | string | `--from` flag, defaults to `main` | Used only at creation time |

**Validation**:
- `branch_name` must not already exist in the repository (`git rev-parse --verify refs/heads/<name>` must fail)
- `path` must not already exist as a directory at `create` time
- `path` must exist as a directory at `delete` time

**State transitions**:
```
[does not exist]
      │ create
      ▼
  [exists, clean]
      │ user edits files
      ▼
  [exists, dirty]
      │ delete --force (or clean up first, then delete)
      ▼
[does not exist]
```

---

### Branch

A git branch associated with a worktree. Always newly created by `sprout-parallel create`.

| Attribute | Type | Notes |
|-----------|------|-------|
| `name` | string | Same as `Worktree.branch_name` |
| `base` | string | `Worktree.base_branch` — the branch point |

**Constraint**: `sprout-parallel` never checks out existing branches. A branch must not exist before `create` is called.

---

## Naming Transformation: `safe_name()`

Converts a git branch name to a filesystem-safe folder name.

| Input | Output |
|-------|--------|
| `feature/my-thing` | `feature-my-thing` |
| `fix/TICKET-123` | `fix-TICKET-123` |
| `my-branch` | `my-branch` |
| `/leading-slash` | `leading-slash` |

**Rule**: Replace all `/` with `-`, then strip any leading or trailing `-` characters.

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SPROUT_PROJECTS_ROOT` | `/Users/mehdi/projects` | Root directory containing all managed projects |
