#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_dir="${SCARF_ADDRESS_BOOK_APP_DIR:-$repo_root/benchmark/persistence/address-book/spring}"
framework="${SCARF_ADDRESS_BOOK_FRAMEWORK:-spring}"
maven_repo="${SCARF_M2_DIR:-/private/tmp/scarf-m2}"
log_path="/private/tmp/scarf-address-book-spring-workflow.log"
work_dir="$(mktemp -d /private/tmp/scarf-address-book.XXXXXX)"
port="${SCARF_ADDRESS_BOOK_PORT:-18080}"
base_url="${SCARF_ADDRESS_BOOK_BASE_URL:-http://localhost:${port}}"

app_pid=''
cleanup() {
  if [[ -n "$app_pid" ]]; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

if [[ "${SCARF_ADDRESS_BOOK_SKIP_LAUNCH:-false}" != true ]]; then
  cd "$app_dir"
  case "$framework" in
    spring)
      mvn -q -Dmaven.repo.local="$maven_repo" \
        -Dspring-boot.run.arguments="--server.port=$port" \
        spring-boot:run >"$log_path" 2>&1 &
      ;;
    quarkus)
      mvn -q -Dmaven.repo.local="$maven_repo" \
        package -DskipTests >"$log_path" 2>&1
      QUARKUS_HTTP_PORT="$port" \
        java -jar target/quarkus-app/quarkus-run.jar >>"$log_path" 2>&1 &
      ;;
    *)
      echo "unsupported Address Book framework: $framework" >&2
      exit 2
      ;;
  esac
  app_pid=$!
fi

ready=false
for _ in {1..45}; do
  if [[ "$(curl -sL -o /dev/null -w '%{http_code}' "$base_url/contact/List.xhtml" || true)" == 200 ]]; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  tail -100 "$log_path" >&2
  exit 2
fi
echo 'SCARF_EVIDENCE_COMPILE_OK=true'
echo 'SCARF_EVIDENCE_DEPLOY_OK=true'

form_id() {
  sed -n 's/.*<form id="\([^"]*\)".*/\1/p' "$1" | head -1
}

view_state() {
  sed -n 's/.*name="jakarta.faces.ViewState"[^>]*value="\([^"]*\)".*/\1/p' "$1" | head -1
}

action_id() {
  local page="$1"
  local label="$2"
  local action

  action="$(sed -n "s/.*{'\([^']*\)':'[^']*'}.*>${label}<.*/\1/p" "$page" | head -1)"
  if [[ -z "$action" ]]; then
    action="$(sed -n "s/.*myfaces\.oam\.submitForm('[^']*','\([^']*\)').*>${label}<.*/\1/p" "$page" | head -1)"
  fi
  printf '%s\n' "$action"
}

# Mojarra renders a command component as a request parameter whose name and
# value are the component id. MyFaces instead writes the component id to its
# `${form}:_idcl` hidden field and includes `${form}_SUBMIT=1`. Keep the
# evaluator-owned interaction at the JSF protocol boundary so both gold
# framework implementations are tested by the same behavioral oracle.
action_fields=()
prepare_action_fields() {
  local page="$1"
  local form="$2"
  local action="$3"

  if grep -Fq 'myfaces.oam.submitForm' "$page"; then
    action_fields=(
      --data-urlencode "${form}_SUBMIT=1"
      --data-urlencode "${form}:_idcl=${action}"
    )
  else
    action_fields=(
      --data-urlencode "${form}=${form}"
      --data-urlencode "${action}=${action}"
    )
  fi
}

open_create_form() {
  local cookie_jar="$1"
  local list_page="$2"
  local create_page="$3"
  local form
  local action
  local state

  curl -sS -c "$cookie_jar" -b "$cookie_jar" \
    "$base_url/contact/List.xhtml" -o "$list_page"
  form="$(form_id "$list_page")"
  action="$(action_id "$list_page" 'Create New Contact')"
  state="$(view_state "$list_page")"
  [[ -n "$form" && -n "$action" && -n "$state" ]]
  prepare_action_fields "$list_page" "$form" "$action"

  curl -sS -c "$cookie_jar" -b "$cookie_jar" -X POST \
    "${action_fields[@]}" \
    --data-urlencode "jakarta.faces.ViewState=${state}" \
    "$base_url/contact/List.xhtml" -o "$create_page"
}

