#!/usr/bin/env bash
# shellcheck disable=SC2034

NO_SUCH_ELEMENT=101

function os_name() {
  uname -s
}

function arch_name() {
  uname -m
}

function ensure_cmd() {
  local cmd="$1"
  if ! command -v -- "$cmd" >/dev/null 2>&1; then
    die "Required command not found in PATH: $cmd"
  fi
}

function bash_env() {
  local full_key="$1"
  local key="${full_key%%-*}"
  local default="${full_key#*-}"

  if [[ -v $key ]]; then
    printf "%s" "${!key}"
    return 0
  elif [[ "$full_key" == *-* ]]; then
    printf "%s" "$default"
    return 0
  fi

  return 1
}

function bash_c() {
  local value="$1"

  bash -c "
  set -euo pipefail    # fail fast, catch unset variables, propagate pipeline failures
  set -o errtrace      # propagate ERR trap into functions/subshells
  $value
  "
}
