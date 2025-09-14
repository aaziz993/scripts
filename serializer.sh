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

function is_int() {
  local source="${1:-}"
  local type
  type="$(src "$source" | type)"

  [[ "$type" == "!!int" ]] && return 0

  return 1
}

function is_str() {
  local source="${1:-}"
  local type
  type="$(src "$source" | type)"

  [[ "$type" == "!!str" ]] && return 0

  return 1
}

function is_seq() {
  local source="${1:-}"
  local type
  type="$(src "$source" | type)"

  [[ "$type" == "!!seq" ]] && return 0

  return 1
}

function is_map() {
  local source="${1:-}"
  local type
  type="$(src "$source" | type)"

  [[ "$type" == "!!map" ]] && return 0

  return 1
}

function is_scalar() {
  local source
  local type

  source="$(src "${1:-}")"

  is_int "$source" || is_str "$source" && return 0

  return 1
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

  if is_str <<<"$value" && [[ "$value" =~ ^[[:space:]]*[|\>]-?[[:space:]]*\\n ]]; then
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
  local strict=true

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

  local global_source
  global_source="$(src "${2:-}")"
  local global_values="${1:-$global_source}"
  local -A global_cache=()

  function inner_getter() {
    local -n keys="$1"
    local path
    local value

    path="$(join_to_string keys ".")"

    contains "$path" "$global_values" || return 2

    value="$(get "$path" "$global_values")"

    if is_scalar <<<"$value"; then
      printf "%s" "$value"
    else
      inner_substitute "$value"
      return 1
    fi

    return 0
  }

  function inner_evaluator() {
    local value="$1"

    bash -c "
        $(declare -f)
        $(declare -p SINGLE_QUOTED_STRING_PATTERN DOUBLE_QUOTED_STRING_PATTERN EVEN_DOLLARS_PATTERN INTERPOLATE_KEY INTERPOLATE_START_PATTERN INTERPOLATE_BRACED_START_PATTERN EVALUATE_START_PATTERN SUBSTITUTE_OTHER_PATTERN EVALUATE_OTHER_PATTERN)
        $(declare -p interpolate interpolate_braced evaluate unescape_dollars global_source global_values global_cache)
        function var() {
          inner_substitute_string \"\$1\" \"\$global_source\"
        }
        set -e
        $value
    "
  }

  function inner_substitute_string() {
    local path="$1"
    local source="$2"
    local value

    if [[ -v "${global_cache[$path]}" ]]; then
      value="${global_cache[$path]}"
    else
      value="$(get "$path" "$source")"

      if is_str <<<"$value"; then
        value="$(substitute_string -i "$interpolate" -ib "$interpolate_braced" -e "$evaluate" -ud "$unescape_dollars" \
          -s "$strict" inner_getter inner_evaluator <<<"$value")"
        global_cache[$path]="$value"
      fi
    fi

    printf "%s" "$value"
  }

  function inner_substitute() {
    local source="$1"

    while IFS= read -r path; do
      local value
      value="$(inner_substitute_string "$path" "$source")"

      source="$(assign "$path" = "$value" "$source")"
    done < <(yq '.. | select(tag == "!!str") | path | . as $path | map(["\"", ., "\""] | join("")) | join(".")' <<<"$source")

    printf "%s" "$source"
  }

  inner_substitute "$global_source"
}

function assign_in_file() {
  local path="$1"
  local assign="${2:-=}"
  local value="$3"
  local source="$4"

  if is_str <<<"$value" && [[ "$value" =~ ^[[:space:]]*[|\>]-?[[:space:]]*\\n ]]; then
    value="${value#"${BASH_REMATCH[0]}"}"
  fi

  yq -i -r=false eval-all '(select(fileIndex==0) // {}) as $source | $source'"${path:+.$path} $assign"' select(fileIndex==1) | $source'  "$source" <(printf "%s" "$value")
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

    decoded_file="$(substitute -ud false -s false "" "$decoded_file" | substitute "$merged_imports")"

    assign "" "*=" "$decoded_file" "$merged_imports"
  }

  function decode_file_inner() {
    local file="$1"
    local depth="$2"
    local decoded_file
    local import_file
    local merged_import_files=()

    local indent
    if ((depth == 0)); then
      indent=""
    else
      indent="$(printf '    %.0s' $(seq 1 "$depth"))"
    fi

    ansi_span "\033[0;32mFile:" " $file\n" >&2

    decoded_file="$("$decoder" "$file")"

    merged_files[$file]=

    while IFS= read -r import_file; do
      printf "%s└──" "$indent" >&2

      if [[ -v merged_files[$import_file] ]]; then
        if [[ -n "${merged_files[$import_file]}" ]]; then
          ansi_span "\033[0;33mFile:" " $import_file ↻\n" >&2
          merged_import_files+=("${merged_files[$import_file]}")
        else
          error "Detected cycle '$file' -> '$import_file'"
        fi
      else
        decode_file_inner "$import_file" $((depth + 1))
        merged_import_files+=("$merged")
      fi
    done < <("$imports" "$file" "$decoded_file")

    merged="$("$merger" "$decoded_file" merged_import_files)"

    merged_files[$file]="$merged"
  }

  decode_file_inner "$file" 0

  printf "%s" "$merged"
}
