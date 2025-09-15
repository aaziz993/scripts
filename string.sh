#!/usr/bin/env bash
# shellcheck disable=SC2016
# shellcheck disable=SC2119
# shellcheck disable=SC2317
# shellcheck disable=SC2329

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/log.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/io.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ansi.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/array.sh"
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/env.sh"

ID_PATTERN='[_\p{L}][_\p{L}\p{N}]*'
KEY_PATTERN='[_\p{L}\p{N}][_\p{L}\p{N}-]*'
SINGLE_QUOTED_STRING_PLAIN_PATTERN="(?:[^'\\\\]|\\.)*"
SINGLE_QUOTED_STRING_PATTERN="'$SINGLE_QUOTED_STRING_PLAIN_PATTERN'"
DOUBLE_QUOTED_STRING_PLAIN_PATTERN='(?:[^"\\\\]|\\.)*'
DOUBLE_QUOTED_STRING_PATTERN='"'"$DOUBLE_QUOTED_STRING_PLAIN_PATTERN"'"'

function is_blank() {
  local source

  source="$(src "${1:-}")"

  [[ -z "${source//[[:space:]]/}" ]]
}

function trim_start() {
  local trim="$1"
  local source

  source="$(src "${2:-}")"

  [[ $source == "$trim"* ]] && source="${source#"$trim"}"

  printf '%s' "$source"
}

function trim_end() {
  local trim="$1"
  local source

  source="$(src "${2:-}")"

  [[ $source == *"$trim" ]] && source="${source%"$trim"}"

  printf '%s' "$source"
}

function trim() {
  local trim="$1"
  local source="${2:-}"

  src "$source" | trim_start "$trim" | trim_end "$trim"
}

function escape() {
  local source

  source="$(src "${1:-}")"

  printf "%q" "$source"
}

function halve() {
  local source

  source="$(src "${1:-}")"

  printf "%s" "${source:0:$((${#source} / 2))}"
}

function match_at() {
  local regex="$1"
  local index="$2"
  local source

  source="$(src "${3:-}")"

  perl -CS -MJSON::PP=encode_json -e '
    use strict;
    use warnings;
    
    my ($input, $regex) = @ARGV;


    if( $input =~ qr/^$regex/ ) {
      my @groups = map { defined $_ ? $_ : "" } @{^CAPTURE};
      print encode_json({
        groupValues => [$&, @groups]
      });
    } else {
      print encode_json({
        groupValues => []
      });
    }
  ' -- "${source:$index}" "$regex"
}

EVEN_DOLLARS_PATTERN='(?:\$\$)+'
INTERPOLATE_KEY='\s*(?|('"$KEY_PATTERN"')|\[(\d+)\]|'"'($SINGLE_QUOTED_STRING_PLAIN_PATTERN)'"'|"('"$DOUBLE_QUOTED_STRING_PLAIN_PATTERN"')")\s*'
INTERPOLATE_START_PATTERN='\$'
INTERPOLATE_BRACED_START_PATTERN='\$\{'
EVALUATE_START_PATTERN='\$\<'
SUBSTITUTE_OTHER_PATTERN='[^$]+'
EVALUATE_OTHER_PATTERN='[^"<>]+'

