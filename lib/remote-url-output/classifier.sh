#!/usr/bin/env bash
# Bounded classifier for executable Bash command candidates. The scanner owns
# AST extraction; this file owns variable provenance, recognized redaction
# boundaries, and finding reasons.

_REMOTE_URL_OUTPUT_TAINT_EVENTS=""
_REMOTE_URL_OUTPUT_SAFE_EVENTS=""
_REMOTE_URL_OUTPUT_REASON=""

remote_url_output_is_redactor_name() {
  local name="$1"
  [[ "$name" =~ (^|[_-])(redact|sanitize|scrub|mask)([_A-Za-z0-9.-]|$) ]]
}

remote_url_output_is_remote_name() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [[ "$lower" =~ (^|_)(remote|origin)($|_) ]] ||
    [[ "$lower" =~ ^(repo|repository|remote|origin)_(url|uri)$ ]] ||
    [[ "$lower" =~ ^(url|uri)_(remote|origin|repo|repository)$ ]]
}

remote_url_output_mark_event() {
  local kind="$1"
  local variable="$2"
  local line="$3"

  if [[ "$kind" == safe ]]; then
    _REMOTE_URL_OUTPUT_SAFE_EVENTS+="$variable"$'\t'"$line"$'\n'
  else
    _REMOTE_URL_OUTPUT_TAINT_EVENTS+="$variable"$'\t'"$line"$'\n'
  fi
}

remote_url_output_latest_event() {
  local events="$1"
  local wanted="$2"
  local through_line="$3"
  local variable line latest=0

  while IFS=$'\t' read -r variable line; do
    [[ "$variable" == "$wanted" ]] || continue
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    if [[ "$line" -le "$through_line" && "$line" -gt "$latest" ]]; then
      latest="$line"
    fi
  done <<< "$events"
  printf '%s\n' "$latest"
}

remote_url_output_variable_is_sensitive() {
  local variable="$1"
  local line="$2"
  local taint_line safe_line

  taint_line=$(remote_url_output_latest_event "$_REMOTE_URL_OUTPUT_TAINT_EVENTS" "$variable" "$line")
  safe_line=$(remote_url_output_latest_event "$_REMOTE_URL_OUTPUT_SAFE_EVENTS" "$variable" "$line")

  if [[ "$safe_line" -gt "$taint_line" ]]; then
    return 1
  fi
  if [[ "$taint_line" -gt 0 ]]; then
    return 0
  fi
  remote_url_output_is_remote_name "$variable"
}

