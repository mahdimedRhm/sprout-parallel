# Implementation Plan: Worktree Manager CLI (sprout-parallel)

**Branch**: `001-worktree-manager` | **Date**: 2026-03-31 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-worktree-manager/spec.md`

## Summary

Build `sprout-parallel`, a bash CLI tool that wraps `git worktree` to let a developer create, delete, and list parallel worktrees for projects under a configurable root directory. Each worktree lands in a sibling `<project>-worktrees/<branch>` folder next to the main project. The tool is installable globally and runs from any directory.

## Technical Context

**Language/Version**: Bash (POSIX-compatible, targeting bash 3.2+ for macOS compatibility)
**Primary Dependencies**: `git` 2.17+ (for `git worktree remove`), standard POSIX utilities (`awk`, `sed`, `tr`)
**Storage**: Filesystem only — no config files or databases; `SPROUT_PROJECTS_ROOT` env var for configuration
**Testing**: [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System)
**Target Platform**: macOS / Linux (zsh/bash shell environments)
**Project Type**: CLI tool — single executable script
**Performance Goals**: Create worktree <10s, delete <5s (dominated by git operations, not script overhead)
**Constraints**: No external dependencies beyond `git`; works from any working directory; zero install friction
**Scale/Scope**: Personal developer tool; single user; projects count ~10–50

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution file is unpopulated (template placeholders only) — no active gates apply. Treating as no violations.

Post-design re-check: No new concerns introduced. Single-file bash script is the simplest viable implementation; no unnecessary abstractions added.

## Project Structure

### Documentation (this feature)

```text
specs/001-worktree-manager/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── cli-contract.md  # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
sprout-parallel          # Main executable script (single file, no extension)
install.sh               # Optional install helper (symlinks to ~/.local/bin)

tests/
└── sprout-parallel.bats # BATS test suite

docs/
└── README.md            # Full documentation (mirrors --help content)
```

**Structure Decision**: Single-file CLI. The entire tool is one bash script (`sprout-parallel`) placed at the repo root. This eliminates build steps, makes installation trivial (one symlink or copy), and keeps the codebase readable end-to-end. No `src/` directory is needed for a personal utility of this scope.

## Complexity Tracking

No constitution violations — table not applicable.
