#!/usr/bin/env bash

function ansi_span() {
  local arg

  for arg in "$@"; do
    printf "%b\033[0m" "$arg"
  done
}