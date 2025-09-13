#!/usr/bin/env bash

function ansi_span() {
  local color="$1"
  local first="$2"
  shift
  shift
  # Color first argument, then append rest uncolored
  printf "%b%b\033[0m" "$color" "$first"
  printf "%b" "$@"
}