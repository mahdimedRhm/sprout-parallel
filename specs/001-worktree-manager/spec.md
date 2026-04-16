# Feature Specification: Worktree Manager CLI (sprout-parallel)

**Feature Branch**: `001-worktree-manager`
**Created**: 2026-03-31
**Status**: Draft
**Input**: User description: "Let's make a script to manage worktrees in my git projects. - what i need is a way to create a work tree and delete a work tree. - what i also need is that each worktree should be on a separate folder. - most of my projects are in /Users/mehdi/projects so have a look at them to see if how would you do it - the script should be run from everywhere and it should have a documentation - app is called sprout-parallel"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a Worktree (Priority: P1)

A developer working on a project (e.g., `scooda` at `/Users/mehdi/projects/scooda`) wants to open a parallel branch in a separate folder without touching their current working tree. They run `sprout-parallel create <branch-name>` from any directory, and a new dedicated folder is created with the branch checked out.

**Why this priority**: This is the core capability the tool is built around. Without the ability to create a worktree, the tool has no value.

**Independent Test**: Can be fully tested by running `sprout-parallel create <branch-name>` and verifying the new directory exists and `git worktree list` shows the new entry.

**Acceptance Scenarios**:

1. **Given** a user is inside a valid git project directory, **When** they run `sprout-parallel create <branch-name>`, **Then** a new branch is created from `main` and a new folder is created at `<projects-root>/<project>-worktrees/<branch-name>` with the branch checked out, and `git worktree list` shows the new entry.
2. **Given** a user wants to branch from a non-default base, **When** they run `sprout-parallel create <branch-name> --from <base-branch>`, **Then** the new branch is created from `<base-branch>` and the worktree is set up accordingly.
3. **Given** a user is outside any git project, **When** they run `sprout-parallel create <branch-name> --project <project-name>`, **Then** the tool resolves the project from the known projects root and creates the worktree.
4. **Given** the requested branch already exists in the repository (as a worktree or otherwise), **When** the user runs `sprout-parallel create <branch-name>`, **Then** the tool displays a clear error and does not create a branch or worktree.

---

### User Story 2 - Delete a Worktree (Priority: P2)

A developer has finished working on a parallel branch and wants to clean up the worktree folder. They run `sprout-parallel delete <branch-name>` and the worktree folder and its git registration are removed cleanly.

**Why this priority**: Cleanup is essential to avoid accumulating stale folders and orphaned worktree registrations. Without delete, the tool leaves behind clutter.

**Independent Test**: Can be fully tested by creating a worktree, then running `sprout-parallel delete <branch-name>`, and verifying the folder is gone and `git worktree list` no longer shows the entry.

**Acceptance Scenarios**:

1. **Given** a worktree exists for `<branch-name>`, **When** the user runs `sprout-parallel delete <branch-name>`, **Then** the worktree directory is removed and the worktree entry is pruned from git.
2. **Given** the worktree has uncommitted changes, **When** the user runs `sprout-parallel delete <branch-name>`, **Then** the tool warns the user about uncommitted changes and requires a `--force` flag to proceed.
3. **Given** the specified branch name has no associated worktree, **When** the user runs `sprout-parallel delete <branch-name>`, **Then** the tool displays a clear "not found" error.

---

### User Story 3 - List Worktrees (Priority: P3)

A developer wants to see all currently active worktrees for a project at a glance — their branch names, folder paths, and status (clean or dirty).

**Why this priority**: Discoverability helps manage multiple parallel workstreams. Without listing, the user must run raw git commands to orient themselves.

**Independent Test**: Can be tested independently by running `sprout-parallel list` inside a project with existing worktrees and verifying the output matches the actual worktree state.

**Acceptance Scenarios**:

1. **Given** a project has multiple worktrees, **When** the user runs `sprout-parallel list`, **Then** all worktrees are shown with branch name, path, and dirty/clean status.
2. **Given** a project has no extra worktrees (only the main working tree), **When** the user runs `sprout-parallel list`, **Then** the tool outputs a message indicating no parallel worktrees exist.

---

### Edge Cases

