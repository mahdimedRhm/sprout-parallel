#!/usr/bin/env bash
# Tests for the worktree database setup on create: a failed clone must not
# leave the worktree pointing at the main project's database.
# Run: bash tests/db_setup_test.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SP="$REPO/sprout-parallel"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export SPROUT_PROJECTS_ROOT="$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export PYTHONIOENCODING=utf-8

# Stubs: mysql fails CREATE DATABASE while $ROOT/deny exists; the rest are no-ops.
STUBS="$ROOT/stubs"
mkdir "$STUBS"
cat > "$STUBS/mysql" <<STUB
#!/bin/sh
case "\$*" in
  *"CREATE DATABASE"*)
    if [ -f "$ROOT/deny" ]; then
      echo "ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)"
      exit 1
    fi ;;
esac
# Import mode (no -e): swallow the piped dump
case "\$*" in *" -e "*) ;; *) cat > /dev/null ;; esac
exit 0
STUB
printf '#!/bin/sh\nexit 0\n' > "$STUBS/mysqldump"
printf '#!/bin/sh\nexit 0\n' > "$STUBS/redis-cli"
printf '#!/bin/sh\nexit 1\n' > "$STUBS/lsof"
chmod +x "$STUBS"/*
# A PATH with only system tools + stubs (no real mysql, herd, composer or npm)
BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$STUBS:$BASE_PATH"

FAILS=0
OUT="$ROOT/out.json"

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
    echo "FAIL - $3: [$2] not found in:"
    echo "$1" | sed 's/^/       /'
    FAILS=$((FAILS + 1))
  fi
}

env_of() {
  grep "^$2=" "$ROOT/eta-worktrees/$1/.env" | head -1 | cut -d= -f2-
}

q() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
W = lambda f: next(w for p in d['projects'] for w in p['worktrees'] if w['folder'] == f)
print($1)" "$OUT"
}

mkdir "$ROOT/eta"
git -C "$ROOT/eta" init -q -b main
git -C "$ROOT/eta" commit -q --allow-empty -m init
printf '.env\n' > "$ROOT/eta/.git/info/exclude"
printf 'DB_CONNECTION=mysql\nDB_DATABASE=eta\nDB_USERNAME=root\nDB_PASSWORD=secret\n' > "$ROOT/eta/.env"

# ─── CREATE DATABASE denied ───────────────────────────────────────────────────

touch "$ROOT/deny"
rc=0
out="$("$SP" create feature/denied --project eta 2>&1)" || rc=$?
assert_eq "$rc" "0" "create still succeeds when the database can't be made"
assert_eq "$(env_of feature-denied DB_DATABASE)" "" "DB_DATABASE is cleared, not left pointing at the main database"
assert_eq "$(env_of feature-denied SPROUT_DB_FAILED)" "1" "the failure is recorded in .env"
assert_contains "$out" "Warning: DATABASE NOT CREATED" "a prominent warning ends the output"
assert_contains "$out" "was 'eta'" "the warning names the main database it avoided"
assert_eq "$(echo "$out" | tail -2 | head -1 | cut -c1-30)" "Warning: DATABASE NOT CREATED:" "the warning comes last, not mid-log"

# ─── mysql not installed ──────────────────────────────────────────────────────

rm "$ROOT/deny"
mv "$STUBS/mysql" "$ROOT/mysql.off"
out="$("$SP" create feature/nomysql --project eta 2>&1)"
assert_eq "$(env_of feature-nomysql DB_DATABASE)" "" "no mysql: DB_DATABASE is cleared too"
assert_contains "$out" "Warning: DATABASE NOT CREATED" "no mysql: warning shown"
mv "$ROOT/mysql.off" "$STUBS/mysql"

# ─── success ──────────────────────────────────────────────────────────────────

out="$("$SP" create feature/ok --project eta 2>&1)"
assert_eq "$(env_of feature-ok DB_DATABASE)" "eta_feature_ok" "a created database is used"
assert_eq "$(env_of feature-ok SPROUT_DB_FAILED)" "" "no failure marker on success"
assert_eq "$(echo "$out" | grep -c 'DATABASE NOT CREATED' || true)" "0" "no warning on success"

# ─── status reports it ────────────────────────────────────────────────────────

"$SP" status --json > "$OUT"
assert_eq "$(q "W('feature-denied')['dbFailed']")" "True" "status: dbFailed for the failed worktree"
assert_eq "$(q "W('feature-denied')['mysqlDb']")" "None" "status: no mysqlDb for the failed worktree"
assert_eq "$(q "W('feature-ok')['dbFailed']")" "False" "status: dbFailed false on success"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$FAILS test(s) failed"
  exit 1
fi
