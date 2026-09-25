#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_root="$repo_root/experiments/db-backed-smoke/fixtures"
validator="$repo_root/experiments/db-backed-smoke/validate-address-book-reference.sh"
port="${SCARF_ADDRESS_BOOK_NEGATIVE_PORT:-18081}"
server_log="$(mktemp /private/tmp/scarf-address-book-fake.XXXXXX.log)"
validator_output="$(mktemp /private/tmp/scarf-address-book-fake-result.XXXXXX.json)"

python3 -m http.server "$port" --directory "$fixture_root" >"$server_log" 2>&1 &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  rm -f "$server_log" "$validator_output"
}
trap cleanup EXIT INT TERM

ready=false
for _ in {1..20}; do
  if [[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://localhost:${port}/contact/List.xhtml" || true)" == 200 ]]; then
    ready=true
    break
  fi
  sleep 0.25
done
if [[ "$ready" != true ]]; then
  cat "$server_log" >&2
  exit 2
fi

if SCARF_ADDRESS_BOOK_SKIP_LAUNCH=true \
  SCARF_ADDRESS_BOOK_BASE_URL="http://localhost:${port}" \
  "$validator" >"$validator_output" 2>/dev/null; then
  echo 'FAIL: evaluator accepted a DB-free HTTP-200 fake' >&2
  exit 1
fi
jq -e '
  .passed == false and
  .metrics.tests_passed == 0 and
  .metrics.tests_total == 5
' "$validator_output" >/dev/null

echo 'PASS: evaluator rejected the DB-free HTTP-200 fake'
