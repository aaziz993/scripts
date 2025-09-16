#!/usr/bin/env bash
# shellcheck disable=SC2016
# shellcheck disable=SC2034
# shellcheck disable=SC2119
# shellcheck disable=SC2120
# shellcheck disable=SC2317
# shellcheck disable=SC2329
# shellcheck disable=SC2086

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/string.sh"

function uncomment() {
  local source="${1:-}"

  src "$source" | yq '... comments=""'
}

# Converts to pretty YAML format.
function pretty_yaml() {
  local source="${1:-}"

  src "$source" | yq -P
}

# Converts to pretty YAML format except scalars.
function pretty_yaml_objects() {
  local source="${1:-}"

  src "$source" | yq '(.. | select(tag == "!!seq" or tag == "!!map")) style= ""'
}

function type() {
  local source="${1:-}"

  src "$source" | yq 'type'
}

function is_type() {
  local type="$1"
  local source="${2:-}"

  [[ "$(src "$source" | type)" == "$type" ]] && return 0

  return 1
}

function is_bool() {
  is_type "!!bool"<<< "$1"
}

function is_int() {
  is_type "!!int"<<< "$1"
}

function is_float() {
  is_type "!!float"<<< "$1"
}

function is_str() {
  is_type "!!str"<<< "$1"
}

function is_scalar() {
  is_bool "$1" || is_int "$1" || is_float "$1" || is_str "$1"
}

function is_seq() {
  is_type "!!seq"<<< "$1"
}

function is_map() {
  is_type "!!map"<<< "$1"
}

function is_object() {
  is_seq "$1" || is_map "$1"
}

function coalesce() {
  local default="$1"
  local source="${2:-}"

  src "$source" | yq "select(. == null) |= $default"
}

function contains() {
  local path="$1"
  local source="${2:-}"

  src "$source" | yq '. as $root | .'"$path"' | path as $path | $root | eval($path.[:-1] | join(".") | "." + .) | has($path[-1])' | grep -q true >/dev/null
}

function get() {
  local path="$1"
  local source="${2:-}"

  src "$source" | yq -r=false ".$path"
}

function assign() {
  local path="$1"
  local assign="${2:-=}"
  local value="$3"
  local source="${4:-}"

  if is_str "$value" && [[ "$value" =~ ^[[:space:]]*[|\>]-?[[:space:]]*\\n ]]; then
    value="${value#"${BASH_REMATCH[0]}"}"
  fi

  yq -r=false eval-all '(select(fileIndex==0) // {}) as $source | $source'"${path:+.$path} $assign"' select(fileIndex==1) | $source' <(src "$source") <(printf "%s" "$value")
}

function slice() {
  local -n paths="$1"
  local source="${2:-}"

  src "$source" | yq -r=false "($(printf '.%s,' "${paths[@]}" | sed 's/,$//'))"' as $i ireduce({}; setpath($i | path; $i))'
}

function replace() {
  local to_path="$1"
  local assignment="${2:-=}"
  local from_path="$3"
  local source="${4:-}"

  src "$source" | yq -r=false ".$to_path $assignment .$from_path | del(.$from_path)"
}

function delete() {
  local path="$1"
  local source="${2:-}"

  src "$source" | yq -r=false "del(.$path)"
}

function deletes() {
  local -n paths="$1"
  local source="${2:-}"

  src "$source" | yq -r=false "del($(printf '.%s,' "${paths[@]}" | sed 's/,$//'))"
}

function merge() {
  local -n sources="$1"
  local merge="${2:-*+}"

  yq eval-all -r=false ". as \$item ireduce ({}; . $merge \$item)" <(printf '%s\n---\n' "${sources[@]}")
}

function substitute() {
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
    -ib | --interpolate_braced)
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

  local global_source
  global_source="$(src "${2:-}")"
  local global_values="${1:-$global_source}"
  local -A global_cache=()

  function _getter() {
    local -n keys="$1"
    local path
    local value

    path="$(join_to_string keys ".")"

    contains "$path" "$global_values" || return $UNRESOLVED

    value="$(get "$path" "$global_values")"

    is_scalar "$value"

    echo "V:$value:$?">&2

    if is_scalar "$value"; then
      printf "%s" "$value"
      return $DEEP_RESOLVE
    else
      _substitute "$value"
    fi
  }

  function _evaluator() {
    local value="$1"

    bash -c "
      set -euo pipefail
      set -o errtrace
      $(declare -f)
      $(declare -p SINGLE_QUOTED_STRING_PATTERN DOUBLE_QUOTED_STRING_PATTERN EVEN_DOLLARS_PATTERN INTERPOLATE_KEY INTERPOLATE_START_PATTERN INTERPOLATE_BRACED_START_PATTERN EVALUATE_START_PATTERN SUBSTITUTE_OTHER_PATTERN EVALUATE_OTHER_PATTERN DEEP_RESOLVE UNRESOLVED)
      $(declare -p interpolate interpolate_braced evaluate unescape_dollars global_source global_values global_cache)
      function var() {
        local path=\"\$1\"
        ! contains \"\$path\" \"\$global_source\" && return \$UNRESOLVED
        _substitute_string0 \"\$path\" \"\$global_source\"
        local status=\$?
        ((status == 0 || status==\$UNRESOLVED)) && printf \"%s\" \"\$global_value\"
        return \$status
      }
      $value
    "
  }

  local global_value

  function _substitute_string0() {
    local path="$1"
    local source="$2"

    if [[ -v global_cache[$path] ]]; then
      global_value="${global_cache[$path]}"
    else
      global_value="$(get "$path" "$source")"

      if is_str "$global_value"; then
        local substituted_value
        substituted_value="$(substitute_string -i "$interpolate" -ib "$interpolate_braced" -e "$evaluate" \
          -ud "$unescape_dollars" _getter _evaluator global_cache "$global_value")"

        local status=$?
        ((status == 0)) && global_value="$substituted_value"

        ((status == 0 || status == UNRESOLVED)) && global_cache[$path]="$global_value"

        return $status
      fi
    fi
  }

  function _substitute() {
    local source="$1"

    while IFS= read -r path; do
      _substitute_string0 "$path" "$source"

      local status=$?
      ((status != 0 && status != UNRESOLVED)) && error "Unresolved '$path'" $status

      source="$(assign "$path" = "$global_value" "$source")"
    done < <(yq '.. | select(tag == "!!str") | path | . as $path | map(["\"", ., "\""] | join("")) | join(".")' <<<"$source")

    printf "%s" "$source"
  }

  _substitute "$global_source"
}

