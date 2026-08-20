#!/usr/bin/env bash
# Narrow detector for known unsafe consumers of variadic Mise Usage values.
#
# This intentionally recognizes two finite source patterns: a declared
# variadic usage_* expansion directly under static `eval`, and a static `read`
# command with only r/a option words, one array name, and one final direct
# here-string carrying exactly that declared expansion. It is not a Bash
# dataflow or shell-word analyzer.

_CODEBASE_VARIADIC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_VARIADIC_RULE_DIR="$_CODEBASE_VARIADIC_LIB_DIR/../rules/variadic-args"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_VARIADIC_LIB_DIR/shell-files.sh"

variadic_args_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0
  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

variadic_args_declarations() {
  local file="$1"
  local line spec name legacy
  local arg_re flag_re long_re legacy_re

  arg_re='^#USAGE[[:space:]]+arg[[:space:]]+"(\[|<)([A-Za-z_][A-Za-z0-9_]*)(\.\.\.)?(\]|>)'
  flag_re='^#USAGE[[:space:]]+flag[[:space:]]+"([^"]+)"'
  long_re='(^|[[:space:]])--([A-Za-z][A-Za-z0-9-]*)($|[[:space:]])'
  legacy_re='(\[|<)[A-Za-z_][A-Za-z0-9_]*\.\.\.(\]|>)'

  while IFS= read -r line; do
    if [[ "$line" =~ $arg_re ]]; then
      name="${BASH_REMATCH[2]}"
      legacy="${BASH_REMATCH[3]}"
      if [[ "$line" == *'var=#true'* || -n "$legacy" ]]; then
        printf 'usage_%s\n' "$name"
      fi
      continue
    fi

    if [[ "$line" =~ $flag_re ]]; then
      spec="${BASH_REMATCH[1]}"
      if [[ "$line" != *'var=#true'* && ! "$spec" =~ $legacy_re ]]; then
        continue
      fi
      if [[ "$spec" =~ $long_re ]]; then
        name="${BASH_REMATCH[2]//-/_}"
        printf 'usage_%s\n' "$name"
      fi
    fi
  done < "$file" | LC_ALL=C sort -u
}

variadic_args_is_declared() {
  local wanted="$1"
  shift
  local declared

  for declared in "$@"; do
    [[ "$wanted" == "$declared" ]] && return 0
  done
  return 1
}

variadic_args_has_reasoned_ignore() {
  local file="$1"
  rg -q 'codebase:ignore[[:space:]]+variadic-args[[:space:]]+--[[:space:]]+[^[:space:]]' "$file"
}

