#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="$repo_root/benchmark/whole_applications/realworld/spring"
gradle_home="${SCARF_GRADLE_DIR:-/private/tmp/scarf-gradle-home}"
port="${SCARF_REALWORLD_PORT:-18083}"
base_url="http://localhost:${port}"
work_dir="$(mktemp -d /private/tmp/scarf-realworld.XXXXXX)"
log_path="/private/tmp/scarf-realworld-spring-workflow.log"

app_pid=''
cleanup() {
  if [[ -n "$app_pid" ]]; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null
command -v jq >/dev/null
mkdir -p "$gradle_home"
cp -R "$source_dir/." "$work_dir"

# This gold project pins Gradle 6.8.3, which cannot build on the benchmark
# host's JDK 21. Build in the JDK 11 environment declared by its Dockerfile,
# while avoiding the Dockerfile's unrelated Playwright installation.
docker run --rm \
  -v "$work_dir:/work" \
  -v "$gradle_home:/root/.gradle" \
  -w /work \
  eclipse-temurin:11-jdk-focal \
  ./gradlew --no-daemon clean bootJar -x test

jar_path="$work_dir/build/libs/realworld-spring-boot-java-2.1.1.jar"
[[ -f "$jar_path" ]]
SERVER_PORT="$port" java -jar "$jar_path" >"$log_path" 2>&1 &
app_pid=$!

ready=false
for _ in {1..45}; do
  if [[ "$(curl -sS -o "$work_dir/ready.json" -w '%{http_code}' "$base_url/tags" || true)" == 200 ]]; then
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
  local method="$2"
  local endpoint="$3"
  local output="$4"
  shift 4
  local actual_code
  actual_code="$(curl -sS -o "$output" -w '%{http_code}' \
    -X "$method" "$@" "$base_url$endpoint")"
  if [[ "$actual_code" != "$expected_code" ]]; then
    echo "$method $endpoint: expected $expected_code, got $actual_code" >&2
    cat "$output" >&2
    exit 1
  fi
}

json_header=(-H 'Content-Type: application/json')

signup="$work_dir/signup.json"
request 200 POST /users "$signup" "${json_header[@]}" \
  -d '{"user":{"email":"ada@scarf.test","password":"correct-horse-battery-staple","username":"ada"}}'
jq -e '.user.email == "ada@scarf.test" and .user.username == "ada" and (.user.token | length > 20)' "$signup" >/dev/null

# Database uniqueness and authentication are meaningful negative controls.
request 409 POST /users "$work_dir/duplicate.json" "${json_header[@]}" \
  -d '{"user":{"email":"ada@scarf.test","password":"different-password","username":"other"}}'
request 401 POST /users/login "$work_dir/bad-login.json" "${json_header[@]}" \
  -d '{"user":{"email":"ada@scarf.test","password":"wrong-password"}}'

login="$work_dir/login.json"
request 200 POST /users/login "$login" "${json_header[@]}" \
  -d '{"user":{"email":"ada@scarf.test","password":"correct-horse-battery-staple"}}'
token="$(jq -er '.user.token' "$login")"
auth_header=(-H "Authorization: Token $token")

article="$work_dir/article.json"
request 200 POST /articles "$article" "${json_header[@]}" "${auth_header[@]}" \
  -d '{"article":{"title":"SCARF Stateful Story","description":"evaluator-owned oracle","body":"the database must remember this","tagList":["migration","mongodb"]}}'
jq -e '.article.title == "SCARF Stateful Story" and .article.author.username == "ada" and (.article.tagList | sort) == ["migration", "mongodb"]' "$article" >/dev/null
slug="$(jq -er '.article.slug' "$article")"

persisted="$work_dir/persisted.json"
request 200 GET "/articles/$slug" "$persisted"
jq -e '.article.body == "the database must remember this" and .article.slug == "scarf-stateful-story"' "$persisted" >/dev/null

tags="$work_dir/tags.json"
request 200 GET /tags "$tags"
jq -e '(.tags | sort) == ["migration", "mongodb"]' "$tags" >/dev/null

comment="$work_dir/comment.json"
request 200 POST "/articles/$slug/comments" "$comment" "${json_header[@]}" "${auth_header[@]}" \
  -d '{"comment":{"body":"relations survive the migration"}}'
jq -e '.comment.body == "relations survive the migration" and .comment.author.username == "ada"' "$comment" >/dev/null
jq -er '.comment.id' "$comment" >/dev/null

comments="$work_dir/comments.json"
request 200 GET "/articles/$slug/comments" "$comments" "${auth_header[@]}"
jq -e '.comments | length == 1 and .[0].body == "relations survive the migration"' "$comments" >/dev/null

favorite="$work_dir/favorite.json"
request 200 POST "/articles/$slug/favorite" "$favorite" "${auth_header[@]}"
jq -e '.article.favorited == true and .article.favoritesCount == 1' "$favorite" >/dev/null

unfavorite="$work_dir/unfavorite.json"
request 200 DELETE "/articles/$slug/favorite" "$unfavorite" "${auth_header[@]}"
jq -e '.article.favorited == false and .article.favoritesCount == 0' "$unfavorite" >/dev/null

request 204 DELETE "/articles/$slug" "$work_dir/delete-article.json" "${auth_header[@]}"
request 404 GET "/articles/$slug" "$work_dir/missing-article.json"

echo 'PASS: realworld Spring H2 auth, uniqueness, article, tags, comments, favorite, and deletion workflow'
