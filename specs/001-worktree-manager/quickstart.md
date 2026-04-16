# Quickstart: sprout-parallel

**Phase**: 1 | **Date**: 2026-03-31 | **Branch**: `001-worktree-manager`

---

## What Is This?

`sprout-parallel` is a CLI tool for managing git worktrees across your projects. It lets you create, delete, and list parallel working directories so you can work on multiple branches simultaneously without stashing or switching branches.

---

## Prerequisites

- `git` 2.17 or later
- bash or zsh shell
- Projects located under a common root directory (default: `/Users/mehdi/projects`)

---

## Installation

```bash
# Clone or navigate to this repo
cd /Users/mehdi/tools/sprout-parallel

# Run the install helper — symlinks sprout-parallel to ~/.local/bin
bash install.sh

# Verify
sprout-parallel --help
```

If `~/.local/bin` is not on your PATH, add this to your `~/.zshrc` or `~/.bashrc`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## Configuration

By default, `sprout-parallel` looks for projects under `/Users/mehdi/projects`.

To use a different root, set the `SPROUT_PROJECTS_ROOT` environment variable:

```bash
export SPROUT_PROJECTS_ROOT="/path/to/your/projects"
```

Add this to your shell profile to make it permanent.

---

## Usage

### Create a worktree

```bash
# From inside a project directory — branch from main
sprout-parallel create feature/my-new-thing

# From inside a project directory — branch from a specific base
sprout-parallel create hotfix/urgent --from production

# From any directory — specify the project explicitly
sprout-parallel create feature/my-new-thing --project scooda
```

The new worktree is created at:
```
/Users/mehdi/projects/<project>-worktrees/<branch-folder>/
```

For example: `/Users/mehdi/projects/scooda-worktrees/feature-my-new-thing/`

### Delete a worktree

```bash
# Delete a clean worktree
sprout-parallel delete feature/my-new-thing

# Delete a worktree with uncommitted changes
sprout-parallel delete feature/my-new-thing --force

# Specify project explicitly
sprout-parallel delete feature/my-new-thing --project scooda
```

### List worktrees

```bash
# From inside a project
sprout-parallel list

# Specify project explicitly
sprout-parallel list --project scooda
```

### Get help

```bash
sprout-parallel help
sprout-parallel help create
sprout-parallel help delete
sprout-parallel help list
```

---

## Typical Workflow

```bash
# 1. Start a new feature
cd /Users/mehdi/projects/scooda
sprout-parallel create feature/user-profile

# 2. Open the worktree in your editor
code /Users/mehdi/projects/scooda-worktrees/feature-user-profile

# 3. Work in parallel — your main worktree is untouched

# 4. Check what worktrees you have open
sprout-parallel list

# 5. When done, clean up
sprout-parallel delete feature/user-profile
```

---

## Directory Layout

```
/Users/mehdi/projects/
├── scooda/                        ← main working tree (branch: main)
├── scooda-worktrees/
│   ├── feature-user-profile/      ← worktree (branch: feature/user-profile)
│   └── fix-login-bug/             ← worktree (branch: fix/login-bug)
├── prayercal/
├── prayercal-worktrees/
│   └── feature-reminders/
└── ...
```
