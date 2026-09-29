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

# ─── create records sproutBase ────────────────────────────────────────────────────────────

"$SP" create feature/dev --project alpha --from develop --no-setup > /dev/null
assert_eq "$(git -C "$ROOT/alpha" config --get branch.feature/dev.sproutBase || true)" "develop" \
  "create stores base in git config"

"$SP" status --json > "$OUT"
assert_eq "$(q "W('feature-dev')['base']")" "develop" "status reports recorded base"
assert_eq "$(q "(W('feature-dev')['ahead'], W('feature-dev')['behind'])")" "(0, 0)" "sync against recorded base"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$FAILS test(s) failed"
  exit 1
fi
