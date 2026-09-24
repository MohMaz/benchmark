#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_dir="$repo_root/benchmark/persistence/roster/spring"
maven_repo="${SCARF_M2_DIR:-/private/tmp/scarf-m2}"
log_path="/private/tmp/scarf-roster-spring-workflow.log"

cd "$app_dir"
mvn -q -Dmaven.repo.local="$maven_repo" verify

java -jar roster-boot/target/roster-boot-1.0.0.jar >"$log_path" 2>&1 &
app_pid=$!
cleanup() {
  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

ready=false
for _ in {1..30}; do
  if [[ "$(curl -sL -o /dev/null -w '%{http_code}' http://localhost:8080/h2-console || true)" == 200 ]]; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  tail -100 "$log_path" >&2
  exit 2
fi

request() {
  local expected_code="$1"
  local expected_body="$2"
  shift 2
  local body_path
  local http_code
  body_path="$(mktemp /private/tmp/scarf-roster-body.XXXXXX)"
  http_code="$(curl -sS -o "$body_path" -w '%{http_code}' "$@")"
  [[ "$http_code" == "$expected_code" ]]
  if [[ -n "$expected_body" ]]; then
    diff -u <(printf '%s' "$expected_body") "$body_path"
  fi
}

request 200 '' \
  -X POST -H 'Content-Type: application/json' \
  -d '{"id":"L1","name":"Premier","sport":"soccer"}' \
  http://localhost:8080/roster/league
request 200 '' \
  -X POST -H 'Content-Type: application/json' \
  -d '{"id":"T1","name":"Owls","city":"Seattle"}' \
  http://localhost:8080/roster/team/league/L1
request 200 '' \
  -X POST \
  'http://localhost:8080/roster/player?id=P1&name=Ada&position=forward&salary=125000'
request 200 '' -X POST http://localhost:8080/roster/player/P1/team/T1
request 200 \
  '{"id":"L1","name":"Premier","sport":"soccer"}' \
  http://localhost:8080/roster/league/L1
request 200 \
  '[{"id":"P1","name":"Ada","position":"forward","salary":125000.0}]' \
  http://localhost:8080/roster/team/T1/players
request 200 \
  '[{"id":"P1","name":"Ada","position":"forward","salary":125000.0}]' \
  'http://localhost:8080/roster/players/salary/range?low=100000&high=130000'
request 200 \
  '[{"id":"P1","name":"Ada","position":"forward","salary":125000.0}]' \
  http://localhost:8080/roster/players/sport/soccer
request 200 '' -X DELETE http://localhost:8080/roster/player/P1
request 404 '' http://localhost:8080/roster/player/P1

echo "PASS: roster Spring H2 CRUD, relationship, query, and deletion workflow"