remote_url_output_without_single_quotes() {
  local text="$1"
  local output="" char previous="" in_single=false
  local i

  for ((i = 0; i < ${#text}; i++)); do
    char="${text:i:1}"
    if [[ "$char" == "'" && "$previous" != "\\" ]]; then
      if [[ "$in_single" == true ]]; then
        in_single=false
      else
        in_single=true
      fi
      previous="$char"
      continue
    fi
    if [[ "$in_single" == false ]]; then
      output+="$char"
    fi
    previous="$char"
  done
  printf '%s\n' "$output"
}

remote_url_output_argument_is_redacted() {
  local argument function_name
  argument=$(remote_url_output_without_single_quotes "$1")
  if [[ ! "$argument" =~ ^\"?\$\(([_A-Za-z0-9.-]+)[[:space:]].*\)\"?$ ]]; then
    return 1
  fi
  function_name="${BASH_REMATCH[1]}"
  remote_url_output_is_redactor_name "$function_name"
}

remote_url_output_argument_has_sensitive_value() {
  local argument="$1"
  local line="$2"
  local text match variable

  remote_url_output_argument_is_redacted "$argument" && return 1
  text=$(remote_url_output_without_single_quotes "$argument")
  text=$(printf '%s\n' "$text" | sed -E 's/\$\([_A-Za-z0-9.-]*(redact|sanitize|scrub|mask)[_A-Za-z0-9.-]*[[:space:]][^)]*\)//g')
  while [[ "$text" =~ (\$\{?([A-Za-z_][A-Za-z0-9_]*)) ]]; do
    match="${BASH_REMATCH[1]}"
    variable="${BASH_REMATCH[2]}"
    if remote_url_output_variable_is_sensitive "$variable" "$line"; then
      return 0
    fi
    text="${text#*"$match"}"
  done
  [[ "$text" =~ [A-Za-z][A-Za-z0-9+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@ ]]
}

remote_url_output_source_has_redaction_pipeline() {
  local source="$1" function_name
  if [[ ! "$source" =~ \|[[:space:]]*([_A-Za-z0-9.-]+)([[:space:]]|$) ]]; then
    return 1
  fi
  function_name="${BASH_REMATCH[1]}"
  remote_url_output_is_redactor_name "$function_name"
}

remote_url_output_stderr_is_safe() {
  local source="$1" function_name
  local stderr_null_re='2>[[:space:]]*/dev/null([[:space:];)]|$)'
  local combined_null_re='>[[:space:]]*/dev/null[[:space:]]+2>&1([[:space:];)]|$)'

  [[ "$source" =~ $stderr_null_re ]] && return 0
  [[ "$source" =~ $combined_null_re ]] && return 0
  if [[ "$source" =~ 2\>[[:space:]]*\>\([[:space:]]*([_A-Za-z0-9.-]+) ]]; then
    function_name="${BASH_REMATCH[1]}"
    remote_url_output_is_redactor_name "$function_name" && return 0
  fi
  if [[ "$source" =~ 2\>\&1[[:space:]]*\|[[:space:]]*([_A-Za-z0-9.-]+) ]]; then
    function_name="${BASH_REMATCH[1]}"
    remote_url_output_is_redactor_name "$function_name" && return 0
  fi
  return 1
}

remote_url_output_classify_command() {
  local command="$1"
  local encoded_args="$2"
  local source="$3"
  local line="$4"
  local argument subcommand="" previous=""
  local -a args

  IFS=$'\037' read -r -a args <<< "$encoded_args"
  if [[ "$command" == command || "$command" == builtin ]]; then
    [[ ${#args[@]} -gt 0 ]] || return 1
    command="${args[0]}"
    args=("${args[@]:1}")
  fi
  command="${command##*/}"

  if [[ "$command" == printf || "$command" == echo ]]; then
    [[ "$source" =~ =[[:space:]]*\$\( ]] && return 1
    remote_url_output_source_has_redaction_pipeline "$source" && return 1
    for argument in "${args[@]}"; do
      if remote_url_output_argument_has_sensitive_value "$argument" "$line"; then
        _REMOTE_URL_OUTPUT_REASON="prints a remote URL without a recognized redaction boundary"
        return 0
      fi
    done
    return 1
  fi

  [[ "$command" == git ]] || return 1
  for argument in "${args[@]}"; do
    if [[ "$previous" == remote && "$argument" == get-url ]]; then
      if [[ "$source" =~ =[[:space:]]*\$\( ]] || remote_url_output_source_has_redaction_pipeline "$source"; then
        return 1
      fi
      _REMOTE_URL_OUTPUT_REASON="writes git remote get-url directly to output"
      return 0
    fi
    previous="$argument"
    case "$argument" in
      clone|fetch|push|ls-remote) [[ -z "$subcommand" ]] && subcommand="$argument" ;;
    esac
  done

  [[ -n "$subcommand" ]] || return 1
  for argument in "${args[@]}"; do
    if remote_url_output_argument_has_sensitive_value "$argument" "$line"; then
      if ! remote_url_output_stderr_is_safe "$source"; then
        _REMOTE_URL_OUTPUT_REASON="runs git $subcommand with a remote URL while credential-bearing stderr is exposed or captured unredacted"
        return 0
      fi
    fi
  done
  return 1
}
