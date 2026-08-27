#!/usr/bin/env bash
# Detect process substitutions whose producer status is unavailable to the
# parent shell. This is a syntactic safety boundary: the rule does not infer
# whether a producer can fail or whether empty output is acceptable.

_CODEBASE_PROCESS_SUBSTITUTION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_PROCESS_SUBSTITUTION_RULE="$_CODEBASE_PROCESS_SUBSTITUTION_LIB_DIR/../rules/process-substitution-status/process-substitution.yml"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_PROCESS_SUBSTITUTION_LIB_DIR/shell-files.sh"

process_substitution_status_parse_targets() {
  local encoded="$1"
  local parsed target

  [[ -n "$encoded" ]] || return 0
  if ! parsed=$(printf '%s' "$encoded" | xargs printf '%s\n'); then
    printf '%s\n' 'ERROR: could not parse target arguments' >&2
    return 1
  fi
  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done <<< "$parsed"
}

process_substitution_status_range_has_ignore() {
  local file="$1"
  local first_line="$2"
  local last_line="$3"
  local lines line

  if ! lines=$(sed -n "${first_line},${last_line}p" "$file"); then
    printf 'ERROR: could not read suppression range in %s\n' "$file" >&2
    return 2
  fi
  while IFS= read -r line; do
    if [[ "$line" =~ codebase:ignore[[:space:]]+process-substitution-status[[:space:]]+--[[:space:]]+[^[:space:]] ]]; then
      return 0
    fi
  done <<< "$lines"
  return 1
}

process_substitution_status_scan_file() {
  local file="$1"
  local ast_output ranges zero_based_start zero_based_end first_line last_line line trimmed ignore_status

  if ! ast_output=$(ast-grep scan --stdin --rule "$_CODEBASE_PROCESS_SUBSTITUTION_RULE" --json=stream < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not scan %s\n' "$file" >&2
    printf '%s\n' "$ast_output" >&2
    return 1
  fi

  if ! ranges=$(printf '%s\n' "$ast_output" | jq -r '[.range.start.line, .range.end.line] | @tsv'); then
    printf 'ERROR: could not parse ast-grep output for %s\n' "$file" >&2
    return 1
  fi

  while IFS=$'\t' read -r zero_based_start zero_based_end; do
    [[ -n "$zero_based_start" ]] || continue
    first_line=$((zero_based_start + 1))
    last_line=$((zero_based_end + 1))

    if process_substitution_status_range_has_ignore "$file" "$first_line" "$last_line"; then
      continue
    else
      ignore_status=$?
      [[ "$ignore_status" -eq 1 ]] || return "$ignore_status"
    fi

    if ! line=$(sed -n "${first_line}p" "$file"); then
      printf 'ERROR: could not read finding line in %s\n' "$file" >&2
      return 1
    fi
    trimmed="${line#"${line%%[![:space:]]*}"}"
    printf '%s: %s\n' "$first_line" "$trimmed"
  done <<< "$ranges"
}

process_substitution_status_lint() {
  local encoded_targets="$1"
  local failures=0 parsed_targets target name toml discovered_files file rel scan_output hit hit_count target_output
  local -a targets files

  if ! parsed_targets=$(process_substitution_status_parse_targets "$encoded_targets"); then
    return 1
  fi
  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done <<< "$parsed_targets"

  if [[ ${#targets[@]} -eq 0 ]]; then
    printf '%s\n' 'ERROR: at least one target is required' >&2
    return 1
  fi

  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      printf 'ERROR: target does not exist: %s\n' "$target" >&2
      return 1
    fi

    name=$(basename "$target")
    toml="$target/mise.toml"
    if [[ -f "$toml" ]] && rg -q 'codebase:ignore[[:space:]]+process-substitution-status[[:space:]]+--[[:space:]]+[^[:space:]]' "$toml"; then
      printf 'SKIP  %s (codebase:ignore)\n' "$name"
      continue
    fi

    if ! discovered_files=$(discover_shell_files "$target"); then
      printf 'ERROR: could not discover shell files in %s\n' "$target" >&2
      return 1
    fi

    files=()
    while IFS= read -r file; do
      [[ -n "$file" ]] && files+=("$file")
    done <<< "$discovered_files"

    if [[ ${#files[@]} -eq 0 ]]; then
      printf 'OK    %s (no shell files found)\n' "$name"
      continue
    fi

    hit_count=0
    target_output=""
    for file in "${files[@]}"; do
      rel="${file#"$target"/}"
      if ! scan_output=$(process_substitution_status_scan_file "$file"); then
        return 1
      fi
      while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        target_output+="  $rel:$hit"$'\n'
        hit_count=$((hit_count + 1))
      done <<< "$scan_output"
    done

    if [[ "$hit_count" -gt 0 ]]; then
      printf 'FAIL  %s: %s hidden process-substitution producer status(es)\n' "$name" "$hit_count"
      printf '%s' "$target_output"
      printf '%s\n' '  hint: write producer output to a snapshot, check the producer command, then consume the snapshot.'
      failures=$((failures + 1))
    else
      printf 'OK    %s (%s file(s) clean)\n' "$name" "${#files[@]}"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
