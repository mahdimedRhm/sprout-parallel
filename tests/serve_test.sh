#!/usr/bin/env bash
# Tests for worktree serving: ports, Herd links, and URL fields in status.
# Run: bash tests/serve_test.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SP="$REPO/sprout-parallel"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export SPROUT_PROJECTS_ROOT="$ROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export PYTHONIOENCODING=utf-8

# Stubs: herd (records calls, prints a links table), lsof (ports listed in
# $LISTENING are "listening"), and no-op mysql/redis-cli.
STUBS="$ROOT/stubs"
CALLS="$ROOT/herd.log"
LISTENING="$ROOT/listening"
mkdir "$STUBS"
: > "$CALLS"
: > "$LISTENING"
cat > "$STUBS/herd" <<STUB
#!/bin/sh
case "\$1" in
  links)
    echo "+------+-----+-----+------+-----+---+"
    echo "| Site | SSL | URL | Path | PHP |   |"
    echo "+------+-----+-----+------+-----+---+"
    echo "| gamma |  X  | https://gamma.test | $ROOT/gamma | 8.3 | 24 |"
    echo "|       |     |                    |             |     |    |"
    ;;
  tld) echo "test" ;;
  *) echo "\$* (in \$(pwd))" >> "$CALLS" ;;
esac
STUB
cat > "$STUBS/lsof" <<STUB
#!/bin/sh
for arg in "\$@"; do
  case "\$arg" in
    -iTCP:*) port="\${arg#-iTCP:}" ;;
  esac
done
grep -qx "\$port" "$LISTENING"
STUB
printf '#!/bin/sh\nexit 0\n' > "$STUBS/mysql"
printf '#!/bin/sh\nexit 0\n' > "$STUBS/redis-cli"
chmod +x "$STUBS"/*
export PATH="$STUBS:$PATH"

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
  grep "^$2=" "$ROOT/$1/.env" | head -1 | cut -d= -f2-
}

q() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
W = lambda f: next(w for p in d['projects'] for w in p['worktrees'] if w['folder'] == f)
print($1)" "$OUT"
}

new_project() {
  mkdir "$ROOT/$1"
  git -C "$ROOT/$1" init -q -b main
  git -C "$ROOT/$1" commit -q --allow-empty -m init
  printf '.env\n' > "$ROOT/$1/.git/info/exclude"
  printf 'APP_NAME=%s\nAPP_URL=http://%s.test\n' "$1" "$1" > "$ROOT/$1/.env"
}

new_project gamma   # linked in Herd, secure, PHP 8.3
new_project delta   # not linked in Herd

# ─── create: port + Herd link for a Herd-linked project ───────────────────────

"$SP" create feature/a --project gamma > /dev/null 2>&1
assert_eq "$(env_of gamma-worktrees/feature-a SERVER_PORT)" "8001" "first worktree gets port 8001"
assert_contains "$(cat "$CALLS")" "link gamma-feature-a --secure --isolate=8.3 (in $ROOT/gamma-worktrees/feature-a)" \
  "herd link run in the worktree, secure, same PHP as the main site"
assert_eq "$(env_of gamma-worktrees/feature-a SPROUT_HERD_URL)" "https://gamma-feature-a.test" "Herd URL recorded"
assert_eq "$(env_of gamma-worktrees/feature-a APP_URL)" "https://gamma-feature-a.test" "APP_URL points at the Herd site"

# ─── ports skip ones in use by other worktrees or already listening ───────────

echo 8002 > "$LISTENING"
"$SP" create feature/b --project gamma > /dev/null 2>&1
assert_eq "$(env_of gamma-worktrees/feature-b SERVER_PORT)" "8003" "port skips used (8001) and listening (8002)"

# ─── project not linked in Herd: port only ────────────────────────────────────

: > "$CALLS"
"$SP" create feature/c --project delta > /dev/null 2>&1
assert_eq "$(env_of delta-worktrees/feature-c SERVER_PORT)" "8004" "ports are unique across projects"
assert_eq "$(env_of delta-worktrees/feature-c APP_URL)" "http://127.0.0.1:8004" "APP_URL uses the serve port without Herd"
assert_eq "$(cat "$CALLS")" "" "no herd link for a project Herd doesn't serve"

# ─── --no-setup leaves serving alone ──────────────────────────────────────────

"$SP" create feature/bare --project gamma --no-setup > /dev/null 2>&1
assert_eq "$(grep -c 'feature-bare' "$CALLS" || true)" "0" "--no-setup does not link in Herd"

# ─── a worktree from before this feature ──────────────────────────────────────

"$SP" create feature/legacy --project delta --no-setup > /dev/null 2>&1
printf 'APP_URL=http://127.0.0.1:8000\n' > "$ROOT/delta-worktrees/feature-legacy/.env"

# ─── status --json exposes the URLs ───────────────────────────────────────────

echo 8001 > "$LISTENING"
"$SP" status --json > "$OUT"
assert_eq "$(q "W('feature-a')['herdUrl']")" "https://gamma-feature-a.test" "status herdUrl"
assert_eq "$(q "W('feature-a')['serveUrl']")" "http://127.0.0.1:8001" "status serveUrl"
assert_eq "$(q "W('feature-a')['serveRunning']")" "True" "serveRunning when the port is listening"
assert_eq "$(q "W('feature-b')['serveRunning']")" "False" "serveRunning false when nothing listens"
assert_eq "$(q "W('feature-c')['herdUrl']")" "None" "no herdUrl without Herd"
assert_eq "$(q "W('feature-bare')['serveUrl']")" "None" "no serveUrl without a port"
assert_eq "$(q "W('feature-legacy')['serveUrl']")" "http://127.0.0.1:8000" "legacy APP_URL with a port is used as serveUrl"

# ─── delete unlinks the Herd site ─────────────────────────────────────────────

: > "$CALLS"
"$SP" delete feature/a --project gamma --force > /dev/null 2>&1
assert_contains "$(cat "$CALLS")" "unlink gamma-feature-a" "delete unlinks the Herd site"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
if [[ "$FAILS" -eq 0 ]]; then
  echo "all tests passed"
else
  echo "$FAILS test(s) failed"
  exit 1
fi
