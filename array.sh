#!/usr/bin/env bash

function join_to_string() {
  local -n array="$1"
  local delimiter="${2-,}"
  local IFS="$delimiter"
  echo "${array[*]}"
}