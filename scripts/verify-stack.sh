#!/usr/bin/env bash
#
# End-to-end verification of the running Izvor containerized stack (thesis §4.5).
# Proves cross-tenant isolation, tenant-resolution fail-closed edges, and the
# exception_log write-through against a live `docker compose` stack.
#
# Verification only: makes no code/schema/compose changes and no git commit.
#
#   bash scripts/verify-stack.sh                 # checks A, B, C
#   bash scripts/verify-stack.sh --with-restart  # A, B, C, then D (cycles the stack)
#
# Re-runnable. Exits non-zero if any check fails.
#
set -uo pipefail

BASE="http://localhost"
PG_CONTAINER="izvor-postgres"
DB="izvor"
DB_USER="izvor_admin"

INTELLYA_HOST="intellya.izvor.lvh.me"
FON_HOST="fon.izvor.lvh.me"
ADMIN_EMAIL="admin@intellya.com"
ADMIN_PASSWORD="demo123"

WITH_RESTART=false
[ "${1:-}" = "--with-restart" ] && WITH_RESTART=true

PASS_COUNT=0
FAIL_COUNT=0

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '  [%s] %s\n' "$(green PASS)" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '  [%s] %s\n' "$(red FAIL)" "$1"; }

section() { printf '\n=== %s ===\n' "$1"; }

# req METHOD HOST PATH [TOKEN] [JSON_BODY]
# Emits: body on all lines but the last; last line is the HTTP status code.
req() {
  local method="$1" host="$2" path="$3" token="${4:-}" body="${5:-}"
  local args=(-s -w $'\n%{http_code}' -X "$method" -H "Host: $host" "$BASE$path")
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  curl "${args[@]}"
}

# check DESC EXPECTED_STATUS EXPECTED_SUBSTRING RESPONSE
# RESPONSE is the raw req() output (body + trailing status line).
check() {
  local desc="$1" want_status="$2" want_sub="$3" resp="$4"
  local status body
  status="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  if [ "$status" != "$want_status" ]; then
    fail "$desc — expected HTTP $want_status, got $status; body: $(printf '%s' "$body" | head -c 200)"
    return
  fi
  if [ -n "$want_sub" ] && ! printf '%s' "$body" | grep -q "$want_sub"; then
    fail "$desc — status $status OK but body missing '$want_sub'; body: $(printf '%s' "$body" | head -c 200)"
    return
  fi
  pass "$desc — HTTP $status, body contains '${want_sub:-<any>}'"
}

psql_q() {
  docker exec "$PG_CONTAINER" psql -U "$DB_USER" -d "$DB" -tAc "$1"
}

login_intellya_admin() {
  local resp status body
  resp="$(req POST "$INTELLYA_HOST" /api/auth/login "" \
    "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")"
  status="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  if [ "$status" != "200" ]; then
    printf '%s' "$body" | head -c 200 >&2
    return 1
  fi
  printf '%s' "$body" | jq -r '.accessToken'
}

# ---------------------------------------------------------------------------
# A. Cross-tenant isolation
# ---------------------------------------------------------------------------
run_check_a() {
  section "A. Cross-tenant isolation"

  local token
  if ! token="$(login_intellya_admin)" || [ -z "$token" ] || [ "$token" = "null" ]; then
    fail "A0 login as $ADMIN_EMAIL on $INTELLYA_HOST — could not obtain accessToken"
    return 1
  fi
  pass "A0 login as $ADMIN_EMAIL on $INTELLYA_HOST — got accessToken"

  check "A1 intellya JWT on Host $FON_HOST → 403 tenant_mismatch" 403 tenant_mismatch \
    "$(req GET "$FON_HOST" /api/me "$token")"

  check "A2 (control) intellya JWT on Host $INTELLYA_HOST → 200" 200 '"subdomain":"intellya"' \
    "$(req GET "$INTELLYA_HOST" /api/me "$token")"

  # Export the token so C can reuse it without a second login (rate-limit hygiene).
  INTELLYA_TOKEN="$token"
}

# ---------------------------------------------------------------------------
# B. Fail-closed / tenant-resolution edges
# ---------------------------------------------------------------------------
run_check_b() {
  section "B. Fail-closed / tenant-resolution edges"

  check "B1 reserved subdomain api.izvor.lvh.me → 400 invalid_host" 400 invalid_host \
    "$(req GET "api.izvor.lvh.me" /api/me)"

  check "B2 unknown tenant nope.izvor.lvh.me → 404 tenant_not_found" 404 tenant_not_found \
    "$(req GET "nope.izvor.lvh.me" /api/me)"
}

