#!/usr/bin/env bash

ANSI_RESET='\033'

ansi_span() {
  local arg

  for arg in "$@"; do
    # match actual CSI sequence at start
    if [[ $arg == *"$ANSI_RESET"* ]]; then
      printf "%b%b" "$arg" "${ANSI_RESET}[0m"
    else
      printf "%b" "$arg"
    fi
  done
}
