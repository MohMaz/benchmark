#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/experiments/db-backed-smoke/address-book-spring-workflow.sh"
work_dir=''
framework=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir)
      work_dir="${2:-}"
      shift 2
      ;;
    --framework)
      framework="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$work_dir" || ! -d "$work_dir" ]]; then
  echo '--work-dir must name an existing candidate directory' >&2
  exit 2
fi
if [[ "$framework" != spring && "$framework" != quarkus ]]; then
  echo '--framework must be spring or quarkus' >&2
  exit 2
fi

run_log="$(mktemp /private/tmp/scarf-address-book-oracle.XXXXXX.log)"
cleanup() {
  rm -f "$run_log"
}
trap cleanup EXIT INT TERM

if SCARF_ADDRESS_BOOK_APP_DIR="$work_dir" \
  SCARF_ADDRESS_BOOK_FRAMEWORK="$framework" \
  "$workflow" >"$run_log" 2>&1; then
  cat "$run_log" >&2
  printf '{"passed":true,"metrics":{"compile_ok":true,"deploy_ok":true,"tests_passed":5,"tests_total":5,"contract_level":"L2","oracle_id":"amp-scarf-address-book-l2-v1","target_framework":"%s"},"details":"Address Book workspace passed five evaluator-owned durable-state cases."}\n' "$framework"
  exit 0
else
  status=$?
fi

cat "$run_log" >&2
compile_ok=false
deploy_ok=false
if grep -Fq 'SCARF_EVIDENCE_COMPILE_OK=true' "$run_log"; then
  compile_ok=true
fi
if grep -Fq 'SCARF_EVIDENCE_DEPLOY_OK=true' "$run_log"; then
  deploy_ok=true
fi
tests_passed="$(grep -c '^SCARF_EVIDENCE_CASE_PASS=' "$run_log" || true)"
printf '{"passed":false,"metrics":{"compile_ok":%s,"deploy_ok":%s,"tests_passed":%s,"tests_total":5,"contract_level":"L2","oracle_id":"amp-scarf-address-book-l2-v1","target_framework":"%s"},"details":"Address Book workspace workflow failed after %s of five evaluator-owned cases; see validator stderr for phase diagnostics."}\n' \
  "$compile_ok" "$deploy_ok" "$tests_passed" "$framework" "$tests_passed"
exit "$status"