writer_cookie="$work_dir/writer.cookies"
writer_list="$work_dir/writer-list.html"
create_page="$work_dir/create.html"
created_page="$work_dir/created.html"
open_create_form "$writer_cookie" "$writer_list" "$create_page"

form="$(form_id "$create_page")"
action="$(action_id "$create_page" 'Save')"
state="$(view_state "$create_page")"
[[ -n "$form" && -n "$action" && -n "$state" ]]
prepare_action_fields "$create_page" "$form" "$action"
curl -sS -c "$writer_cookie" -b "$writer_cookie" -X POST \
  "${action_fields[@]}" \
  --data-urlencode "${form}:firstName=Ada" \
  --data-urlencode "${form}:lastName=Lovelace" \
  --data-urlencode "${form}:birthday=12/10/1815" \
  --data-urlencode "${form}:homePhone=206-555-0100" \
  --data-urlencode "${form}:mobilePhone=425-555-0101" \
  --data-urlencode "${form}:email=ada@scarf.test" \
  --data-urlencode "jakarta.faces.ViewState=${state}" \
  "$base_url/contact/Create.xhtml" -o "$created_page"
grep -Fq 'Contact was successfully created.' "$created_page"
echo 'SCARF_EVIDENCE_CASE_PASS=create'

# A new browser session proves the row was persisted rather than left only in
# the JSF session-scoped controller.
reader_cookie="$work_dir/reader.cookies"
reader_list="$work_dir/reader-list.html"
curl -sS -c "$reader_cookie" -b "$reader_cookie" \
  "$base_url/contact/List.xhtml" -o "$reader_list"
for expected in Ada Lovelace 206-555-0100 425-555-0101 ada@scarf.test; do
  grep -Fq ">$expected<" "$reader_list"
done
echo 'SCARF_EVIDENCE_CASE_PASS=independent-session-read'

# The negative case must be rejected by application validation and must not
# become a second database row.
invalid_cookie="$work_dir/invalid.cookies"
invalid_list="$work_dir/invalid-list.html"
invalid_create="$work_dir/invalid-create.html"
invalid_result="$work_dir/invalid-result.html"
open_create_form "$invalid_cookie" "$invalid_list" "$invalid_create"
form="$(form_id "$invalid_create")"
action="$(action_id "$invalid_create" 'Save')"
state="$(view_state "$invalid_create")"
prepare_action_fields "$invalid_create" "$form" "$action"
curl -sS -c "$invalid_cookie" -b "$invalid_cookie" -X POST \
  "${action_fields[@]}" \
  --data-urlencode "${form}:firstName=Invalid" \
  --data-urlencode "${form}:lastName=Email" \
  --data-urlencode "${form}:email=not-an-email" \
  --data-urlencode "jakarta.faces.ViewState=${state}" \
  "$base_url/contact/Create.xhtml" -o "$invalid_result"
grep -Fq 'Not a valid email address.' "$invalid_result"
echo 'SCARF_EVIDENCE_CASE_PASS=invalid-email-rejection'

# Delete from the independently loaded list, then verify from yet another
# session that no contact (valid or invalid) remains.
form="$(form_id "$reader_list")"
action="$(action_id "$reader_list" 'Destroy')"
state="$(view_state "$reader_list")"
[[ -n "$form" && -n "$action" && -n "$state" ]]
prepare_action_fields "$reader_list" "$form" "$action"
deleted_page="$work_dir/deleted.html"
curl -sS -c "$reader_cookie" -b "$reader_cookie" -X POST \
  "${action_fields[@]}" \
  --data-urlencode "jakarta.faces.ViewState=${state}" \
  "$base_url/contact/List.xhtml" -o "$deleted_page"
grep -Fq 'Contact was successfully deleted.' "$deleted_page"
echo 'SCARF_EVIDENCE_CASE_PASS=delete'

final_page="$work_dir/final.html"
curl -sS "$base_url/contact/List.xhtml" -o "$final_page"
grep -Fq '(No Contact Items Found)' "$final_page"
if grep -Eq 'Ada|Lovelace|not-an-email' "$final_page"; then
  echo 'deleted or invalid contact is still present' >&2
  exit 1
fi
echo 'SCARF_EVIDENCE_CASE_PASS=independent-empty-state'

echo "PASS: address-book ${framework} H2 create, independent read, validation, and deletion workflow"
