#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_dir="$(mktemp -d /private/tmp/scarf-static-negative.XXXXXX)"

mkdir -p \
  "$fixture_dir/address-book-10-SNAPSHOT" \
  "$fixture_dir/roster" \
  "$fixture_dir/order-10-SNAPSHOT" \
  "$fixture_dir/petclinic" \
  "$fixture_dir/daytrader" \
  "$fixture_dir/cargo-tracker" \
  "$fixture_dir/api"

touch \
  "$fixture_dir/index.html" \
  "$fixture_dir/address-book-10-SNAPSHOT/index.html" \
  "$fixture_dir/roster/index.html" \
  "$fixture_dir/order-10-SNAPSHOT/index.html" \
  "$fixture_dir/petclinic/home.jsf" \
  "$fixture_dir/daytrader/index.html" \
  "$fixture_dir/cargo-tracker/index.xhtml" \
  "$fixture_dir/api/tags"

pids=()
cleanup() {
  for server_pid in "${pids[@]}"; do
    kill "$server_pid" 2>/dev/null || true
  done
  for server_pid in "${pids[@]}"; do
    wait "$server_pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

for port in 8080 8081 8082 9080; do
  python3 -m http.server "$port" --directory "$fixture_dir" \
    >"/private/tmp/scarf-static-${port}.log" 2>&1 &
  pids+=("$!")
done

ready=false
for _ in {1..15}; do
  if [[ "$(curl -sL -o /dev/null -w '%{http_code}' http://localhost:8080/api/tags || true)" == 200 ]]; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "temporary negative-control servers did not become ready" >&2
  exit 2
fi

smoke_scripts=()
while IFS= read -r smoke_script; do
  smoke_scripts+=("$smoke_script")
done < <(
  find \
    "$repo_root/benchmark/persistence" \
    "$repo_root/benchmark/whole_applications" \
    -mindepth 3 -maxdepth 3 -name test.sh -type f | sort
)

accepted=0
rejected=0
echo "test,negative_control"
for smoke_script in "${smoke_scripts[@]}"; do
  relative_path="${smoke_script#"$repo_root"/}"
  if "$smoke_script" >/dev/null 2>&1; then
    echo "$relative_path,ACCEPTED_STATIC_FAKE"
    accepted=$((accepted + 1))
  else
    echo "$relative_path,rejected"
    rejected=$((rejected + 1))
  fi
done

echo "summary,accepted=$accepted rejected=$rejected total=${#smoke_scripts[@]}"

# This spike records the current weakness. A future strengthened public oracle
# should deliberately make this assertion fail and update the expected result.
[[ "$accepted" -eq 24 && "$rejected" -eq 0 ]]