function assign_in_file() {
  local path="$1"
  local assign="${2:-=}"
  local value="$3"
  local source="$4"

  if is_str "$value" && [[ "$value" =~ ^[[:space:]]*[|\>]-?[[:space:]]*\\n ]]; then
    value="${value#"${BASH_REMATCH[0]}"}"
  fi

  yq -i -r=false eval-all '(select(fileIndex==0) // {}) as $source | $source'"${path:+.$path} $assign"' select(fileIndex==1) | $source' "$source" <(printf "%s" "$value")
}

function slice_in_file() {
  local -n paths="$1"
  local source="$2"

  yq -i "($(printf '.%s,' "${paths[@]}" | sed 's/,$//'))"' as $i ireduce({}; setpath($i | path; $i))' "$source"
}

function replace_in_file() {
  local to_path="$1"
  local assignment="${2:-=}"
  local from_path="$3"
  local source="$4"

  yq -i ".$to_path $assignment .$from_path | del(.$from_path)" "$source"
}

function delete_in_file() {
  local path="$1"
  local source="$2"

  yq -i "del(.$path)" "$source"
}

function deletes_in_file() {
  local -n paths="$1"
  local source="$2"

  yq -i "del($(printf '.%s,' "${paths[@]}" | sed 's/,$//'))" "$source"
}

function merge_files() {
  local -n files="$1"
  local merge="${2:-*+}"

  yq eval-all -r=false ". as \$item ireduce ({}; . $merge \$item)" "${files[@]}"
}

function decode_file() {
  local file="$1"
  local imports="${2:-default_imports}"
  local decoder="${3:-default_decoder}"
  local merger="${4:-default_merger}"
  local -A merged_files=()
  local merged

  function default_imports() {
    local file="$1"
    local decoded_file="$2"
    local file_dir

    file_dir="$(dirname -- "$file")"

    while IFS= read -r path; do
      realpath -- "$file_dir/$path"
    done < <(yq -r ".imports[]" <<<"$decoded_file")
  }

  function default_decoder() {
    local file="$1"

    cat "$file"
  }

  function default_merger() {
    local decoded_file="$1"
    local -n decoded_imports="$2"
    local merged_imports

    merged_imports="$(merge decoded_imports "*n")"
    decoded_file="$(substitute -ud false "" "$decoded_file" | substitute "$merged_imports")"
    assign "" "*=" "$decoded_file" "$merged_imports"
  }

  ansi_span "\033[0;32mFile:" " $file\n" >&2

  _decode_file() {
    local file="$1"
    local prefix="$2"
    local decoded_file
    local import_file
    local merged_import_files=()

    decoded_file="$("$decoder" "$file")"
    merged_files[$file]=""

    local import_files
    mapfile -t import_files < <("$imports" "$file" "$decoded_file")
    local total=${#import_files[@]}
    local index

    for index in "${!import_files[@]}"; do
      import_file="${import_files[$index]}"
      local is_last=$((index == total - 1 ? 1 : 0))
      local connector="├──"
      [[ $is_last -eq 1 ]] && connector="└──"

      if [[ -v merged_files[$import_file] ]]; then
        if [[ -n "${merged_files[$import_file]}" ]]; then
          ansi_span "$prefix$connector " "\033[0;33mFile:" " $import_file ↻\n" >&2
          merged_import_files+=("${merged_files[$import_file]}")
        else
          error "Detected cycle '$file' -> '$import_file'"
        fi
      else
        ansi_span "$prefix$connector " "\033[0;32mFile:" " $import_file \n" >&2

        local next_prefix="$prefix"
        [[ $is_last -eq 1 ]] && next_prefix+="   " || next_prefix+="│  "

        _decode_file "$import_file" "$next_prefix"
        merged_import_files+=("$merged")
      fi
    done

    merged="$("$merger" "$decoded_file" merged_import_files)"
    merged_files[$file]="$merged"
  }

  _decode_file "$file" ""

  printf "%s" "$merged"
}

example=$(
  cat <<'EOF'
func: ${values.str}
test: 90
values:
  testing: Testing
  greet: Hello
  nested: ${values.greet}, World!
  j: ${values.some}
  some:
    structure: vAL ${greet}
  str: >
    Something ${values.nested} $<echo $((98+546))> $<var values.j> Other
  str2: |
    Greetings $test
EOF
)

substitute -i true "" "$example"