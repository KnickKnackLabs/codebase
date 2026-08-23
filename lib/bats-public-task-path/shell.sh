#!/usr/bin/env bash
# Decode and classify statically quoted nested Bash payloads.

if [[ "${_CODEBASE_BATS_PATH_SHELL_LOADED:-0}" -eq 1 ]]; then
  return 0
fi
_CODEBASE_BATS_PATH_SHELL_LOADED=1

_CODEBASE_BATS_PATH_SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ast.sh
source "$_CODEBASE_BATS_PATH_SHELL_DIR/ast.sh"
# shellcheck source=./mise.sh
source "$_CODEBASE_BATS_PATH_SHELL_DIR/mise.sh"

bats_public_task_path_decode_static_word() {
  local word="$1"
  local body result="" char next
  local backslash=$'\\'
  local i

  if [[ "$word" == \'*\' && ${#word} -ge 2 ]]; then
    printf '%s\n' "${word:1:${#word}-2}"
    return 0
  fi
  if [[ "$word" != \"*\" || ${#word} -lt 2 ]]; then
    return 1
  fi

  body=${word:1:${#word}-2}
  for ((i = 0; i < ${#body}; i++)); do
    char=${body:i:1}
    if [[ "$char" == "$backslash" && $((i + 1)) -lt ${#body} ]]; then
      next=${body:i+1:1}
      case "$next" in
        "$backslash"|'"'|'$'|'`')
          result+="$next"
          i=$((i + 1))
          continue
          ;;
        $'\n')
          i=$((i + 1))
          continue
          ;;
      esac
    fi
    result+="$char"
  done
  printf '%s\n' "$result"
}

bats_public_task_path_shell_payload() {
  local command="$1"
  local inspect stripped pattern match word attempt

  [[ "$command" == *bash* ]] || return 1
  [[ "$command" == *-c* || "$command" == *-lc* ]] || return 1
  inspect="$command"

  for attempt in 1 2; do
    # shellcheck disable=SC2016 # ast-grep metavariables are literal.
    for pattern in \
      'bash -c $SCRIPT' \
      'bash -c $SCRIPT $$$REST' \
      'bash -lc $SCRIPT' \
      'bash -lc $SCRIPT $$$REST' \
      'run bash -c $SCRIPT' \
      'run bash -c $SCRIPT $$$REST' \
      'run bash -lc $SCRIPT' \
      'run bash -lc $SCRIPT $$$REST' \
      'env $$$ENV bash -c $SCRIPT' \
      'env $$$ENV bash -c $SCRIPT $$$REST' \
      'env $$$ENV bash -lc $SCRIPT' \
      'env $$$ENV bash -lc $SCRIPT $$$REST' \
      'run env $$$ENV bash -c $SCRIPT' \
      'run env $$$ENV bash -c $SCRIPT $$$REST' \
      'run env $$$ENV bash -lc $SCRIPT' \
      'run env $$$ENV bash -lc $SCRIPT $$$REST'; do
      if match=$(bats_public_task_path_ast_whole_match "$inspect" "$pattern"); then
        word=$(printf '%s\n' "$match" | jq -r '.metaVariables.single.SCRIPT.text')
        bats_public_task_path_decode_static_word "$word"
        return $?
      fi
    done

    [[ "$attempt" -eq 1 ]] || break
    if stripped=$(bats_public_task_path_ast_strip_prefix "$command" shell-assignments.yml); then
      inspect="$stripped"
    else
      break
    fi
  done
  return 1
}

bats_public_task_path_fixture_payload() {
  local payload="$1"
  local pattern match dir

  # This is the maintained copied-fixture form: select another workspace and
  # scrub the parent test's REPO_DIR before asking Mise to resolve the task.
  # Require it to be the whole payload so surrounding root dispatch cannot hide.
  # shellcheck disable=SC2016 # ast-grep metavariables are literal.
  pattern='cd $DIR && env -u REPO_DIR mise $$$PRE run $$$ARGS'
  if ! match=$(bats_public_task_path_ast_whole_match "$payload" "$pattern"); then
    return 1
  fi
  dir=$(printf '%s\n' "$match" | jq -r '.metaVariables.single.DIR.text')
  if printf '%s\n' "$match" | jq -e '
    (.metaVariables.multi.PRE // [])
    | any((.text | startswith("-C")) or .text == "--cd" or (.text | startswith("--cd=")))
  ' >/dev/null && bats_public_task_path_match_is_raw "$match"; then
    return 1
  fi
  ! bats_public_task_path_is_repo_root_token "$dir"
}

bats_public_task_path_script_has_raw_dispatch() {
  local payload="$1"
  local scratch_dir scratch errors commands command match

  bats_public_task_path_fixture_payload "$payload" && return 1

  scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/codebase-bats-payload.XXXXXX")
  scratch="$scratch_dir/payload.sh"
  printf '%s\n' "$payload" > "$scratch"

  if ! errors=$(bats_public_task_path_ast_scan "$scratch" bash-errors.yml stream 2>&1); then
    rm -rf "$scratch_dir"
    return 2
  fi
  if [[ -n "$errors" ]]; then
    rm -rf "$scratch_dir"
    return 2
  fi

  if ! commands=$(bats_public_task_path_ast_scan "$scratch" commands.yml 2>&1); then
    rm -rf "$scratch_dir"
    return 2
  fi
  rm -rf "$scratch_dir"

  while IFS= read -r command; do
    [[ -n "$command" ]] || continue
    if match=$(bats_public_task_path_dispatch_match "$command") && \
      bats_public_task_path_match_is_raw "$match"; then
      return 0
    fi
  done < <(printf '%s\n' "$commands" | jq -r '.[].text')
  return 1
}
