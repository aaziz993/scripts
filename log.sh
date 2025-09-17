#!/usr/bin/env bash

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ansi.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/time.sh"

VERBOSE="${VERBOSE:-1}"
COLOR="${COLOR:-1}"

function info() {
  local message="$1"
  if [[ "$VERBOSE" -eq 0 ]]; then
    return
  fi
  if [[ "$COLOR" -eq 1 ]]; then
    ansi_span "$(timestamp) " "\033[0;36m[INFO] $message\n" >&2
  else
    printf "[%s] [INFO] %s\n" "$(timestamp)" "$message" >&2
  fi
}

function warn() {
  local message="$1"
  if [[ "$COLOR" -eq 1 ]]; then
    ansi_span "$(timestamp) " "\033[0;33m[WARN] $message\n" >&2
  else
    printf "[%s] [WARN] %s\n" "$(timestamp)" "$message" >&2
  fi
}

function error() {
  local message="$1"
  local code="${2:-1}"
  if [[ "$COLOR" -eq 1 ]]; then
    ansi_span "$(timestamp) " "\033[0;31m[ERROR] $message (exit code: $code)\n" >&2
  else
    printf "[%s] [ERROR] %s (exit code: %d)\n" "$(timestamp)" "$message" "$code" >&2
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