variadic_args_expansion_name() {
  local text="$1"

  text="${text#\$\{}"
  text="${text#\$}"
  text="${text%\}}"
  [[ "$text" =~ ^usage_[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  printf '%s\n' "$text"
}

variadic_args_scan_eval() {
  local file="$1"
  shift
  local ast_output parsed lineno text name

  if ! ast_output=$(ast-grep scan \
    --rule "$_CODEBASE_VARIADIC_RULE_DIR/eval-expansion.yml" \
    --json=stream --stdin < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not inspect eval consumers in %s\n' "$file" >&2
    printf '%s\n' "$ast_output" >&2
    return 1
  fi

  if ! parsed=$(printf '%s\n' "$ast_output" | jq -r '[.range.start.line + 1, .text] | @tsv' 2>&1); then
    printf 'ERROR: could not parse ast-grep eval output for %s\n' "$file" >&2
    printf '%s\n' "$parsed" >&2
    return 1
  fi

  while IFS=$'\t' read -r lineno text; do
    [[ -n "$lineno" ]] || continue
    name=$(variadic_args_expansion_name "$text") || continue
    variadic_args_is_declared "$name" "$@" || continue
    printf '%s\teval\t%s\n' "$lineno" "$name"
  done <<< "$parsed"
}

variadic_args_read_payload() {
  local command="$1"
  local command_json redirect redirect_json payload analyzer_status

  # shellcheck disable=SC2016 # ast-grep metavariable syntax is literal.
  if command_json=$(printf '%s' "$command" |
    ast-grep run --lang bash --pattern 'read $$$ARGS' --json=compact --stdin 2>&1); then
    :
  else
    analyzer_status=$?
    [[ "$analyzer_status" -eq 1 && "$command_json" == '[]' ]] && return 1
    printf '%s\n' 'ERROR: ast-grep could not parse a read command' >&2
    printf '%s\n' "$command_json" >&2
    return 2
  fi

  if ! redirect=$(printf '%s' "$command_json" | jq -jr '
    if length != 1 then empty
    else .[0].metaVariables.multi.ARGS as $args |
      if ($args | length) < 3 then empty
      else ($args[0:-2] | map(.text)) as $options |
        ($args[-2].text) as $array |
        if ($options | length) >= 1 and
           ($options | all(. == "-r" or . == "-a" or . == "-ra" or . == "-ar")) and
           ($options | map(select(contains("a"))) | length) == 1 and
           ($array | test("^[A-Za-z_][A-Za-z0-9_]*$"))
        then $args[-1].text else empty end
      end
    end' 2>&1); then
    printf '%s\n' 'ERROR: could not parse ast-grep read arguments' >&2
    printf '%s\n' "$redirect" >&2
    return 2
  fi
  [[ -n "$redirect" ]] || return 1

  # shellcheck disable=SC2016 # ast-grep metavariable syntax is literal.
  if redirect_json=$(printf '%s' "$redirect" |
    ast-grep run --lang bash --pattern '<<< $PAYLOAD' --json=compact --stdin 2>&1); then
    :
  else
    analyzer_status=$?
    [[ "$analyzer_status" -eq 1 && "$redirect_json" == '[]' ]] && return 1
    printf '%s\n' 'ERROR: ast-grep could not parse a read here-string' >&2
    printf '%s\n' "$redirect_json" >&2
    return 2
  fi
  if ! payload=$(printf '%s' "$redirect_json" |
    jq -jr --arg redirect "$redirect" '
      if length == 1 and .[0].text == $redirect
      then .[0].metaVariables.single.PAYLOAD.text
      else empty end' 2>&1); then
    printf '%s\n' 'ERROR: could not parse ast-grep read here-string output' >&2
    printf '%s\n' "$payload" >&2
    return 2
  fi
  [[ -n "$payload" ]] || return 1

  if [[ "$payload" == '"'*'"' ]]; then
    payload="${payload#\"}"
    payload="${payload%\"}"
  fi
  variadic_args_expansion_name "$payload"
}

variadic_args_scan_read() {
  local file="$1"
  shift
  local ast_output commands command_start command_end name_start lineno count command name payload_status

  if ! ast_output=$(ast-grep scan \
    --rule "$_CODEBASE_VARIADIC_RULE_DIR/read-command.yml" \
    --json=stream --stdin < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not inspect read consumers in %s\n' "$file" >&2
    printf '%s\n' "$ast_output" >&2
    return 1
  fi

  if ! commands=$(printf '%s\n' "$ast_output" | jq -r '
    . as $match |
    (.labels[] | select(.text == "read" and .style == "secondary")) as $name |
    [$match.range.byteOffset.start, $match.range.byteOffset.end,
     $name.range.byteOffset.start, $match.range.start.line + 1] | @tsv' 2>&1); then
    printf 'ERROR: could not parse ast-grep read output for %s\n' "$file" >&2
    printf '%s\n' "$commands" >&2
    return 1
  fi

  while IFS=$'\t' read -r command_start command_end name_start lineno; do
    [[ -n "$command_start" ]] || continue
    count=$((command_end - name_start))
    if ! command=$(dd if="$file" bs=1 skip="$name_start" count="$count" 2>/dev/null); then
      printf 'ERROR: could not materialize read command in %s\n' "$file" >&2
      return 1
    fi
    if name=$(variadic_args_read_payload "$command"); then
      variadic_args_is_declared "$name" "$@" || continue
    else
      payload_status=$?
      [[ "$payload_status" -eq 1 ]] && continue
      printf 'ERROR: could not inspect read consumer in %s\n' "$file" >&2
      return "$payload_status"
    fi
    printf '%s\tread\t%s\n' "$lineno" "$name"
  done <<< "$commands"
}

variadic_args_scan_file() {
  local file="$1"
  local declarations eval_hits read_hits hit
  local -a declared

  variadic_args_has_reasoned_ignore "$file" && return 0

  declarations=$(variadic_args_declarations "$file")
  [[ -n "$declarations" ]] || return 0
  declared=()
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && declared+=("$hit")
  done <<< "$declarations"

  eval_hits=$(variadic_args_scan_eval "$file" "${declared[@]}") || return 1
  read_hits=$(variadic_args_scan_read "$file" "${declared[@]}") || return 1
  printf '%s\n%s\n' "$eval_hits" "$read_hits" | sed '/^$/d'
}

variadic_args_lint() {
  local encoded_targets="$1"
  local target name task_dir discovered file rel scan_output hit lineno line
  local failures=0 hit_count target_output
  local -a targets files

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done < <(variadic_args_parse_targets "$encoded_targets")

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo 'ERROR: at least one target is required' >&2
    return 1
  fi

  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      printf 'ERROR: target does not exist: %s\n' "$target" >&2
      return 1
    fi

    name=$(basename "$target")
    task_dir="$target/.mise/tasks"
    if [[ ! -d "$task_dir" ]]; then
      printf 'OK    %s (no .mise/tasks directory)\n' "$name"
      continue
    fi

    if ! discovered=$(discover_shell_files "$task_dir"); then
      printf 'ERROR: could not discover Bash tasks in %s\n' "$target" >&2
      return 1
    fi
    files=()
    while IFS= read -r file; do
      [[ -n "$file" && -x "$file" ]] || continue
      head -1 "$file" | rg -q '^#!.*\bbash\b' || continue
      files+=("$file")
    done <<< "$discovered"

    hit_count=0
    target_output=""
    for file in ${files[@]+"${files[@]}"}; do
      rel="${file#"$target"/}"
      scan_output=$(variadic_args_scan_file "$file") || return 1
      while IFS=$'\t' read -r lineno _; do
        [[ -n "$lineno" ]] || continue
        line=$(sed -n "${lineno}p" "$file")
        target_output+="  $rel:$lineno: ${line#"${line%%[![:space:]]*}"}"$'\n'
        hit_count=$((hit_count + 1))
      done <<< "$scan_output"
    done

    if [[ "$hit_count" -gt 0 ]]; then
      printf 'FAIL  %s: %s known unsafe variadic Usage consumer(s)\n' "$name" "$hit_count"
      printf '%s' "$target_output"
      printf '%s\n' '  hint: parse single-line values with xargs printf, or use a language-native parser; this lint intentionally recognizes only known bad source idioms.'
      failures=$((failures + 1))
    else
      printf 'OK    %s (%s executable Bash task(s) clean)\n' "$name" "${#files[@]}"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
