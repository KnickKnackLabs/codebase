#!/usr/bin/env bash
# Track bounded same-file remote URL provenance and recognized redaction names.

_REMOTE_URL_OUTPUT_TAINT_EVENTS=""
_REMOTE_URL_OUTPUT_SAFE_EVENTS=""
_REMOTE_URL_OUTPUT_REDACTED_EVENTS=""
_REMOTE_URL_OUTPUT_EVENT_SEQUENCE=0
_REMOTE_URL_OUTPUT_REASON=""
_REMOTE_URL_OUTPUT_GIT_SUBCOMMAND=""
_REMOTE_URL_OUTPUT_GIT_SUBCOMMAND_INDEX=0
_REMOTE_URL_OUTPUT_LATEST_EVENT=0
_REMOTE_URL_OUTPUT_WITHOUT_SINGLE_QUOTES=""
_REMOTE_URL_OUTPUT_WITHOUT_REDACTOR_CALLS=""
_REMOTE_URL_OUTPUT_DIRECT_ASSIGNMENT_VALUE=""

remote_url_output_is_redactor_name() {
  local name="$1"
  [[ "$name" =~ (^|[_-])(redact|sanitize|scrub|mask)([_A-Za-z0-9.-]|$) ]]
}

remote_url_output_is_remote_name() {
  local name="$1"
  local remote_re='([Rr][Ee][Mm][Oo][Tt][Ee]|[Oo][Rr][Ii][Gg][Ii][Nn])'
  local repo_re='([Rr][Ee][Pp][Oo]|[Rr][Ee][Pp][Oo][Ss][Ii][Tt][Oo][Rr][Yy])'
  local url_re='([Uu][Rr][Ll]|[Uu][Rr][Ii])'

  [[ "$name" =~ (^|_)$remote_re($|_) ]] ||
    [[ "$name" =~ ^($repo_re|$remote_re)_$url_re$ ]] ||
    [[ "$name" =~ ^${url_re}_($remote_re|$repo_re)$ ]]
}

remote_url_output_mark_event() {
  local kind="$1"
  local variable="$2"
  local line="$3"

  _REMOTE_URL_OUTPUT_EVENT_SEQUENCE=$((_REMOTE_URL_OUTPUT_EVENT_SEQUENCE + 1))
  case "$kind" in
    safe) _REMOTE_URL_OUTPUT_SAFE_EVENTS+="$variable"$'\t'"$line"$'\t'"$_REMOTE_URL_OUTPUT_EVENT_SEQUENCE"$'\n' ;;
    redacted) _REMOTE_URL_OUTPUT_REDACTED_EVENTS+="$variable"$'\t'"$line"$'\t'"$_REMOTE_URL_OUTPUT_EVENT_SEQUENCE"$'\n' ;;
    *) _REMOTE_URL_OUTPUT_TAINT_EVENTS+="$variable"$'\t'"$line"$'\t'"$_REMOTE_URL_OUTPUT_EVENT_SEQUENCE"$'\n' ;;
  esac
}

remote_url_output_set_latest_event() {
  local events="$1"
  local wanted="$2"
  local through_line="$3"
  local variable line sequence

  _REMOTE_URL_OUTPUT_LATEST_EVENT=0
  while IFS=$'\t' read -r variable line sequence; do
    [[ "$variable" == "$wanted" ]] || continue
    [[ "$line" =~ ^[0-9]+$ && "$sequence" =~ ^[0-9]+$ ]] || continue
    if [[ "$line" -le "$through_line" && "$sequence" -gt "$_REMOTE_URL_OUTPUT_LATEST_EVENT" ]]; then
      _REMOTE_URL_OUTPUT_LATEST_EVENT="$sequence"
    fi
  done <<< "$events"
}

