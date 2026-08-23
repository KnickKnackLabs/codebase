#!/usr/bin/env bash
# Detect BATS tests that reconstruct this repository's Mise task dispatch path
# instead of calling the exported test wrapper.

_CODEBASE_BATS_PATH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_BATS_PATH_LIB_DIR/shell-files.sh"
# shellcheck source=./bats-public-task-path/bats-source.sh
source "$_CODEBASE_BATS_PATH_LIB_DIR/bats-public-task-path/bats-source.sh"

bats_public_task_path_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0
  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

bats_public_task_path_lint() {
  local encoded_targets="$1"
  local target resolved name toml file hit status failures=0 hit_count target_output
  local -a targets files

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$target")
  done < <(bats_public_task_path_parse_targets "$encoded_targets")
  if [[ ${#targets[@]} -eq 0 ]]; then
    printf '%s\n' 'ERROR: at least one target is required' >&2
    return 1
  fi

  for target in "${targets[@]}"; do
    resolved=$(resolve_target "$target")
    if [[ ! -e "$resolved" ]]; then
      printf 'ERROR: target does not exist: %s\n' "$resolved" >&2
      return 1
    fi
    name=$(basename "$resolved")
    toml="$resolved/mise.toml"
    if [[ -f "$toml" ]] && rg -q 'codebase:ignore bats-public-task-path' "$toml"; then
      printf 'SKIP  %s (codebase:ignore)\n' "$name"
      continue
    fi

    files=()
    if [[ -d "$resolved/test" ]]; then
      while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
      done < <(fd -t f -e bats --exclude fixtures . "$resolved/test" | LC_ALL=C sort)
    fi
    if [[ ${#files[@]} -eq 0 ]]; then
      printf 'OK    %s (no BATS test files found)\n' "$name"
      continue
    fi

    hit_count=0
    target_output=""
    for file in "${files[@]}"; do
      if hit=$(bats_public_task_path_scan_file "$file"); then
        :
      else
        status=$?
        return "$status"
      fi
      while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        target_output+="  ${file#"$resolved"/}:$hit"$'\n'
        hit_count=$((hit_count + 1))
      done <<< "$hit"
    done

    if [[ "$hit_count" -gt 0 ]]; then
      printf 'FAIL  %s: %s raw repository Mise dispatch(es) in BATS test bodies\n' \
        "$name" "$hit_count"
      printf '%s' "$target_output"
      # shellcheck disable=SC2016 # User guidance is intentionally literal.
      printf '%s\n' '  hint: call the exported test wrapper; use explicit `mise -C <fixture>` only for fixture workspaces.'
      failures=$((failures + 1))
    else
      printf 'OK    %s (%s BATS file(s) use public task paths)\n' "$name" "${#files[@]}"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