# ---------------------------------------------------------------------------
# C. exception_log write-through
# ---------------------------------------------------------------------------
run_check_c() {
  section "C. exception_log write-through"

  local token="${INTELLYA_TOKEN:-}"
  if [ -z "$token" ]; then
    if ! token="$(login_intellya_admin)" || [ -z "$token" ] || [ "$token" = "null" ]; then
      fail "C setup login — could not obtain accessToken"
      return 1
    fi
  fi

  local guid path
  guid="$(cat /proc/sys/kernel/random/uuid)"
  path="/api/categories/$guid"

  check "C1 PUT $path (admin) → 404 category_not_found" 404 category_not_found \
    "$(req PUT "$INTELLYA_HOST" "$path" "$token" '{"name":"Renamed","description":null}')"

  local row
  row="$(psql_q "SELECT pg_code || '|' || http_status || '|' || http_method || '|' || \
    (tenant_id IS NOT NULL)::text || '|' || (user_id IS NOT NULL)::text \
    FROM system_impl.exception_log WHERE path = '$path';")"

  local count
  count="$(printf '%s\n' "$row" | grep -c .)"
  if [ "$count" != "1" ]; then
    fail "C2 exception_log write-through — expected exactly 1 row for path $path, found $count"
    return
  fi
  if [ "$row" = "P0001|404|PUT|true|true" ]; then
    pass "C2 exception_log write-through — 1 row: pg_code=P0001 http_status=404 method=PUT tenant/user populated"
  else
    fail "C2 exception_log write-through — row present but fields differ; got '$row' (want 'P0001|404|PUT|true|true')"
  fi
}

# ---------------------------------------------------------------------------
# D. Persistence across down/up (opt-in — restarts the stack)
# ---------------------------------------------------------------------------
run_check_d() {
  section "D. Persistence across docker compose down/up"

  local before
  before="$(psql_q "SELECT count(*) || '|' || string_agg(subdomain, ',' ORDER BY subdomain) \
    FROM system_impl.tenants;")"
  printf '  before down: tenants = %s\n' "$before"

  printf '  docker compose down (no -v) ...\n'
  docker compose down >/dev/null 2>&1
  printf '  docker compose up -d ...\n'
  docker compose up -d >/dev/null 2>&1

  printf '  waiting for /api/health ...\n'
  local i status
  for i in $(seq 1 60); do
    status="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $INTELLYA_HOST" "$BASE/api/health" 2>/dev/null)"
    [ "$status" = "200" ] && break
    sleep 2
  done
  if [ "$status" != "200" ]; then
    fail "D health poll — stack did not become healthy within timeout (last status: $status)"
    return
  fi
  pass "D0 stack healthy after up (/api/health → 200)"

  local after
  after="$(psql_q "SELECT count(*) || '|' || string_agg(subdomain, ',' ORDER BY subdomain) \
    FROM system_impl.tenants;")"
  printf '  after up:   tenants = %s\n' "$after"

  if [ "$after" = "$before" ] && printf '%s' "$after" | grep -q 'fon' && printf '%s' "$after" | grep -q 'intellya'; then
    pass "D1 tenants persisted across down/up (named volume izvor-pgdata) — $after"
  else
    fail "D1 tenant persistence — before '$before' != after '$after'"
  fi

  # D2: a prior check still passes post-cycle (fresh login required — api restarted).
  local token
  if ! token="$(login_intellya_admin)" || [ -z "$token" ] || [ "$token" = "null" ]; then
    fail "D2 post-cycle login — could not obtain accessToken"
    return
  fi
  check "D2 cross-tenant 403 still holds post-cycle" 403 tenant_mismatch \
    "$(req GET "$FON_HOST" /api/me "$token")"
}

# ---------------------------------------------------------------------------
main() {
  printf 'Izvor stack verification — %s\n' "$BASE"

  run_check_a
  run_check_b
  run_check_c
  if [ "$WITH_RESTART" = true ]; then
    run_check_d
  else
    section "D. Persistence across down/up"
    printf '  (skipped — pass --with-restart to run; it cycles the stack)\n'
  fi

  section "Summary"
  printf '  %s passed, %s failed\n' "$(green "$PASS_COUNT")" "$([ "$FAIL_COUNT" -gt 0 ] && red "$FAIL_COUNT" || printf '%s' 0)"
  [ "$FAIL_COUNT" -eq 0 ]
}

main
