#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$repo_root/experiments/db-backed-smoke/validate-address-book-workspace.sh" \
  --work-dir "$repo_root/benchmark/persistence/address-book/spring" \
  --framework spring
