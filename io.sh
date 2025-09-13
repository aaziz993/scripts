#!/usr/bin/env bash

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
