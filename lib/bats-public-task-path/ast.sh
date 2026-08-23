#!/usr/bin/env bash
# Shared ast-grep mechanics for BATS public-task-path classification.

if [[ "${_CODEBASE_BATS_PATH_AST_LOADED:-0}" -eq 1 ]]; then
  return 0
fi
_CODEBASE_BATS_PATH_AST_LOADED=1

_CODEBASE_BATS_PATH_AST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_BATS_PATH_RULE_DIR="$_CODEBASE_BATS_PATH_AST_DIR/../../rules/bats-public-task-path"

bats_public_task_path_ast_scan() {
  local source="$1"
  local rule="$2"
  local format="${3:-compact}"

  ast-grep scan \
    --rule "$_CODEBASE_BATS_PATH_RULE_DIR/$rule" \
    --json="$format" "$source"
}

bats_public_task_path_ast_is_parseable() {
  local source="$1"
  local errors

  if ! errors=$(bats_public_task_path_ast_scan "$source" bash-errors.yml stream 2>&1); then
    printf 'ERROR: ast-grep could not inspect BATS Bash syntax: %s\n' "$source" >&2
    printf '%s\n' "$errors" >&2
    return 2
  fi
  [[ -z "$errors" ]]
}

bats_public_task_path_ast_whole_match() {
  local command="$1"
  local pattern="$2"
  local output match

  output=$(printf '%s\n' "$command" | ast-grep run \
    --lang bash --pattern "$pattern" --json=compact --stdin 2>/dev/null) || true
  match=$(printf '%s\n' "$output" | jq -c \
    '[.[] | select(.charCount.leading == 0 and .charCount.trailing == 0)][0] // empty')
  [[ -n "$match" ]] || return 1
  printf '%s\n' "$match"
}

bats_public_task_path_ast_strip_prefix() {
  local command="$1"
  local rule="$2"
  local scratch_dir scratch matches end

  scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/codebase-bats-prefix.XXXXXX")
  scratch="$scratch_dir/command.sh"
  printf '%s\n' "$command" > "$scratch"
  if ! matches=$(bats_public_task_path_ast_scan "$scratch" "$rule" 2>/dev/null); then
    rm -rf "$scratch_dir"
    return 1
  fi
  rm -rf "$scratch_dir"
  end=$(printf '%s\n' "$matches" | jq -r \
    'if length == 0 then 0 else ([.[].range.byteOffset.end] | max) end')
  [[ "$end" -gt 0 ]] || return 1
  printf '%s\n' "${command:end}" | sed 's/^[[:space:]]*//'
}
