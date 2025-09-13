#!/usr/bin/env bash

function ansi_span() {
  local color="$1"
  shift
  local first="$1"
  shift
  # Color first argument, then append rest uncolored
  printf "%b%s" "$color" "$first"
  printf "\033[0m"
  printf "%b" "$@"
}