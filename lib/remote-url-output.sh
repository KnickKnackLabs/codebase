#!/usr/bin/env bash
# Detect bounded Bash shapes that can print credential-bearing Git remote URLs.
# This is intentionally not general secret-flow analysis: it follows captured
# `git remote get-url` values within one file and recognizes a small public set
# of redaction names.

_CODEBASE_REMOTE_URL_OUTPUT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_REMOTE_URL_OUTPUT_CANDIDATE_RULE="$_CODEBASE_REMOTE_URL_OUTPUT_LIB_DIR/../rules/remote-url-output/candidates.yml"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_REMOTE_URL_OUTPUT_LIB_DIR/shell-files.sh"

# shellcheck source=./remote-url-output/classifier.sh
source "$_CODEBASE_REMOTE_URL_OUTPUT_LIB_DIR/remote-url-output/classifier.sh"

remote_url_output_parse_targets() {
  local encoded="$1"
  local parsed target

  [[ -n "$encoded" ]] || return 0
  if ! parsed=$(printf '%s' "$encoded" | xargs printf '%s\n'); then
    printf '%s\n' 'ERROR: could not parse target arguments' >&2
    return 1
  fi
  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done <<< "$parsed"
}

remote_url_output_source_has_ignore() {
  local source="$1"
  local line

  while IFS= read -r line; do
    if [[ "$line" =~ codebase:ignore[[:space:]]+remote-url-output[[:space:]]+--[[:space:]]+[^[:space:]] ]]; then
      return 0
    fi
  done <<< "$source"
  return 1
}

remote_url_output_load_source_lines() {
  local file="$1" line

  _REMOTE_URL_OUTPUT_SOURCE_LINES=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    _REMOTE_URL_OUTPUT_SOURCE_LINES+=("$line")
  done < "$file"
}

remote_url_output_set_source_range() {
  local first_line="$1"
  local last_line="$2"
  local index

  _REMOTE_URL_OUTPUT_SOURCE_RANGE=""
  for ((index = first_line - 1; index < last_line; index++)); do
    _REMOTE_URL_OUTPUT_SOURCE_RANGE+="${_REMOTE_URL_OUTPUT_SOURCE_LINES[$index]}"$'\n'
  done
  _REMOTE_URL_OUTPUT_SOURCE_RANGE="${_REMOTE_URL_OUTPUT_SOURCE_RANGE%$'\n'}"
}