function substitute_string() {
  local interpolate=false
  local interpolate_braced=true
  local evaluate=true
  local unescape_dollars=true

  while [[ "$1" == -* ]]; do
    case "$1" in
    -i | --interpolate)
      interpolate="${2:-true}"
      shift 2
      ;;
    -ib | --interpolate-braced)
      interpolate_braced="${2:-true}"
      shift 2
      ;;
    -e | --evaluate)
      evaluate="${2:-true}"
      shift 2
      ;;
    -ud | --unescape-dollars)
      unescape_dollars="${2:-true}"
      shift 2
      ;;
    *)
      echo "Unknown option $1"
      shift
      ;;
    esac
  done

  local getter="${1:-bash_env}"
  local evaluator="${2:-bash_c}"
  local source
  source="$(src "${3:-}")"
  local output=""
  local index=0
  local -A cache=()

  while ((index < ${#source})); do
    local groups=()

    if [[ "$interpolate" == true || "$interpolate_braced" == true || "$evaluate" == true ]]; then
      while IFS= read -r item; do
        groups+=("$(jq -r '@base64d' <<<"$item")")
      done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$EVEN_DOLLARS_PATTERN" $index "$source")")
      if ((${#groups[@]} > 0)); then
        ((index += ${#groups[0]}))

        local dollars="${groups[1]}"

        [[ "$unescape_dollars" == true ]] && dollars="$(halve <<<"$dollars")"

        output+="$dollars"
        continue
      fi
    fi

    if [[ "$interpolate_braced" == true ]]; then
      while IFS= read -r item; do
        groups+=("$(jq -r '@base64d' <<<"$item")")
      done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$INTERPOLATE_BRACED_START_PATTERN" $index "$source")")
      if ((${#groups[@]} > 0)); then
        ((index += ${#groups[0]}))

        local -a path_keys=()

        while true; do
          groups=()
          while IFS= read -r item; do
            groups+=("$(jq -r '@base64d' <<<"$item")")
          done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$INTERPOLATE_KEY" $index "$source")")

          ((${#groups[@]} == 0)) && break

          ((index += ${#groups[0]}))

          path_keys+=("${groups[1]}")

          [[ "${source:index:1}" == "." ]] && ((index += 1))
        done

        check '(( ${#path_keys[@]} == 0 ))' "Empty interpolate at '$index' in $source"
        check '[[ "${source:index:1}" != "}" ]]' "Missing } at '$index' in $source"

        ((index += 1))

        local path_plain
        path_plain="$(join_to_string path_keys ".")"
        local value

        if [[ -v "${cache[$path_plain]}" ]]; then
          value="${cache[$path_plain]}"
        else
          value="$("$getter" path_keys)"

          local status=$?
          if ((status == 0)); then
            value="$(substitute_string -i "$interpolate" -ib "$interpolate_braced" -e "$evaluate" \
              -ud "$unescape_dollars" "$getter" "$evaluator" <<<"$value")"
            cache[$path_plain]="$value"
          elif ((status != 1)); then
            return 1
          fi
        fi

        output+="$value"
        continue
      fi
    fi

    if [[ "$interpolate" == true ]]; then
      while IFS= read -r item; do
        groups+=("$(jq -r '@base64d' <<<"$item")")
      done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$INTERPOLATE_START_PATTERN" $index "$source")")
      if ((${#groups[@]} > 0)); then
        local offset=$index

        ((index += "${#groups[0]}"))

        local -a path_keys=()

        while true; do
          groups=()
          while IFS= read -r item; do
            groups+=("$(jq -r '@base64d' <<<"$item")")
          done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$INTERPOLATE_KEY" $index "$source")")

          ((${#groups[@]} == 0)) && break

          ((index += "${#groups[0]}"))

          path_keys+=("${groups[1]}")

          [[ "${source:index:1}" == "." ]] && ((index += 1))
        done

        if ((${#path_keys[@]} == 0)); then
          index=$offset
        else
          local path_plain
          path_plain="$(join_to_string path_keys ".")"
          local value

          if [[ -v "${cache[$path_plain]}" ]]; then
            value="${cache[$path_plain]}"
          else
            value="$("$getter" path_keys)"

            local status=$?
            if ((status == 0)); then
              value="$(substitute_string -i "$interpolate" -ib "$interpolate_braced" -e "$evaluate" \
                -ud "$unescape_dollars" "$getter" "$evaluator" <<<"$value")"
              cache[$path_plain]="$value"
            elif ((status != 1)); then
              return 1
            fi
          fi

          output+="$value"
          continue
        fi
      fi
    fi

    if [[ "$evaluate" == true ]]; then
      while IFS= read -r item; do
        groups+=("$(jq -r '@base64d' <<<"$item")")
      done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$EVALUATE_START_PATTERN" $index "$source")")
      if ((${#groups[@]} > 0)); then
        ((index += ${#groups[0]}))

        local script
        script="$(evaluate_string_parser "${source:index-1}")"

        ((index += ${#script} + 1))

        value="$("$evaluator" "$script")"

        local status=$?
        ((status != 0)) && return 1

        output+="$value"
        continue
      fi
    fi

    while IFS= read -r item; do
      groups+=("$(jq -r '@base64d' <<<"$item")")
    done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$SUBSTITUTE_OTHER_PATTERN" $index "$source")")
    if ((${#groups[@]} > 0)); then
      ((index += ${#groups[0]}))

      output+="${groups[0]}"
      continue
    fi

    output+="${source:index:1}"
    ((index += 1))
  done

  printf "%s" "$output"
  return 0
}

function evaluate_string_parser() {
  local source
  source="$(src "${1:-}")"
  local output=""
  local index=1

  [[ "${source:0:1}" != "<" ]] && error "Missing < at '0' in $source"

  while ((index < ${#source})); do
    local groups=()

    # Single-quoted value
    while IFS= read -r item; do
      groups+=("$(jq -r '@base64d' <<<"$item")")
    done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$SINGLE_QUOTED_STRING_PATTERN" $index "$source")")

    if ((${#groups[@]} > 0)); then
      ((index += ${#groups[0]}))

      output+="${groups[0]}"
      continue
    fi

    # Double-quoted value
    while IFS= read -r item; do
      groups+=("$(jq -r '@base64d' <<<"$item")")
    done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$DOUBLE_QUOTED_STRING_PATTERN" $index "$source")")
    if ((${#groups[@]} > 0)); then
      ((index += ${#groups[0]}))

      output+="${groups[0]}"
      continue
    fi

    # Opening brace
    if [[ "${source:index:1}" == "<" ]]; then
      ((index += 1))

      error "Extra < at '$index' in $source"
      continue
    fi

    # Closing brace
    if [[ "${source:index:1}" == ">" ]]; then
      ((index += 1))

      printf "%s" "$output"
      return
    fi

    while IFS= read -r item; do
      groups+=("$(jq -r '@base64d' <<<"$item")")
    done < <(jq -c '.groupValues[] | @base64' <<<"$(match_at "$EVALUATE_OTHER_PATTERN" $index "$source")")
    if ((${#groups[@]} > 0)); then
      ((index += ${#groups[0]}))

      output+="${groups[0]}"
      continue
    fi

    output+="${source:index:1}"
    ((index += 1))
  done

  error "Missing > at '${#source}' in '$source'"
}

function getter() {
  local -n keys="$1"
  echo 87
  return 1
}

function evaluator() {
  local value="$1"

  bash -c "
  set -euo pipefail    # fail fast, catch unset variables, propagate pipeline failures
  set -o errtrace       # propagate ERR trap into functions/subshells
  $(declare -f)
  $(declare -p SINGLE_QUOTED_STRING_PATTERN DOUBLE_QUOTED_STRING_PATTERN EVEN_DOLLARS_PATTERN INTERPOLATE_KEY INTERPOLATE_START_PATTERN INTERPOLATE_BRACED_START_PATTERN EVALUATE_START_PATTERN SUBSTITUTE_OTHER_PATTERN EVALUATE_OTHER_PATTERN)
  var() {
        local -a path_keys=(\"\$1\")
        getter path_keys
    }
    $value
  "
}

substitute_string -s false getter evaluator 'Some $<val=$(var test)||exit $?;echo $((val + 1))>'
