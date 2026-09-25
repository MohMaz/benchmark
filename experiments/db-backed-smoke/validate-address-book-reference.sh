#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/experiments/db-backed-smoke/address-book-spring-workflow.sh"
run_log="$(mktemp /private/tmp/scarf-address-book-oracle.XXXXXX.log)"

cleanup() {
  rm -f "$run_log"
}
trap cleanup EXIT INT TERM

if "$workflow" >"$run_log" 2>&1; then
  cat "$run_log" >&2
  printf '%s\n' '{"passed":true,"metrics":{"compile_ok":true,"deploy_ok":true,"tests_passed":5,"tests_total":5,"contract_level":"L2","oracle_id":"amp-scarf-address-book-l2-v1"},"details":"Address Book reference passed five evaluator-owned durable-state cases."}'
  exit 0
else
  status=$?
fi

cat "$run_log" >&2
printf '%s\n' '{"passed":false,"metrics":{"compile_ok":false,"deploy_ok":false,"tests_passed":0,"tests_total":5,"contract_level":"L2","oracle_id":"amp-scarf-address-book-l2-v1"},"details":"Address Book reference workflow failed; see validator stderr for phase diagnostics."}'
exit "$status"
