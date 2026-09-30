# sprout-parallel

A CLI tool for managing git worktrees across your projects. Create, delete, and list parallel working directories so you can work on multiple branches simultaneously — without stashing or switching.

---

## Installation

```bash
# From the sprout-parallel repo directory
bash install.sh
```

This symlinks `sprout-parallel` to `~/.local/bin/sprout-parallel` (falls back to `/usr/local/bin` if `~/.local/bin` doesn't exist).

**If `~/.local/bin` is not on your PATH**, add this to your `~/.zshrc` or `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Verify the install:**

```bash
sprout-parallel --help
```

### Requirements

- `git` 2.17 or later
- bash or zsh

---

## Configuration

By default `sprout-parallel` looks for projects under `/Users/mehdi/projects`.

Override with the `SPROUT_PROJECTS_ROOT` environment variable:

```bash
export SPROUT_PROJECTS_ROOT="/path/to/your/projects"
```

Add to your shell profile to make it permanent.

---

## Commands

### `create` — Create a worktree

```
sprout-parallel create <branch-name> [--project <name>] [--from <base>]
```

Creates a new git branch and a new worktree folder for it.

| Argument / Flag | Required | Default | Description |
|-----------------|----------|---------|-------------|
| `<branch-name>` | Yes | — | New branch name. Must not already exist. |
| `--project <name>` | No | Auto-detected | Project name under `$SPROUT_PROJECTS_ROOT`. |
| `--from <base>` | No | `main` | Base branch to create the new branch from. |

**Examples:**

```bash
# From inside a project directory — branch from main
sprout-parallel create feature/my-thing

# Branch from a different base
sprout-parallel create hotfix/urgent --from production

# From anywhere — specify the project explicitly
sprout-parallel create feature/my-thing --project scooda
```

**Output:**

```
Created worktree for branch 'feature-my-thing'
  Project : scooda
  Branch  : feature/my-thing
  Path    : /Users/mehdi/projects/scooda-worktrees/feature-my-thing
  Base    : main
```

---

### `delete` — Delete a worktree

```
sprout-parallel delete <branch-name> [--project <name>] [--force]
```

Removes the worktree folder and its git registration.

| Argument / Flag | Required | Default | Description |
|-----------------|----------|---------|-------------|
| `<branch-name>` | Yes | — | Branch whose worktree to delete. |
| `--project <name>` | No | Auto-detected | Project name. |
| `--force` | No | off | Required when the worktree has uncommitted changes. |

**Examples:**

```bash
sprout-parallel delete feature/my-thing
sprout-parallel delete feature/my-thing --force
sprout-parallel delete feature/my-thing --project scooda
```

**Output:**

```
Deleted worktree 'feature-my-thing'
  Project : scooda
  Path    : /Users/mehdi/projects/scooda-worktrees/feature-my-thing
```

---

### `clear` — Delete every worktree of a project

```
sprout-parallel clear [--project <name>] [--force] [--keep-db]
```

Runs `delete` on each of the project's worktrees. Worktrees with uncommitted
changes are skipped unless `--force` is given, and a failing delete doesn't stop
the others. Branches are kept.

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--project <name>` | No | Auto-detected | Project name. |
| `--force` | No | off | Also delete worktrees with uncommitted changes. |
| `--keep-db` | No | off | Don't drop databases or clear Redis keys. |

**Output:**

```
Skipped 'feature-wip' (uncommitted changes — use --force to delete it)
Deleted worktree 'feature-my-thing'
  ...

cleared 1 · skipped 1 · failed 0
```

Exits 1 if any delete failed.

---

### `list` — List worktrees

```
sprout-parallel list [--project <name>]
```

Shows all parallel worktrees for a project with branch name, path, and clean/dirty status.

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--project <name>` | No | Auto-detected | Project name. |

**Examples:**

```bash
sprout-parallel list
sprout-parallel list --project scooda
```

**Output:**

```
Worktrees for project: scooda
  /Users/mehdi/projects/scooda-worktrees/feature-my-thing  [feature/my-thing]  clean
  /Users/mehdi/projects/scooda-worktrees/fix-TICKET-123    [fix/TICKET-123]    dirty
```

When no worktrees exist:

```
No parallel worktrees found for project: scooda
```

---

### `help` — Show help

```
sprout-parallel help [create|delete|list]
sprout-parallel --help
```

---

## Directory Layout

```
/Users/mehdi/projects/
├── scooda/                              ← main working tree (branch: main)
├── scooda-worktrees/
│   ├── feature-my-thing/               ← worktree (branch: feature/my-thing)
│   └── fix-TICKET-123/                 ← worktree (branch: fix/TICKET-123)
├── prayercal/
├── prayercal-worktrees/
│   └── feature-reminders/
└── ...
```

Each project gets a `<project>-worktrees/` sibling directory. Each branch gets its own subdirectory inside it, named by converting `/` → `-` in the branch name.

---

## Typical Workflow

```bash
# 1. Start a new feature
cd /Users/mehdi/projects/scooda
sprout-parallel create feature/user-profile

# 2. Open the worktree in your editor
code /Users/mehdi/projects/scooda-worktrees/feature-user-profile

# 3. Work in parallel — your main worktree is untouched

# 4. Check what worktrees are open
sprout-parallel list

# 5. When done, clean up
sprout-parallel delete feature/user-profile
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | User error (bad arguments, entity not found, pre-condition not met) |
| `2` | Internal / git failure |

---

## Sprout menu bar app

A terminal-styled macOS menu bar app for viewing and managing worktrees across
every project under `$SPROUT_PROJECTS_ROOT`. It drives the `sprout-parallel`
CLI (`status --json`, `create`, `delete`), so both always agree.

Each new worktree gets its own `php artisan serve` port (`SERVER_PORT`, from 8001)
and, when the main project is linked in Herd, its own Herd site
(`https://<project>-<branch>.test`); `delete` unlinks it. Sprout shows both URLs
and whether the serve port is running.

Click the leaf in the menu bar to show or hide the Sprout window. Drag its
background to move it and its edges to resize it; it remembers where you left it.

### Terminals

Every worktree has its own terminal tabs below its details, running your login
shell (`zsh -l`, so `~/.zshrc` applies) in the worktree folder. Switching
worktree switches terminals; the others keep running. Drag the divider to
resize, and use the hide/show button to collapse it. ``⌃` `` moves focus
between the list and the terminal (opening the terminal if it is hidden). While the terminal has focus every key goes to the shell. Terminals
of deleted worktrees are closed, and quitting Sprout warns if a command is still
running.

### Install

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
bash install.sh          # the app runs sprout-parallel via `zsh -lic`, so PATH set in ~/.zshrc applies
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
| `o` / `⇧O` | open the Herd URL / the `php artisan serve` URL |
| `n` | new worktree in the selected project |
| `⌫` | delete the selected worktree |
| `⇧X` | clear all worktrees of the selected project |
| ``⌃` `` | focus the terminal / back to the list |
| `⌘T` / `⌘⇧W` | new terminal tab / close tab |
| `r` | refresh |
| `⌘⏎` / `esc` | confirm / back (in forms) |
| `esc` / `⌘W` | hide the window (in the list) |

### Development

```bash
cd app
swift run SproutCoreChecks   # logic checks (no Xcode needed)
swift run SproutTerminalChecks # terminal sessions + live zsh checks
swift run SproutSnapshots    # renders views to app/build/snapshots/*.png
bash ../tests/status_test.sh # status --json tests
bash ../tests/clear_test.sh  # clear tests
bash ../tests/serve_test.sh  # port + Herd link tests
```
