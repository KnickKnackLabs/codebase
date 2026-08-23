#!/usr/bin/env bash
# Normalize BATS syntax, map commands to source lines, and classify test bodies.

if [[ "${_CODEBASE_BATS_PATH_SOURCE_LOADED:-0}" -eq 1 ]]; then
  return 0
fi
_CODEBASE_BATS_PATH_SOURCE_LOADED=1

_CODEBASE_BATS_PATH_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ast.sh
source "$_CODEBASE_BATS_PATH_SOURCE_DIR/ast.sh"
# shellcheck source=./command.sh
source "$_CODEBASE_BATS_PATH_SOURCE_DIR/command.sh"

bats_public_task_path_normalize() {
  local source="$1"
  local line test_count=0
  local test_pattern='^[[:blank:]]*@test[[:blank:]]+(.*[^[:blank:]])[[:blank:]]+\{(.*)$'
  local comment_pattern='^[[:blank:]]*(function[[:blank:]]+)?[^[:blank:]()]+[[:blank:]]*\(?\)?[[:blank:]]+\{[[:blank:]]+#[[:blank:]]*@test[[:blank:]]*$'

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $test_pattern ]]; then
      test_count=$((test_count + 1))
      printf '__codebase_bats_test_%s() {%s\n' "$test_count" "${BASH_REMATCH[2]}"
    elif [[ "$line" =~ $comment_pattern ]]; then
      test_count=$((test_count + 1))
      printf '__codebase_bats_test_%s() { # @test\n' "$test_count"
    else
      printf '%s\n' "$line"
    fi
  done < "$source"
}
bats_public_task_path_scan_file() {
  local source="$1"
  local normalized_dir normalized commands item line command original status

  normalized_dir=$(mktemp -d "${TMPDIR:-/tmp}/codebase-bats-normalized.XXXXXX")
  normalized="$normalized_dir/normalized.sh"
  bats_public_task_path_normalize "$source" > "$normalized"

  if bats_public_task_path_ast_is_parseable "$normalized"; then
    :
  else
    status=$?
    printf 'ERROR: BATS Bash syntax is not structurally parseable: %s\n' "$source" >&2
    rm -rf "$normalized_dir"
    return "$status"
  fi
  if ! commands=$(bats_public_task_path_ast_scan "$normalized" commands-in-tests.yml 2>&1); then
    printf 'ERROR: ast-grep could not inspect BATS test bodies: %s\n' "$source" >&2
    printf '%s\n' "$commands" >&2
    rm -rf "$normalized_dir"
    return 2
  fi
  rm -rf "$normalized_dir"

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    line=$(printf '%s\n' "$item" | jq -r '.range.start.line + 1')
    command=$(printf '%s\n' "$item" | jq -r '.text')
    original=$(awk -v line="$line" 'NR == line { print; exit }' "$source")
    [[ "$original" == *'codebase:ignore bats-public-task-path'* ]] && continue

    if bats_public_task_path_command_is_raw "$command"; then
      printf '%s: %s\n' "$line" "${original#"${original%%[![:space:]]*}"}"
    else
      status=$?
      if [[ "$status" -ne 1 ]]; then
        printf 'ERROR: could not inspect nested Bash payload at %s:%s\n' "$source" "$line" >&2
        return "$status"
      fi
    fi
  done < <(printf '%s\n' "$commands" | jq -c '.[]')
}
