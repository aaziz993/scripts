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
INTERPOLATE_KEY='\s*(?|('"$KEY_PATTERN"')|'"'($SINGLE_QUOTED_STRING_PLAIN_PATTERN)'"'|"('"$DOUBLE_QUOTED_STRING_PLAIN_PATTERN"')")\s*'
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
  local strict=true

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
    -s | --strict)
      strict="${2:-true}"
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

  function skip_evaluator() {
    printf "%s" "$1"
  }

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
        local offset=$index

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

        check '(( ${#path_keys[@]} == 0 ))' "Empty interpolate"
        check '[[ "${source:index:1}" != "}" ]]' "Missing closing brace at '$index' ${source:index}"

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
              -ud "$unescape_dollars" -s "$strict" "$getter" "$evaluator" <<<"$value")"
            cache[$path_plain]="$value"
          elif ((status > 1)); then
            [[ "$strict" == true ]] && error "Unresolved '$path_plain'" "$status"
            value="${source:offset:index-offset}"
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
                -ud "$unescape_dollars" -s "$strict" "$getter" "$evaluator" <<<"$value")"
              cache[$path_plain]="$value"
            elif ((status > 1)); then
              [[ "$strict" == true ]] && error "Unresolved '$path_plain'" "$status"
              value="${source:offset:index-offset}"
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
        script="$(evaluate_string skip_evaluator "${source:index-1}")"
        script="${script:1:-1}"

        ((index += ${#script} + 1))

        value="$("$evaluator" "$script")"

        local status=$?
        ((status != 0)) && error "Evaluate '$script'" "$status"

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
}

function evaluate_string() {
  local evaluator="${1:-bash_c}"
  local source
  source="$(src "${2:-}")"
  local output=""
  local index=0
  depth=0

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
      ((depth++))

      output+="<"
      continue
    fi

    # Closing brace
    if [[ "${source:index:1}" == ">" ]]; then
      ((index += 1))
      ((depth--))

      output+=">"

      if ((depth == 0)); then
        "$evaluator" "$output"
        return
      fi

      continue
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

  error "Unbalanced evaluate '<>'"
}

function getter() {
  local -n keys="$1"
return 2
  printf "%s" "$(join_to_string keys ".")"
}

substitute_string -i true -s false getter "" "Some \${   test.    \"o\"   .'other'   } \$\"some\".opa.jet"
