#!/usr/bin/env bash
# shellcheck disable=SC2120
# shellcheck disable=SC2086

function gpg_gen_key() {
  local key_passphrase="$1"
  local key_type="$2"
  local key_length="$3"
  local subkey_type="$4"
  local subkey_length="$5"
  local name_real="$6"
  local name_comment="$7"
  local name_email="$8"
  local expire_date="$9"

  gpg --gen-key --batch <<EOF
Passphrase: $key_passphrase
Key-Type: $key_type
Key-Length: $key_length
Subkey-Type: $subkey_type
Subkey-Length: $subkey_length
Name-Real: $name_real
Name-Comment: $name_comment
Name-Email: $name_email
Expire-Date: $expire_date
%commit
%echo done
EOF
}

function gpg_key_list() {
  local flags="${1:-}"

  gpg --list-keys $flags 2>/dev/null
}

function gpg_short_key_list() {
  local flags="${1:-}"

  gpg --list-keys --keyid-format short $flags 2>/dev/null | awk '$1 == "pub" { print $2 }' | cut -d'/' -f2
}

function gpg_long_key_list() {
  local flags="${1:-}"

  gpg --list-keys --with-colons $flags 2>/dev/null | awk -F: '$1 == "fpr" { print $10 }'
}

function gpg_long_primary_key_list() {
  local flags="${1:-}"

  gpg --list-keys --with-colons $flags 2>/dev/null | awk -F: '$1 == "pub" {getline; if ($1 == "fpr") print $10}'
}

function gpg_secret_key_list() {
  local passphrase="$1"
  local flags="${2:---armor}"

  gpg --batch --yes --pinentry-mode=loopback --passphrase "$passphrase" --export-secret-keys $flags
}

function gpg_clean_keys() {
  local flags="${1:-}"

  gpg --list-secret-keys --with-colons $flags | awk -F: '$1 == "sec" { sec=1 } sec && $1 == "fpr" { print $10; sec=0 }' | xargs -r -n1 gpg --batch --yes --delete-secret-keys
  gpg --list-keys --with-colons $flags | awk -F: '$1 == "pub" { pub=1 } pub && $1 == "fpr" { print $10; pub=0 }' | xargs -r -n1 gpg --batch --yes --delete-keys
}

function is_gpg_key_exported() {
  local keyserver="${1:-keys.openpgp.org}"
  local key="$2"

  gpg --batch --keyserver "$keyserver" --search-key "$key" 2>&1 | grep -qv "not found on keyserver"
}

# Servers:
# - keys.openpgp.org
# - keyserver.ubuntu.com
# - pgp.mit.edu
function gpg_export_key() {
  local key_servers="${1:-keys.openpgp.org keyserver.ubuntu.com pgp.mit.edu}"
  local key="$2"

  for keyserver in $key_servers; do
    if ! is_gpg_key_exported "$keyserver" "$key"; then
      gpg --keyserver "$keyserver" --send-keys "$key"
    fi
  done
}
