#!/usr/bin/env bash

ANSI_ESC=$'\033'
ANSI_PATTERN="$ANSI_ESC\[[0-9;?]*[A-Za-z]"

function ansi_span() {
  local arg

  for arg in "$@"; do
    if [[ "$arg" =~ $ANSI_PATTERN ]]; then
      # append reset only if color code is present
      printf "%b%s" "$arg" "${ANSI_ESC}[0m"
    else
      printf "%b" "$arg"
    fi
  done
}