- What happens when the worktrees directory does not yet exist (first-time use for a project)?
- What happens when the target project is not a git repository?
- How does the tool handle branch names with slashes (e.g., `feature/my-thing`)?
- What happens if the underlying git command fails partway through creating a worktree?
- How does the tool behave if run inside a worktree itself rather than the main working tree?
- What happens if two projects share the same branch name and the user runs without specifying a project?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The tool MUST provide a `create` command that creates a new git branch (branching from `main` by default) and adds a new worktree for it in a dedicated folder separate from the main project directory. The command MUST accept an optional `--from <branch>` flag to specify a different base branch, and MUST error if the specified branch name already exists in the repository.
- **FR-002**: The tool MUST provide a `delete` command that removes a git worktree folder and cleans up its git registration.
- **FR-003**: Each worktree MUST be created in its own dedicated folder, isolated from all other worktrees and from the main working tree.
- **FR-004**: The tool MUST be executable from any directory on the system (installable to a location on the user's PATH).
- **FR-005**: The tool MUST accept a `--project <name>` option to target a specific project when run from outside a project directory, resolving projects from the configured projects root (defaulting to `/Users/mehdi/projects`, overridable via `SPROUT_PROJECTS_ROOT` environment variable).
- **FR-006**: The tool MUST auto-detect the current project when run from within a project directory, without requiring `--project`.
- **FR-007**: The tool MUST warn the user and require a `--force` flag before deleting a worktree that has uncommitted changes.
- **FR-008**: The tool MUST display clear error messages when a requested branch or worktree is not found, already exists, or the target is not a git repository.
- **FR-009**: The tool MUST provide built-in documentation accessible via `--help` and a `help` subcommand, describing all commands, options, and usage examples.
- **FR-010**: The tool MUST provide a `list` command showing all active worktrees for a project, including branch name, path, and change status.
- **FR-011**: Worktree folder names MUST be derived from the branch name in a predictable, filesystem-safe format (e.g., slashes replaced with dashes).

### Key Entities

- **Project**: A git repository located under `/Users/mehdi/projects`. Identified by its directory name and absolute path.
- **Worktree**: A parallel working directory linked to a specific branch within a project. Has a branch name, a folder path, and a change status (clean/dirty).
- **Branch**: A git branch associated with a worktree. Always a newly created branch — `create` errors if the branch name already exists in the repository.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can create a new worktree for any project in under 10 seconds from the moment the command is issued.
- **SC-002**: A developer can delete a worktree cleanly in under 5 seconds, with no orphaned folders or dangling git registrations remaining.
- **SC-003**: Running `sprout-parallel --help` or `sprout-parallel help` provides complete documentation for all commands and options, requiring no access to external resources.
- **SC-004**: The tool runs successfully from any working directory without requiring the user to navigate to the project root first.
- **SC-005**: 100% of worktrees created by the tool are placed in distinct, isolated folders — no two worktrees share a directory.
- **SC-006**: All error scenarios (project not found, branch already exists, dirty worktree) produce a human-readable message that clearly explains what went wrong and what to do next.

## Clarifications

### Session 2026-03-31

- Q: Should the projects root be hardcoded or configurable? → A: Configurable via environment variable (`SPROUT_PROJECTS_ROOT`), defaulting to `/Users/mehdi/projects`
- Q: Where should worktrees be stored? → A: Sibling directory under projects root: `<projects-root>/<project>-worktrees/<branch>` (e.g., `projects/scooda-worktrees/feature-one`)
- Q: Should `create` support existing branches or only new ones? → A: Always create a new branch; error if the branch already exists in the repository
- Q: What base should new branches use? → A: Default to `main`, with an optional `--from <branch>` flag to override

## Assumptions

- The primary projects root defaults to `/Users/mehdi/projects` and is overridable via the `SPROUT_PROJECTS_ROOT` environment variable; all managed projects are direct subdirectories of the configured root.
- Projects follow a standard git repository structure (each project directory contains a `.git` entry).
- The user has `git` installed and available on the system PATH.
- Worktrees are stored in a sibling directory adjacent to the main project folder, named `<project-name>-worktrees`, under the same projects root (e.g., `/Users/mehdi/projects/scooda-worktrees/feature-one`, `/Users/mehdi/projects/scooda-worktrees/feature-two`). This keeps worktrees grouped by project without nesting them inside the project directory.
- The tool targets macOS/Linux shell environments (bash/zsh) as the primary runtime, consistent with the user's platform.
- The `create` command always creates a new branch, branching from `main` by default. An optional `--from <branch>` flag allows specifying a different base. If the branch name already exists (locally or remotely), the command fails with a clear error.
- The `--force` flag is the mechanism for overriding safety guards (e.g., deleting a dirty worktree).
