#!/usr/bin/env bash

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/env.sh"

# Return best IPv4: public if reachable, else local interface IP, else 127.0.0.1
function get_ip() {
  local ip

  # 1) Try public IP (curl/dig/wget fallbacks)
  ip="$(curl -fsS https://api.ipify.org 2>/dev/null)" ||
    ip="$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)" ||
    ip="$(wget -qO- https://api.ipify.org 2>/dev/null)"

  # basic IPv4 sanity check
  if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf "%s" "$ip"
    return 0
  fi

  # 2) Local IPv4 (Linux: iproute2)
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
    [[ -n $ip ]] && printf "%s" "$ip" && return 0
  fi

  # 3) macOS
  if [[ $(uname) == "Darwin" ]]; then
    ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)"
    [[ -n $ip ]] && printf "%s" "$ip" && return 0
  fi

  # 4) Generic fallback
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n $ip ]]; then
    printf "%s" "$ip"
    return 0
  fi

  # 5) Last resort
  printf "%s" "127.0.0.1"
}

# Set hosts in os hosts file
function hosts_set() {
  local -n hosts="$1"
  local host
  local os

  os="$(os_name)"

  local hosts_file="/etc/hosts"

  case "$os" in
  Darwin | Linux) ;;
  MINGW* | MSYS* | CYGWIN*) hosts_file="/c/Windows/System32/drivers/etc/hosts" ;;
  *)
    echo "Unsupported $os OS"
    return 1
    ;;
  esac

  local ip
  ip="$(get_ip)"

  for host in "${hosts[@]}"; do
    host="$ip $host"

    grep -Fxq "$host" "$hosts_file" || {
      ([[ -w $hosts_file ]] && echo "$host" >>"$hosts_file") || echo "$host" | sudo tee -a "$hosts_file" >/dev/null
      echo -e "\033[0;32mSet $host\033[0m in $os \"$hosts_file\""
    }
  done
}

get_ip