#!/usr/bin/env bash
# Tests for `sprout-parallel clear`. Run: bash tests/clear_test.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SP="$REPO/sprout-parallel"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export SPROUT_PROJECTS_ROOT="$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Stub mysql/redis-cli so database cleanup is observable and touches nothing real
STUBS="$ROOT/stubs"
CALLS="$ROOT/calls.log"
mkdir "$STUBS"
touch "$CALLS"
printf '#!/bin/sh\necho "mysql $*" >> "%s"\n' "$CALLS" > "$STUBS/mysql"
printf '#!/bin/sh\necho "redis-cli $*" >> "%s"\n' "$CALLS" > "$STUBS/redis-cli"
chmod +x "$STUBS/mysql" "$STUBS/redis-cli"
export PATH="$STUBS:$PATH"

FAILS=0

assert_eq() {
  if [[ "$1" == "$2" ]]; then
    echo "ok   - $3"
  else
    echo "FAIL - $3: expected [$2], got [$1]"
    FAILS=$((FAILS + 1))
  fi
}

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "ok   - $3"
  else
    echo "FAIL - $3: [$2] not found in output:"
    echo "$1" | sed 's/^/       /'
    FAILS=$((FAILS + 1))
  fi
}

exists() {
  if [[ -d "$1" ]]; then echo yes; else echo no; fi
}

# ─── Fixture ──────────────────────────────────────────────────────────────────

mkdir "$ROOT/beta"
git -C "$ROOT/beta" init -q -b main
git -C "$ROOT/beta" commit -q --allow-empty -m init

WT="$ROOT/beta-worktrees"
for b in feature/one feature/two feature/three; do
  "$SP" create "$b" --project beta --no-setup > /dev/null 2>&1
done
printf 'DB_DATABASE=beta_one\nDB_USERNAME=root\n' > "$WT/feature-one/.env"
# .env is untracked, which makes feature-one dirty too; ignore it like real projects do
printf '.env\n' > "$ROOT/beta/.git/info/exclude"
echo x > "$WT/feature-two/dirty.txt"

# ─── clear without --force skips dirty worktrees ──────────────────────────────

rc=0
out="$("$SP" clear --project beta 2>&1)" || rc=$?
assert_eq "$rc" "0" "clear exits 0 when nothing failed"
assert_contains "$out" "Skipped 'feature-two' (uncommitted changes" "dirty worktree skipped with a reason"
assert_contains "$out" "cleared 2 · skipped 1 · failed 0" "summary line"
assert_eq "$(exists "$WT/feature-one")" "no" "clean worktree one removed"
assert_eq "$(exists "$WT/feature-three")" "no" "clean worktree three removed"
assert_eq "$(exists "$WT/feature-two")" "yes" "dirty worktree kept"
assert_contains "$(cat "$CALLS")" 'DROP DATABASE IF EXISTS `beta_one`' "database of cleared worktree dropped"
assert_eq "$(git -C "$ROOT/beta" rev-parse --verify -q feature/one > /dev/null && echo kept)" "kept" "branches are kept"

# ─── --force --keep-db clears dirty ones and leaves databases alone ───────────

: > "$CALLS"
printf 'DB_DATABASE=beta_two\nDB_USERNAME=root\n' > "$WT/feature-two/.env"
rc=0
out="$("$SP" clear --project beta --force --keep-db 2>&1)" || rc=$?
assert_eq "$rc" "0" "forced clear exits 0"
assert_contains "$out" "cleared 1 · skipped 0 · failed 0" "forced summary"
assert_eq "$(exists "$WT/feature-two")" "no" "--force removes dirty worktree"
assert_eq "$(cat "$CALLS")" "" "--keep-db leaves databases alone"

# ─── nothing to clear ─────────────────────────────────────────────────────────

rc=0
out="$("$SP" clear --project beta 2>&1)" || rc=$?
assert_eq "$rc" "0" "empty clear exits 0"
assert_contains "$out" "No worktrees to clear in project 'beta'." "empty clear message"

# ─── a failing delete doesn't stop the rest, and makes clear exit 1 ───────────

"$SP" create feature/locked --project beta --no-setup > /dev/null 2>&1
"$SP" create feature/fine --project beta --no-setup > /dev/null 2>&1
git -C "$ROOT/beta" worktree lock "$WT/feature-locked"
rc=0
out="$("$SP" clear --project beta 2>&1)" || rc=$?
assert_eq "$rc" "1" "clear exits 1 when a delete fails"
assert_contains "$out" "cleared 1 · skipped 0 · failed 1" "failure counted"
assert_contains "$out" "Error: Failed to delete 1 worktree(s) in 'beta'." "final Error: line"
assert_eq "$(exists "$WT/feature-fine")" "no" "other worktrees still cleared"
assert_eq "$(exists "$WT/feature-locked")" "yes" "failed worktree left in place"

# ─── argument handling ────────────────────────────────────────────────────────

rc=0
"$SP" clear --project beta --bogus > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "1" "unknown option exits 1"
rc=0
"$SP" clear --project nope > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "1" "unknown project exits 1"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$FAILS test(s) failed"
  exit 1
fi
