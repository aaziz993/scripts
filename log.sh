#!/usr/bin/env bash

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ansi.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/datetime.sh"

VERBOSE="${VERBOSE:-1}"
COLOR="${COLOR:-1}"

function info() {
  if [[ "$VERBOSE" -eq 0 ]]; then
    return
  fi
  if [[ "$COLOR" -eq 1 ]]; then
    ansi_span "\033[0;36m$(timestamp) [INFO]" " $1\n">&2
  else
    printf "[%s] [INFO] %s\n" "$(timestamp)" "$1" >&2
  fi
}

function warn() {
  if [[ "$COLOR" -eq 1 ]]; then
    ansi_span "\033[0;33m$(timestamp) [WARN]" " $1\n" >&2
  else
    printf "[%s] [WARN] %s\n" "$(timestamp)" "$1" >&2
  fi
}

function error() {
  local code="${2:-1}"
  if [[ "$COLOR" -eq 1 ]]; then
    ansi_span "\033[0;31m$(timestamp) [ERROR]" " $1 (exit code: $code)\n">&2
  else
    printf "[%s] [ERROR] %s (exit code: %d)\n" "$(timestamp)" "$1" "$code" >&2
  fi
  exit "$code"
}

function check() {
  local condition="$1"
  local message="$2"
  local code="${3:-}"

  if eval "$condition"; then
    error "$message" "$code"
  fi
}