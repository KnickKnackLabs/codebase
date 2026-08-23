#!/usr/bin/env bash
# Classify direct Mise dispatch and workspace selection.

if [[ "${_CODEBASE_BATS_PATH_MISE_LOADED:-0}" -eq 1 ]]; then
  return 0
fi
_CODEBASE_BATS_PATH_MISE_LOADED=1

_CODEBASE_BATS_PATH_MISE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./ast.sh
source "$_CODEBASE_BATS_PATH_MISE_DIR/ast.sh"
bats_public_task_path_env_preamble_is_valid() {
  local match="$1"
  local token needs_value=0

  while IFS= read -r token; do
    if [[ "$needs_value" -eq 1 ]]; then
      needs_value=0
      continue
    fi
    if [[ "$token" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      continue
    fi
    case "$token" in
      -u|--unset|-C|--chdir|-S|--split-string)
        needs_value=1
        ;;
      -*) ;;
      *) return 1 ;;
    esac
  done < <(printf '%s\n' "$match" | jq -r '.metaVariables.multi.ENV[]?.text')

  [[ "$needs_value" -eq 0 ]]
}
bats_public_task_path_dispatch_match() {
  local command="$1"
  local inspect stripped pattern candidate attempt

  [[ "$command" == *mise* ]] || return 1
  inspect="$command"

  for attempt in 1 2; do
    # shellcheck disable=SC2016 # ast-grep metavariables are literal.
    for pattern in \
      'mise $$$PRE run $$$ARGS' \
      'command mise $$$PRE run $$$ARGS' \
      'command env $$$ENV mise $$$PRE run $$$ARGS' \
      'run mise $$$PRE run $$$ARGS' \
      'run command mise $$$PRE run $$$ARGS' \
      'run command env $$$ENV mise $$$PRE run $$$ARGS' \
      'env $$$ENV mise $$$PRE run $$$ARGS' \
      'run env $$$ENV mise $$$PRE run $$$ARGS'; do
      if candidate=$(bats_public_task_path_ast_whole_match "$inspect" "$pattern") && \
        bats_public_task_path_env_preamble_is_valid "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done

    [[ "$attempt" -eq 1 ]] || break
    if stripped=$(bats_public_task_path_ast_strip_prefix "$command" mise-assignments.yml); then
      inspect="$stripped"
    else
      break
    fi
  done
  return 1
}
bats_public_task_path_is_repo_root_token() {
  local token="$1"

  # shellcheck disable=SC2016 # Source tokens are compared literally.
  case "$token" in
    .|./|'$REPO_DIR'|'${REPO_DIR}'|'"$REPO_DIR"'|'"${REPO_DIR}"'|\
      '$REPO_DIR/'|'${REPO_DIR}/'|'$REPO_DIR/.'|'${REPO_DIR}/.'|\
      '"$REPO_DIR/"'|'"${REPO_DIR}/"'|'"$REPO_DIR/."'|'"${REPO_DIR}/."'|\
      '"$REPO_DIR"/'|'"${REPO_DIR}"/'|'"$REPO_DIR"/.'|'"${REPO_DIR}"/.'|\
      "'\$REPO_DIR'"|"'\${REPO_DIR}'"|'$MISE_CONFIG_ROOT'|'${MISE_CONFIG_ROOT}'|\
      '$MISE_CONFIG_ROOT/'|'${MISE_CONFIG_ROOT}/'|'$MISE_CONFIG_ROOT/.'|'${MISE_CONFIG_ROOT}/.'|\
      '"$MISE_CONFIG_ROOT"'|'"${MISE_CONFIG_ROOT}"'|'"$MISE_CONFIG_ROOT/"'|\
      '"${MISE_CONFIG_ROOT}/"'|'"$MISE_CONFIG_ROOT/."'|'"${MISE_CONFIG_ROOT}/."'|\
      '"$MISE_CONFIG_ROOT"/'|'"${MISE_CONFIG_ROOT}"/'|'"$MISE_CONFIG_ROOT"/.'|\
      '"${MISE_CONFIG_ROOT}"/.'|"'\$MISE_CONFIG_ROOT'"|"'\${MISE_CONFIG_ROOT}'") return 0 ;;
    *) return 1 ;;
  esac
}
bats_public_task_path_match_is_raw() {
  local match="$1"
  local token next target=""
  local -a pre
  local i

  pre=()
  while IFS= read -r token; do
    pre+=("$token")
  done < <(printf '%s\n' "$match" | jq -r '.metaVariables.multi.PRE[]?.text')

  for ((i = 0; i < ${#pre[@]}; i++)); do
    token=${pre[$i]}
    case "$token" in
      -C|--cd)
        next=$((i + 1))
        [[ "$next" -lt "${#pre[@]}" ]] || return 0
        target=${pre[$next]}
        break
        ;;
      -C?*)
        target=${token#-C}
        break
        ;;
      --cd=*)
        target=${token#--cd=}
        break
        ;;
    esac
  done

  # No explicit alternate workspace means Mise dispatches the test's current
  # repository and bypasses its exported wrapper. An explicit canonical root is
  # the same defect. Other explicit workspaces are fixture/integration targets.
  [[ -z "$target" ]] && return 0
  bats_public_task_path_is_repo_root_token "$target"
}
