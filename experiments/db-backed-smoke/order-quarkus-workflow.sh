#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_dir="$repo_root/benchmark/persistence/order/quarkus"
maven_repo="${SCARF_M2_DIR:-/private/tmp/scarf-m2}"
log_path="/private/tmp/scarf-order-quarkus-workflow.log"
body_path="$(mktemp /private/tmp/scarf-order-body.XXXXXX)"

cd "$app_dir"
mvn -q -Dmaven.repo.local="$maven_repo" package -DskipTests

java -jar target/quarkus-app/quarkus-run.jar >"$log_path" 2>&1 &
app_pid=$!
cleanup() {
  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  rm -f "$body_path"
}
trap cleanup EXIT INT TERM

ready=false
for _ in {1..30}; do
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8082/orders || true)" == 200 ]]; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  tail -100 "$log_path" >&2
  exit 2
fi

post() {
  local path="$1"
  shift
  local http_code
  http_code="$(curl -sS -o "$body_path" -w '%{http_code}' -X POST "$@" "http://localhost:8082/$path")"
  [[ "$http_code" == 200 ]]
}

post submitOrder \
  --data-urlencode 'newOrderId=4242' \
  --data-urlencode 'newOrderStatus=N' \
  --data-urlencode 'newOrderDiscount=20' \
  --data-urlencode 'newOrderShippingInfo=SCARF-EXPRESS-4242'
grep -q '>4242<' "$body_path"
grep -q '>SCARF-EXPRESS-4242<' "$body_path"

curl -sS http://localhost:8082/orders >"$body_path"
grep -q '>4242<' "$body_path"
grep -q '>SCARF-EXPRESS-4242<' "$body_path"

post removeOrder --data-urlencode 'orderId=4242'
if grep -q 'SCARF-EXPRESS-4242' "$body_path"; then
  echo 'deleted order is still present' >&2
  exit 1
fi

echo "PASS: order Quarkus H2 create, read, and deletion workflow"
