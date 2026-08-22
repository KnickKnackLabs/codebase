#!/usr/bin/env bash
# Detect redirection-only `exec` commands that persistently redirect stderr in
# the current shell. Process-replacing `exec program ... 2>...` commands are
# intentionally outside this rule because the original shell does not resume.

_CODEBASE_EXEC_STDERR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_EXEC_STDERR_RULE="$_CODEBASE_EXEC_STDERR_LIB_DIR/../rules/exec-stderr-persistence/redirection-only-exec.yml"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_EXEC_STDERR_LIB_DIR/shell-files.sh"

exec_stderr_persistence_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0
  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

exec_stderr_persistence_range_has_ignore() {
  local file="$1"
  local first_line="$2"
  local last_line="$3"
  local line

  while IFS= read -r line; do
    if [[ "$line" =~ codebase:ignore[[:space:]]+exec-stderr-persistence[[:space:]]+.+ ]]; then
      return 0
    fi
  done < <(sed -n "${first_line},${last_line}p" "$file")
  return 1
}

exec_stderr_persistence_range_is_async() {
  local file="$1"
  local last_line="$2"
  local end_column="$3"
  local LC_ALL=C line suffix

  line=$(sed -n "${last_line}p" "$file")
  suffix="${line:$end_column}"
  [[ "$suffix" =~ ^[[:space:]]*\&([[:space:]#]|$) ]]
}

exec_stderr_persistence_scan_file() {
  local file="$1"
  local ast_output zero_based_start zero_based_end end_column first_line last_line
  local line trimmed

  if ! ast_output=$(ast-grep scan --stdin --rule "$_CODEBASE_EXEC_STDERR_RULE" --json=stream < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not scan %s\n' "$file" >&2
    printf '%s\n' "$ast_output" >&2
    return 1
  fi

  while IFS=$'\t' read -r zero_based_start zero_based_end end_column; do
    [[ -n "$zero_based_start" ]] || continue
    first_line=$((zero_based_start + 1))
    last_line=$((zero_based_end + 1))

    if exec_stderr_persistence_range_is_async "$file" "$last_line" "$end_column"; then
      continue
    fi

    if exec_stderr_persistence_range_has_ignore "$file" "$first_line" "$last_line"; then
      continue
    fi

    line=$(sed -n "${first_line}p" "$file")
    trimmed="${line#"${line%%[![:space:]]*}"}"
    printf '%s: %s\n' "$first_line" "$trimmed"
  done < <(
    printf '%s\n' "$ast_output" |
      jq -r '[.range.start.line, .range.end.line, .range.end.column] | @tsv'
  )
}

exec_stderr_persistence_lint() {
  local encoded_targets="$1"
  local failures=0 target name toml discovered_files file rel scan_output hit hit_count target_output
  local -a targets files

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done < <(exec_stderr_persistence_parse_targets "$encoded_targets")

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
    if [[ -f "$toml" ]] && rg -q 'codebase:ignore[[:space:]]+exec-stderr-persistence([[:space:]]|$)' "$toml"; then
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
      if ! scan_output=$(exec_stderr_persistence_scan_file "$file"); then
        return 1
      fi
      while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        target_output+="  $rel:$hit"$'\n'
        hit_count=$((hit_count + 1))
      done <<< "$scan_output"
    done

    if [[ "$hit_count" -gt 0 ]]; then
      printf 'FAIL  %s: %s persistent stderr redirection(s)\n' "$name" "$hit_count"
      printf '%s' "$target_output"
      # shellcheck disable=SC2016 # User guidance intentionally shows a literal path variable.
      printf '%s\n' '  hint: scope stderr outside the exec, for example `{ exec 3<>"$path"; } 2>/dev/null`, or save and restore stderr explicitly.'
      failures=$((failures + 1))
    else
      printf 'OK    %s (%s file(s) clean)\n' "$name" "${#files[@]}"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
