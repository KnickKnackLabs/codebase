#!/usr/bin/env bash
# Shared scanner for Bash 3.2 nounset expansion hazards.
#
# This is a library, not a mise task. It is sourced by the two public lint
# rules that distinguish positional argv from named arrays while sharing file
# discovery, nounset detection, ignore handling, diagnostics, and target
# orchestration.

_CODEBASE_BASH_NOUNSET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_BASH_NOUNSET_RULE_DIR="$_CODEBASE_BASH_NOUNSET_LIB_DIR/../rules/bash-nounset"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_BASH_NOUNSET_LIB_DIR/shell-files.sh"

bash_nounset_enabled() {
  local file="$1"
  local rule_file="$_CODEBASE_BASH_NOUNSET_RULE_DIR/nounset-enabled.yml"
  local ast_output

  if ! ast_output=$(ast-grep scan --stdin --rule "$rule_file" --json=stream < "$file" 2>&1); then
    echo "ERROR: ast-grep could not inspect nounset commands in $file" >&2
    printf '%s\n' "$ast_output" >&2
    return 2
  fi

  [[ -n "$ast_output" ]]
}

bash_nounset_ignore_has_reason() {
  local rule="$1"
  local line="$2"

  [[ "$line" =~ codebase:ignore[[:space:]]+${rule}[[:space:]]+.+ ]]
}

bash_nounset_safe_alternate_value() {
  local rule="$1"
  local match="$2"
  local prefix="$3"
  local suffix="$4"
  local parameter safe_prefix safe_colon_prefix

  case "$rule" in
    bash-empty-argv-forwarding)
      # shellcheck disable=SC2016 # Match a literal parameter expansion.
      safe_prefix='${@+"'
      # shellcheck disable=SC2016 # Match a literal parameter expansion.
      safe_colon_prefix='${@:+"'
      ;;
    bash-empty-array-expansions)
      parameter="${match#\$\{}"
      parameter="${parameter%\}}"
      safe_prefix="\${${parameter}+\""
      safe_colon_prefix="\${${parameter}:+\""
      ;;
    *)
      return 1
      ;;
  esac

  [[ ( "$prefix" == *"$safe_prefix" || "$prefix" == *"$safe_colon_prefix" ) && "$suffix" == '"}'* ]]
}

bash_nounset_scan_line() {
  local rule="$1"
  local line="$2"
  local candidate_limit="${3:-0}"
  local candidate_count=0
  local pattern remaining match prefix suffix

  # AST matching chooses executable candidate lines. Remove co-located simple
  # single-quoted examples before counting real expansions on the same line.
  remaining=$(printf '%s\n' "$line" | sed -E "s/'[^']*'//g")

  case "$rule" in
    bash-empty-argv-forwarding)
      # macOS Bash 3.2 accepts $@ and "$@" under nounset. Bracing the special
      # parameter as ${@} fails whether quoted or unquoted.
      pattern='\$\{@\}'
      ;;
    bash-empty-array-expansions)
      # Empty named arrays fail under Bash 3.2 in every expansion context,
      # including command arguments, loops, and array assignments.
      pattern='\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}'
      ;;
    *)
      printf 'ERROR: unknown nounset lint rule: %s\n' "$rule" >&2
      return 2
      ;;
  esac

  while [[ "$remaining" =~ $pattern ]]; do
    match="${BASH_REMATCH[0]}"
    prefix="${remaining%%"$match"*}"
    suffix="${remaining#*"$match"}"
    candidate_count=$((candidate_count + 1))

    if [[ "$candidate_limit" -gt 0 && "$candidate_count" -gt "$candidate_limit" ]]; then
      break
    fi

    if ! bash_nounset_safe_alternate_value "$rule" "$match" "$prefix" "$suffix"; then
      printf '%s\n' "$match"
    fi

    remaining="$suffix"
  done
}

