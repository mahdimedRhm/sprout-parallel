#!/usr/bin/env bash
# Tests for `sprout-parallel db create|refresh|drop`. Run: bash tests/db_test.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SP="$REPO/sprout-parallel"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export SPROUT_PROJECTS_ROOT="$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Stub mysql: records every call; `SELECT COUNT` answers from $ROOT/tables;
# CREATE fails while $ROOT/fail exists; import mode (no -e) records stdin.
STUBS="$ROOT/stubs"
CALLS="$ROOT/calls.log"
mkdir "$STUBS"
: > "$CALLS"
cat > "$STUBS/mysql" <<STUB
#!/bin/sh
echo "mysql \$* pwd=\$MYSQL_PWD" >> "$CALLS"
case "\$*" in
  *"SELECT COUNT"*) cat "$ROOT/tables" 2>/dev/null || echo 0 ;;
  *"CREATE DATABASE"*)
    if [ -f "$ROOT/fail" ]; then echo "ERROR 1044: Access denied"; exit 1; fi ;;
  *" -e "*) ;;
  *) echo "import: \$(cat)" >> "$CALLS" ;;
esac
exit 0
STUB
cat > "$STUBS/mysqldump" <<STUB
#!/bin/sh
for last; do :; done
echo "DUMP OF \$last"
STUB
chmod +x "$STUBS"/*
export PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin"

FAILS=0

assert_eq() {
  if [[ "$1" == "$2" ]]; then echo "ok   - $3"; else echo "FAIL - $3: expected [$2], got [$1]"; FAILS=$((FAILS + 1)); fi
}

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then echo "ok   - $3"; else
    echo "FAIL - $3: [$2] not found in:"; echo "$1" | sed 's/^/       /'; FAILS=$((FAILS + 1)); fi
}

WT="$ROOT/eta-worktrees/feature-a"
env_of() { grep "^$1=" "$WT/.env" | head -1 | cut -d= -f2-; }

mkdir "$ROOT/eta"
git -C "$ROOT/eta" init -q -b main
git -C "$ROOT/eta" commit -q --allow-empty -m init
printf '.env\n' > "$ROOT/eta/.git/info/exclude"
printf 'DB_CONNECTION=mysql\nDB_DATABASE=eta\nDB_USERNAME="root"\nDB_PASSWORD="pw"\n' > "$ROOT/eta/.env"
"$SP" create feature/a --project eta --no-setup > /dev/null 2>&1
# As if setup had failed: DB_DATABASE cleared, marker set, no DB_USERNAME
printf 'DB_CONNECTION=mysql\nDB_DATABASE=\nSPROUT_DB_FAILED=1\n' > "$WT/.env"

# ─── create ───────────────────────────────────────────────────────────────────

rc=0; out="$("$SP" db create feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "0" "create exits 0"
assert_contains "$(cat "$CALLS")" 'CREATE DATABASE IF NOT EXISTS `eta_feature_a`' "create targets <main>_<folder>"
assert_contains "$(cat "$CALLS")" "import: DUMP OF eta" "create clones main into it"
assert_eq "$(env_of DB_DATABASE)" "eta_feature_a" "create repairs an emptied DB_DATABASE"
assert_eq "$(env_of SPROUT_DB_FAILED)" "" "create clears the failure marker"
assert_contains "$(cat "$CALLS")" "-uroot " "credentials fall back to the main project's .env, unquoted user"
assert_contains "$(cat "$CALLS")" "pwd=pw" "unquoted password reaches mysql"

: > "$CALLS"; echo 5 > "$ROOT/tables"
out="$("$SP" db create feature/a --project eta 2>&1)"
assert_contains "$out" "already exists" "create skips cloning a database that has tables"
assert_eq "$(grep -c 'import:' "$CALLS" || true)" "0" "no clone when it already has tables"
rm "$ROOT/tables"

# ─── refresh ──────────────────────────────────────────────────────────────────

: > "$CALLS"
rc=0; "$SP" db refresh feature-a --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "refresh exits 0 (folder name accepted too)"
order="$(grep -oE 'DROP DATABASE|CREATE DATABASE|import:' "$CALLS" | tr '\n' ' ')"
assert_eq "$order" "DROP DATABASE CREATE DATABASE import: " "refresh drops, creates, then clones"
assert_contains "$(cat "$CALLS")" 'DROP DATABASE IF EXISTS `eta_feature_a`' "refresh drops only the worktree database"

: > "$CALLS"; touch "$ROOT/fail"
rc=0; out="$("$SP" db refresh feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "2" "a MySQL failure exits 2"
assert_contains "$(echo "$out" | tail -1)" "Error:" "the failure ends with an Error: line"
assert_eq "$(env_of DB_DATABASE)" "eta_feature_a" "failed refresh leaves .env alone"
rm "$ROOT/fail"

# A failing mysqldump: exit 2, .env untouched, the main database never dropped
cat > "$STUBS/mysqldump" <<STUB
#!/bin/sh
echo "mysqldump: Got error: 1045" >&2
exit 2
STUB
: > "$CALLS"; before="$(cat "$WT/.env")"
rc=0; out="$("$SP" db refresh feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "2" "a failing mysqldump exits 2"
assert_eq "$(cat "$WT/.env")" "$before" "a failed clone leaves .env untouched"
assert_eq "$(grep -c 'DROP DATABASE IF EXISTS `eta`;' "$CALLS" || true)" "0" "a failed clone never drops the main database"
cat > "$STUBS/mysqldump" <<STUB
#!/bin/sh
for last; do :; done
echo "DUMP OF \$last"
STUB

# A worktree .env that points at the main database: refresh only touches <main>_<folder>
sed -i '' 's|^DB_DATABASE=.*|DB_DATABASE=eta|' "$WT/.env"
: > "$CALLS"
rc=0; "$SP" db refresh feature/a --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "refresh with .env pointing at the main DB exits 0"
assert_eq "$(grep -c 'DROP DATABASE IF EXISTS `eta`;' "$CALLS" || true)" "0" "…never drops the main database"
assert_eq "$(grep -c 'CREATE DATABASE `eta`' "$CALLS" || true)" "0" "…never creates over the main database"
assert_contains "$(cat "$CALLS")" 'DROP DATABASE IF EXISTS `eta_feature_a`' "…drops only the worktree database"
assert_eq "$(env_of DB_DATABASE)" "eta_feature_a" "…and .env ends up pointing at the worktree database"

# ─── drop ─────────────────────────────────────────────────────────────────────

: > "$CALLS"
rc=0; "$SP" db drop feature/a --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "drop exits 0"
assert_contains "$(cat "$CALLS")" 'DROP DATABASE IF EXISTS `eta_feature_a`' "drop drops the worktree database"
assert_eq "$(grep -c 'DROP DATABASE IF EXISTS `eta`;' "$CALLS" || true)" "0" "drop never touches the main database"
assert_eq "$(env_of DB_DATABASE)" "" "drop clears DB_DATABASE"

# ─── guards and errors ────────────────────────────────────────────────────────

printf 'DB_CONNECTION=mysql\nDB_USERNAME=root\n' > "$ROOT/eta/.env"
rc=0; out="$("$SP" db create feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "1" "no main DB_DATABASE → exit 1"
assert_contains "$out" "Error:" "…with an Error: line"
printf 'DB_CONNECTION=mysql\nDB_DATABASE=eta\nDB_USERNAME="root"\nDB_PASSWORD="pw"\n' > "$ROOT/eta/.env"

rc=0; "$SP" db explode feature/a --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "1" "unknown action exits 1"
rc=0; "$SP" db create feature/nope --project eta > /dev/null 2>&1 || rc=$?
assert_eq "$rc" "1" "unknown worktree exits 1"

mv "$STUBS/mysql" "$ROOT/mysql.off"
rc=0; out="$("$SP" db create feature/a --project eta 2>&1)" || rc=$?
assert_eq "$rc" "1" "missing mysql exits 1"
assert_contains "$out" "mysql is not installed" "…and says so"
mv "$ROOT/mysql.off" "$STUBS/mysql"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
if [[ "$FAILS" -eq 0 ]]; then echo "all tests passed"; else echo "$FAILS test(s) failed"; exit 1; fi
