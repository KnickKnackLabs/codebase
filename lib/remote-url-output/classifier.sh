#!/usr/bin/env bash
# Classify executable Bash commands that may expose credential-bearing Git URLs.

_CODEBASE_REMOTE_URL_OUTPUT_CLASSIFIER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./provenance.sh
source "$_CODEBASE_REMOTE_URL_OUTPUT_CLASSIFIER_DIR/provenance.sh"

remote_url_output_find_git_subcommand() {
  local index=0 argument
  local -a arguments

  arguments=("$@")
  _REMOTE_URL_OUTPUT_GIT_SUBCOMMAND=""
  _REMOTE_URL_OUTPUT_GIT_SUBCOMMAND_INDEX=0
  while [[ "$index" -lt ${#arguments[@]} ]]; do
    argument="${arguments[$index]}"
    case "$argument" in
      -C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)
        index=$((index + 2))
        ;;
      --git-dir=*|--work-tree=*|--namespace=*|--super-prefix=*|--config-env=*|--exec-path=*)
        index=$((index + 1))
        ;;
      --exec-path)
        # `--exec-path` may be a query or may consume the following path.
        if [[ $((index + 1)) -lt ${#arguments[@]} && "${arguments[$((index + 1))]}" != -* ]]; then
          index=$((index + 2))
        else
          return 1
        fi
        ;;
      --)
        index=$((index + 1))
        [[ "$index" -lt ${#arguments[@]} ]] || return 1
        _REMOTE_URL_OUTPUT_GIT_SUBCOMMAND="${arguments[$index]}"
        _REMOTE_URL_OUTPUT_GIT_SUBCOMMAND_INDEX="$index"
        return 0
        ;;
      -*)
        index=$((index + 1))
        ;;
      *)
        _REMOTE_URL_OUTPUT_GIT_SUBCOMMAND="$argument"
        _REMOTE_URL_OUTPUT_GIT_SUBCOMMAND_INDEX="$index"
        return 0
        ;;
    esac
  done
  return 1
}

remote_url_output_suffix_has_redaction_pipeline() {
  local suffix="$1" function_name
  if [[ ! "$suffix" =~ ^[[:space:]]*\|[[:space:]]*([_A-Za-z0-9.-]+)([[:space:]]|$) ]]; then
    return 1
  fi
  function_name="${BASH_REMATCH[1]}"
  remote_url_output_is_redactor_name "$function_name"
}

remote_url_output_stdout_is_discarded() {
  local suffix="$1" context redirections
  local stdout_null_re='(^|[[:space:]])(1?>)[[:space:]]*/dev/null([[:space:])]|$)'

  context="${suffix%%;*}"
  context="${context%%&&*}"
  context="${context%%||*}"
  redirections="${context%%|*}"
  [[ "$redirections" =~ $stdout_null_re ]]
}

remote_url_output_stderr_is_safe() {
  local suffix="$1" function_name context redirections
  local stderr_null_re='2>[[:space:]]*/dev/null([[:space:])]|$)'
  local combined_null_re='>[[:space:]]*/dev/null[[:space:]]+2>&1([[:space:])]|$)'

  context="${suffix%%;*}"
  context="${context%%&&*}"
  context="${context%%||*}"
  redirections="${context%%|*}"
  [[ "$redirections" =~ $stderr_null_re ]] && return 0
  [[ "$redirections" =~ $combined_null_re ]] && return 0
  if [[ "$redirections" =~ 2\>[[:space:]]*\>\([[:space:]]*([_A-Za-z0-9.-]+) ]]; then
    function_name="${BASH_REMATCH[1]}"
    remote_url_output_is_redactor_name "$function_name" && return 0
  fi
  if [[ "$context" =~ ^[^|]*2\>\&1[[:space:]]*\|[[:space:]]*([_A-Za-z0-9.-]+) ]]; then
    function_name="${BASH_REMATCH[1]}"
    remote_url_output_is_redactor_name "$function_name" && return 0
  fi
  return 1
}

remote_url_output_classify_command() {
  local command="$1"
  local encoded_args="$2"
  local pipeline_suffix="$3"
  local line="$4"
  local captured_variable="$5"
  local captured_provenance="$6"
  local argument remote_action=""
  local index
  local -a args

  IFS=$'\037' read -r -a args <<< "$encoded_args"
  if [[ "$command" == command ]]; then
    while [[ ${#args[@]} -gt 0 ]]; do
      case "${args[0]}" in
        --) args=("${args[@]:1}"); break ;;
        -p) args=("${args[@]:1}") ;;
        -v|-V) return 1 ;;
        *) break ;;
      esac
    done
  fi
  if [[ "$command" == command || "$command" == builtin ]]; then
    [[ ${#args[@]} -gt 0 ]] || return 1
    command="${args[0]}"
    args=("${args[@]:1}")
  fi
  command="${command##*/}"

  if [[ "$command" == printf || "$command" == echo ]]; then
    remote_url_output_suffix_has_redaction_pipeline "$pipeline_suffix" && return 1
    remote_url_output_stdout_is_discarded "$pipeline_suffix" && return 1
    for argument in "${args[@]}"; do
      if remote_url_output_argument_has_sensitive_value "$argument" "$line"; then
        if [[ -n "$captured_variable" ]]; then
          if [[ "$captured_provenance" != redacted ]]; then
            remote_url_output_mark_event taint "$captured_variable" "$line"
          fi
          return 1
        fi
        _REMOTE_URL_OUTPUT_REASON="prints a remote URL without a recognized redaction boundary"
        return 0
      fi
    done
    return 1
  fi

  [[ "$command" == git ]] || return 1
  remote_url_output_find_git_subcommand "${args[@]}" || return 1

  if [[ "$_REMOTE_URL_OUTPUT_GIT_SUBCOMMAND" == remote ]]; then
    for ((index = _REMOTE_URL_OUTPUT_GIT_SUBCOMMAND_INDEX + 1; index < ${#args[@]}; index++)); do
      argument="${args[$index]}"
      [[ "$argument" == -* ]] && continue
      remote_action="$argument"
      break
    done
    if [[ "$remote_action" == get-url ]]; then
      if [[ -n "$captured_variable" ]]; then
        if [[ "$captured_provenance" != redacted ]]; then
          remote_url_output_mark_event taint "$captured_variable" "$line"
        fi
        return 1
      fi
      if remote_url_output_suffix_has_redaction_pipeline "$pipeline_suffix" ||
        remote_url_output_stdout_is_discarded "$pipeline_suffix"; then
        return 1
      fi
      _REMOTE_URL_OUTPUT_REASON="writes git remote get-url directly to output"
      return 0
    fi
    return 1
  fi

  case "$_REMOTE_URL_OUTPUT_GIT_SUBCOMMAND" in
    clone|fetch|push|ls-remote) ;;
    *) return 1 ;;
  esac
  for argument in "${args[@]}"; do
    if remote_url_output_argument_has_sensitive_value "$argument" "$line"; then
      if ! remote_url_output_stderr_is_safe "$pipeline_suffix"; then
        _REMOTE_URL_OUTPUT_REASON="runs git $_REMOTE_URL_OUTPUT_GIT_SUBCOMMAND with a remote URL while credential-bearing stderr is exposed or captured unredacted"
        return 0
      fi
    fi
  done
  return 1
}
