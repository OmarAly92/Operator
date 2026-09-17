#!/usr/bin/env bash
set -uo pipefail
attempts=3
read -r -a delays <<< "${GH_RETRY_DELAYS:-10 30}"
for ((i = 1; i <= attempts; i++)); do
  "$@" && exit 0
  status=$?
  if ((i == attempts)); then
    echo "::error::command failed after $attempts attempts: $*" >&2
    exit "$status"
  fi
  delay=${delays[i - 1]}
  echo "::warning::attempt $i/$attempts failed (exit $status), retrying in ${delay}s: $*" >&2
  sleep "$delay"
done