bash_nounset_scan_file() {
  local rule="$1"
  local file="$2"
  local rule_file="$_CODEBASE_BASH_NOUNSET_RULE_DIR/$rule.yml"
  local ast_output zero_based candidate_count lineno line trimmed match

  if [[ ! -f "$rule_file" ]]; then
    echo "ERROR: missing ast-grep rule: $rule_file" >&2
    return 1
  fi

  # Let tree-sitter identify real shell expansions first. This avoids treating
  # quoted heredocs, comments, and documentation strings as executable Bash.
  # The line scanner below then distinguishes guarded alternate-value forms
  # and preserves Codebase's rule-specific ignore convention.
  if ! ast_output=$(ast-grep scan --stdin --rule "$rule_file" --json=stream < "$file" 2>&1); then
    echo "ERROR: ast-grep could not scan $file" >&2
    printf '%s\n' "$ast_output" >&2
    return 1
  fi

  while read -r zero_based candidate_count; do
    [[ -n "$zero_based" ]] || continue
    lineno=$((zero_based + 1))
    line=$(sed -n "${lineno}p" "$file")

    bash_nounset_ignore_has_reason "$rule" "$line" && continue

    trimmed="${line#"${line%%[![:space:]]*}"}"
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      printf '%s: %s\n' "$lineno" "$trimmed"
    done < <(bash_nounset_scan_line "$rule" "$line" "$candidate_count")
  done < <(
    printf '%s\n' "$ast_output" |
      sed -nE 's/.*"start":\{"line":([0-9]+),.*/\1/p' |
      awk '
        !seen[$0]++ { order[++lines] = $0 }
        { count[$0]++ }
        END { for (i = 1; i <= lines; i++) print order[i], count[order[i]] }
      '
  )
}

bash_nounset_rule_subject() {
  case "$1" in
    bash-empty-argv-forwarding) printf '%s\n' 'braced empty-argv expansion(s) under nounset' ;;
    bash-empty-array-expansions) printf '%s\n' 'empty-array expansion(s) under nounset' ;;
    *) return 1 ;;
  esac
}

bash_nounset_rule_hint() {
  case "$1" in
    bash-empty-argv-forwarding)
      # shellcheck disable=SC2016 # User guidance intentionally shows literals.
      printf '%s\n' 'Use "$@" instead of "${@}"; the unbraced form safely preserves an empty argv on Bash 3.2.'
      ;;
    bash-empty-array-expansions)
      # shellcheck disable=SC2016 # User guidance intentionally shows literals.
      printf '%s\n' 'Use ${args[@]+"${args[@]}"} so an empty array expands safely on Bash 3.2.'
      ;;
    *)
      return 1
      ;;
  esac
}

bash_nounset_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0

  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

bash_nounset_lint() {
  local rule="$1"
  local encoded_targets="$2"
  local failures=0 status target name toml file rel hit hit_count target_output scan_output discovered_files
  local subject hint
  local -a targets files

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done < <(bash_nounset_parse_targets "$encoded_targets")

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo 'ERROR: at least one target is required' >&2
    return 1
  fi

  subject=$(bash_nounset_rule_subject "$rule")
  hint=$(bash_nounset_rule_hint "$rule")

  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      echo "ERROR: target does not exist: $target" >&2
      return 1
    fi

    name=$(basename "$target")
    toml="$target/mise.toml"
    if [[ -f "$toml" ]] && rg -q "codebase:ignore[[:space:]]+$rule([[:space:]]|$)" "$toml"; then
      echo "SKIP  $name (codebase:ignore)"
      continue
    fi

    if ! discovered_files=$(discover_shell_files "$target"); then
      echo "ERROR: could not discover shell files in $target" >&2
      return 1
    fi

    files=()
    while IFS= read -r file; do
      [[ -n "$file" ]] && files+=("$file")
    done <<< "$discovered_files"

    if [[ ${#files[@]} -eq 0 ]]; then
      echo "OK    $name (no shell files found)"
      continue
    fi

    hit_count=0
    target_output=""
    for file in "${files[@]}"; do
      if bash_nounset_enabled "$file"; then
        :
      else
        status=$?
        [[ "$status" -eq 1 ]] && continue
        return "$status"
      fi
      rel="${file#"$target"/}"

      if ! scan_output=$(bash_nounset_scan_file "$rule" "$file"); then
        return 1
      fi

      while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        target_output+="  $rel:$hit"$'\n'
        hit_count=$((hit_count + 1))
      done <<< "$scan_output"
    done

    if [[ "$hit_count" -gt 0 ]]; then
      echo "FAIL  $name: $hit_count $subject"
      printf '%s' "$target_output"
      echo "  hint: $hint"
      failures=$((failures + 1))
    else
      echo "OK    $name (${#files[@]} file(s) clean)"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
