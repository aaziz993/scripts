#!/usr/bin/env bash

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ansi.sh"

# Get source from pipe, terminal or file
function src() {
  local source="${1:-}"

  if [[ -t 0 || -n "$source" ]]; then
    if [[ -f "$source" ]]; then
      cat "$source"
    else
      printf "%s" "$source"
    fi
    return
  fi

  cat
}

function clipboard() {
  local source="${1:-}"

  if command -v pbcopy &>/dev/null; then
    src "$source" | pbcopy
  elif command -v xclip &>/dev/null; then
    src "$source" | xclip
  elif command -v xsel &>/dev/null; then
    src "$source" | xsel
  elif command -v clip &>/dev/null; then
    src "$source" | clip
  else
    return 1
  fi

  echo -e "\033[0;32mCopied to clipboard\033[0m"
}

function file_hash_sha256() {
  local file="$1"

  sha256sum "$file" | awk '{ print $1 }'
}

function download_absent_file() {
  local url="$1"
  local file="${2:-$(basename "$url")}"

  if [ ! -f "$file" ]; then
    echo "Downloading $file ..."
    curl -sSL "$url" -o "$file"
  else
    echo "$file already exists, skipping download."
  fi
}

function user_input() {
  local default="${1:-}"
  local default_label="${2:-$default}"
  local input_color="${3:-}"
  shift 3

  local labels=("$@")
  if [[ -n "$default_label" ]]; then
    labels+=("${input_color}[${default_label}]> ")
  else
    labels+=("> ")
  fi

  # Print labels.
  ansi_span "${labels[@]}" >&2

  # Set input color if provided.
  if [[ -n "$input_color" ]]; then
    printf "%b" "$input_color" >&2
  fi

  # Read input.
  local input
  read -r input

  printf "\033[0m" >&2

  printf "%s" "${input:-$default}"
}

function default_user_input() {
  local default="${1:-}"
  local default_label="${2:-}"
  local input_name="$3"

  user_input "$default" "$default_label" "\033[1;36m" "\033[0;32mEnter $input_name"
}