remote_url_output_record_assignment() {
  local source="$1"
  local line="$2"
  local variable value direct_value

  _REMOTE_URL_OUTPUT_RECORDED_VARIABLE=""
  _REMOTE_URL_OUTPUT_RECORDED_PROVENANCE=""
  if [[ ! "$source" =~ ([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*= ]]; then
    return 0
  fi
  variable="${BASH_REMATCH[1]}"
  value="${source#*=}"
  _REMOTE_URL_OUTPUT_RECORDED_VARIABLE="$variable"
  remote_url_output_set_direct_assignment_value "$value"
  direct_value="$_REMOTE_URL_OUTPUT_DIRECT_ASSIGNMENT_VALUE"

  if [[ "$value" =~ (redact|sanitize|scrub|mask)[_A-Za-z0-9.-]*[[:space:]] ]]; then
    if remote_url_output_argument_has_sensitive_value "$value" "$line"; then
      _REMOTE_URL_OUTPUT_RECORDED_PROVENANCE=taint
      remote_url_output_mark_event taint "$variable" "$line"
    else
      _REMOTE_URL_OUTPUT_RECORDED_PROVENANCE=redacted
      remote_url_output_mark_event redacted "$variable" "$line"
    fi
  elif [[ "$value" =~ git[[:space:]]+remote[[:space:]]+get-url([[:space:]]|$) ]] ||
    { [[ ! "$value" =~ ^\"?\$\(.*\)\"?$ ]] && remote_url_output_argument_has_sensitive_value "$direct_value" "$line"; }; then
    _REMOTE_URL_OUTPUT_RECORDED_PROVENANCE=taint
    remote_url_output_mark_event taint "$variable" "$line"
  else
    _REMOTE_URL_OUTPUT_RECORDED_PROVENANCE=safe
    # Every assignment supersedes earlier provenance. A known-safe value must
    # clear stale taint, just as an unredacted value must clear stale safety.
    remote_url_output_mark_event safe "$variable" "$line"
  fi
}

remote_url_output_cleanup_scan_workspace() {
  local status=$?

  trap - EXIT
  if [[ -n "$scan_dir" ]] && ! rm -rf "$scan_dir"; then
    printf 'ERROR: could not remove the remote URL scan workspace: %s\n' "$scan_dir" >&2
    [[ "$status" -ne 0 ]] || status=1
  fi
  exit "$status"
}

remote_url_output_scan_files() (
  local ast_output candidates file staged_file current_file="" kind first last last_column first_byte last_byte command encoded_args
  local source candidate_source pipeline_suffix line trimmed ignore_status captured_variable captured_provenance
  local assignment_first_byte=-1 assignment_last_byte=-1 assignment_variable="" assignment_provenance=""
  local findings="" scan_dir index LC_ALL=C
  local -a original_files
  _REMOTE_URL_OUTPUT_SOURCE_LINES=()
  _REMOTE_URL_OUTPUT_SOURCE_RANGE=""
  _REMOTE_URL_OUTPUT_SOURCE_TEXT=""
  _REMOTE_URL_OUTPUT_RECORDED_VARIABLE=""
  _REMOTE_URL_OUTPUT_RECORDED_PROVENANCE=""

  original_files=("$@")
  scan_dir=""
  trap remote_url_output_cleanup_scan_workspace EXIT
  trap 'exit 130' HUP INT TERM
  if ! scan_dir=$(mktemp -d "${TMPDIR:-/tmp}/codebase-remote-url-output.XXXXXX"); then
    printf '%s\n' 'ERROR: could not create the remote URL scan workspace' >&2
    return 1
  fi
  for ((index = 0; index < ${#original_files[@]}; index++)); do
    staged_file="$scan_dir/$index.sh"
    if ! while IFS= read -r line || [[ -n "$line" ]]; do
      printf '%s\n' "$line"
    done < "${original_files[$index]}" > "$staged_file"; then
      printf 'ERROR: could not stage shell file for scanning: %s\n' "${original_files[$index]}" >&2
      return 1
    fi
  done

  if ! ast_output=$(ast-grep scan --threads 1 --rule "$_CODEBASE_REMOTE_URL_OUTPUT_CANDIDATE_RULE" --json=stream "$scan_dir" 2>&1); then
    printf '%s\n' 'ERROR: ast-grep could not inspect shell-file candidates' >&2
    printf '%s\n' "$ast_output" >&2
    return 1
  fi
  if ! candidates=$(printf '%s\n' "$ast_output" | jq -r '[.file, if .metaVariables.single.CMD? then "command" else "assignment" end, .range.start.line + 1, .range.end.line + 1, .range.end.column, .range.byteOffset.start, .range.byteOffset.end, (.metaVariables.single.CMD.text // ""), ((.metaVariables.multi.ARGS // []) | map(.text) | join("\u001f"))] | @tsv'); then
    printf '%s\n' 'ERROR: could not parse ast-grep candidate output' >&2
    return 1
  fi

  while IFS=$'\t' read -r staged_file kind first last last_column first_byte last_byte command encoded_args; do
    [[ -n "$staged_file" ]] || continue
    index="${staged_file##*/}"
    index="${index%.sh}"
    if [[ ! "$index" =~ ^[0-9]+$ || "$index" -ge ${#original_files[@]} ]]; then
      printf 'ERROR: ast-grep returned an unknown staged file: %s\n' "$staged_file" >&2
      return 1
    fi
    file="${original_files[$index]}"
    if [[ "$file" != "$current_file" ]]; then
      current_file="$file"
      _REMOTE_URL_OUTPUT_TAINT_EVENTS=""
      _REMOTE_URL_OUTPUT_SAFE_EVENTS=""
      _REMOTE_URL_OUTPUT_REDACTED_EVENTS=""
      _REMOTE_URL_OUTPUT_EVENT_SEQUENCE=0
      assignment_first_byte=-1
      assignment_last_byte=-1
      assignment_variable=""
      assignment_provenance=""
      remote_url_output_load_source_lines "$staged_file"
      _REMOTE_URL_OUTPUT_SOURCE_TEXT=$(< "$staged_file")
    fi

    if [[ ! "$first" =~ ^[0-9]+$ || ! "$last" =~ ^[0-9]+$ || ! "$last_column" =~ ^[0-9]+$ ||
      ! "$first_byte" =~ ^[0-9]+$ || ! "$last_byte" =~ ^[0-9]+$ || "$last_byte" -lt "$first_byte" ]]; then
      printf 'ERROR: ast-grep returned an invalid candidate range: %s..%s\n' "$first_byte" "$last_byte" >&2
      return 1
    fi
    remote_url_output_set_source_range "$first" "$last"
    source="$_REMOTE_URL_OUTPUT_SOURCE_RANGE"
    candidate_source="${_REMOTE_URL_OUTPUT_SOURCE_TEXT:$first_byte:$((last_byte - first_byte))}"
    pipeline_suffix="${_REMOTE_URL_OUTPUT_SOURCE_LINES[$((last - 1))]:$last_column}"
    if [[ "$kind" == assignment ]]; then
      remote_url_output_record_assignment "$candidate_source" "$first"
      assignment_first_byte="$first_byte"
      assignment_last_byte="$last_byte"
      assignment_variable="$_REMOTE_URL_OUTPUT_RECORDED_VARIABLE"
      assignment_provenance="$_REMOTE_URL_OUTPUT_RECORDED_PROVENANCE"
      continue
    fi

    if remote_url_output_source_has_ignore "$source"; then
      continue
    else
      ignore_status=$?
      [[ "$ignore_status" -eq 1 ]] || return "$ignore_status"
    fi

    captured_variable=""
    captured_provenance=""
    if [[ "$first_byte" -ge "$assignment_first_byte" && "$last_byte" -le "$assignment_last_byte" ]]; then
      captured_variable="$assignment_variable"
      captured_provenance="$assignment_provenance"
    fi
    if remote_url_output_classify_command "$command" "$encoded_args" "$pipeline_suffix" "$first" "$captured_variable" "$captured_provenance"; then
      line="${_REMOTE_URL_OUTPUT_SOURCE_LINES[$((first - 1))]}"
      trimmed="${line#"${line%%[![:space:]]*}"}"
      findings+="$file"$'\t'"$first: $_REMOTE_URL_OUTPUT_REASON: $trimmed"$'\n'
    fi
  done <<< "$candidates"
  printf '%s' "$findings"
)

remote_url_output_lint() {
  local encoded_targets="$1"
  local failures=0 parsed_targets target name toml discovered_files file rel scan_output hit hit_count target_output
  local -a targets files

  if ! parsed_targets=$(remote_url_output_parse_targets "$encoded_targets"); then
    return 1
  fi
  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done <<< "$parsed_targets"

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
    if [[ -f "$toml" ]] && rg -q 'codebase:ignore[[:space:]]+remote-url-output[[:space:]]+--[[:space:]]+[^[:space:]]' "$toml"; then
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
    if ! scan_output=$(remote_url_output_scan_files "${files[@]}"); then
      return 1
    fi
    while IFS=$'\t' read -r file hit; do
      [[ -n "$hit" ]] || continue
      rel="${file#"$target"/}"
      target_output+="  $rel:$hit"$'\n'
      hit_count=$((hit_count + 1))
    done <<< "$scan_output"

    if [[ "$hit_count" -gt 0 ]]; then
      printf 'FAIL  %s: %s credential-bearing remote URL output risk(s)\n' "$name" "$hit_count"
      printf '%s' "$target_output"
      printf '%s\n' '  hint: redact remote URLs and Git stderr before output, or add a reasoned rule-specific ignore when an unusual helper owns that boundary.'
      failures=$((failures + 1))
    else
      printf 'OK    %s (%s file(s) clean)\n' "$name" "${#files[@]}"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
