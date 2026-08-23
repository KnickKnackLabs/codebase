#!/usr/bin/env bash
# Compose direct Mise and nested shell command classification.

if [[ "${_CODEBASE_BATS_PATH_COMMAND_LOADED:-0}" -eq 1 ]]; then
  return 0
fi
_CODEBASE_BATS_PATH_COMMAND_LOADED=1

_CODEBASE_BATS_PATH_COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./mise.sh
source "$_CODEBASE_BATS_PATH_COMMAND_DIR/mise.sh"
# shellcheck source=./shell.sh
source "$_CODEBASE_BATS_PATH_COMMAND_DIR/shell.sh"

bats_public_task_path_command_is_raw() {
  local command="$1"
  local match payload status

  if match=$(bats_public_task_path_dispatch_match "$command") && \
    bats_public_task_path_match_is_raw "$match"; then
    return 0
  fi

  if payload=$(bats_public_task_path_shell_payload "$command"); then
    if bats_public_task_path_script_has_raw_dispatch "$payload"; then
      return 0
    else
      status=$?
      [[ "$status" -eq 1 ]] || return "$status"
    fi
  fi
  return 1
}
