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
  local default="${1:-}"       # Default value
  local input_color="${2:-}"   # Color for user input
  shift 2

  # Build prompt arguments
  local prompt_args=("$@")
  if [[ -n "$default" ]]; then
    prompt_args+=("${input_color}[${default}]> ")
  else
    prompt_args=("> ")
  fi

  # Print prompt
  ansi_span "${prompt_args[@]}" >&2

  # Set input color if provided
  if [[ -n "$input_color" ]]; then
    printf "%b" "$input_color" >&2
  fi

  # Read input
  local input
  read -r input

  # Reset colors
  printf "\033[0m" >&2

  # Return input or default
  if [[ -n "$input" ]]; then
    printf "%s" "$input"
  elif [[ -n "$default" ]]; then
    printf "%s" "$default"
  else
    error "No input provided and no default available"
  fi
}