remote_url_output_variable_is_sensitive() {
  local variable="$1"
  local line="$2"
  local taint_line safe_line redacted_line

  remote_url_output_set_latest_event "$_REMOTE_URL_OUTPUT_TAINT_EVENTS" "$variable" "$line"
  taint_line="$_REMOTE_URL_OUTPUT_LATEST_EVENT"
  remote_url_output_set_latest_event "$_REMOTE_URL_OUTPUT_SAFE_EVENTS" "$variable" "$line"
  safe_line="$_REMOTE_URL_OUTPUT_LATEST_EVENT"
  remote_url_output_set_latest_event "$_REMOTE_URL_OUTPUT_REDACTED_EVENTS" "$variable" "$line"
  redacted_line="$_REMOTE_URL_OUTPUT_LATEST_EVENT"

  if [[ "$redacted_line" -gt "$taint_line" && "$redacted_line" -gt "$safe_line" ]]; then
    return 1
  fi
  if [[ "$safe_line" -gt "$taint_line" ]]; then
    remote_url_output_is_remote_name "$variable"
    return
  fi
  if [[ "$taint_line" -gt 0 ]]; then
    return 0
  fi
  remote_url_output_is_remote_name "$variable"
}

remote_url_output_set_without_single_quotes() {
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
  _REMOTE_URL_OUTPUT_WITHOUT_SINGLE_QUOTES="$output"
}

remote_url_output_text_is_redacted() {
  local text="$1" function_name
  if [[ ! "$text" =~ ^\"?\$\(([_A-Za-z0-9.-]+)[[:space:]].*\)\"?$ ]]; then
    return 1
  fi
  function_name="${BASH_REMATCH[1]}"
  remote_url_output_is_redactor_name "$function_name"
}

remote_url_output_set_without_redactor_calls() {
  local text="$1" match
  local redactor_call_re='(\$\([_A-Za-z0-9.-]*(redact|sanitize|scrub|mask)[_A-Za-z0-9.-]*[[:space:]][^)]*\))'

  while [[ "$text" =~ $redactor_call_re ]]; do
    match="${BASH_REMATCH[1]}"
    text="${text/"$match"/}"
  done
  _REMOTE_URL_OUTPUT_WITHOUT_REDACTOR_CALLS="$text"
}

remote_url_output_set_direct_assignment_value() {
  local text="$1" match
  local transformed_re='(\$\{[A-Za-z_][A-Za-z0-9_]*[^A-Za-z0-9_}][^}]*\})'

  while [[ "$text" =~ $transformed_re ]]; do
    match="${BASH_REMATCH[1]}"
    text="${text/"$match"/}"
  done
  _REMOTE_URL_OUTPUT_DIRECT_ASSIGNMENT_VALUE="$text"
}

remote_url_output_text_has_credential_url() {
  local text="$1"

  [[ "$text" =~ [A-Za-z][A-Za-z0-9+.-]*://[^/@[:space:]:]+:[^/@[:space:]]+@ ]] ||
    [[ "$text" =~ [Hh][Tt][Tt][Pp][Ss]?://[^/@[:space:]]+@ ]]
}

remote_url_output_argument_has_sensitive_value() {
  local argument="$1"
  local line="$2"
  local text match variable

  remote_url_output_set_without_single_quotes "$argument"
  text="$_REMOTE_URL_OUTPUT_WITHOUT_SINGLE_QUOTES"
  remote_url_output_text_is_redacted "$text" && return 1
  remote_url_output_text_has_credential_url "$argument" && return 0
  remote_url_output_set_without_redactor_calls "$text"
  text="$_REMOTE_URL_OUTPUT_WITHOUT_REDACTOR_CALLS"
  while [[ "$text" =~ (\$\{?([A-Za-z_][A-Za-z0-9_]*)) ]]; do
    match="${BASH_REMATCH[1]}"
    variable="${BASH_REMATCH[2]}"
    if remote_url_output_variable_is_sensitive "$variable" "$line"; then
      return 0
    fi
    text="${text#*"$match"}"
  done
  remote_url_output_text_has_credential_url "$text"
}
