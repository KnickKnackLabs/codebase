#!/usr/bin/env bash
# Scanner for unsafe Bash consumption of variadic Mise Usage values.

_CODEBASE_VARIADIC_ARGS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_VARIADIC_ARGS_RULE="$_CODEBASE_VARIADIC_ARGS_LIB_DIR/../rules/variadic-args/consumer.yml"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_VARIADIC_ARGS_LIB_DIR/shell-files.sh"

variadic_args_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0

  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

variadic_args_name() {
  local name="$1"

  name="${name#[}"
  name="${name#<}"
  name="${name%%]*}"
  name="${name%%>*}"
  name="${name%...}"
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || return 1
  printf 'usage_%s\n' "$(printf '%s' "$name" | tr '-' '_')"
}

variadic_args_declared_vars() {
  local file="$1"
  local line spec flag

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ [[:space:]]var=#true([[:space:]]|$) ]] || continue

    if [[ "$line" =~ ^[[:space:]]*#USAGE[[:space:]]+arg[[:space:]] ]]; then
      spec=$(printf '%s\n' "$line" | sed -nE 's/^[[:space:]]*#USAGE[[:space:]]+arg[[:space:]]+"([^"]+)".*/\1/p')
      [[ -n "$spec" ]] || continue
      variadic_args_name "$spec" || true
    elif [[ "$line" =~ ^[[:space:]]*#USAGE[[:space:]]+flag[[:space:]] ]]; then
      spec=$(printf '%s\n' "$line" | sed -nE 's/^[[:space:]]*#USAGE[[:space:]]+flag[[:space:]]+"([^"]+)".*/\1/p')
      [[ -n "$spec" ]] || continue
      if ! flag=$(printf '%s\n' "$spec" | grep -oE -- '--[A-Za-z0-9_-]+' | tail -1); then
        continue
      fi
      variadic_args_name "${flag#--}" || true
    fi
  done < "$file"
}

variadic_args_has_reasoned_ignore() {
  local line="$1"
  [[ "$line" =~ codebase:ignore[[:space:]]+variadic-args[[:space:]]+.+ ]]
}

variadic_args_command_uses_var() {
  local command="$1"
  local var="$2"
  local bare_re brace_re

  bare_re='[$]'"$var"'([^A-Za-z0-9_]|$)'
  brace_re='[$][{]'"$var"'([^A-Za-z0-9_]|$)'
  [[ "$command" =~ $bare_re ]] || [[ "$command" =~ $brace_re ]]
}

variadic_args_command_words() {
  local command="$1"
  local transformed="" char pair raw decoded
  local index=0 length

  length="${#command}"

  # xargs handles ordinary shell quotes but not Bash's $'...' form. Decode an
  # ANSI-C quote only when it spells a possible option; otherwise retain just
  # its word boundary.
  while [[ "$index" -lt "$length" ]]; do
    char="${command:$index:1}"
    pair="${command:$index:2}"
    if [[ "$pair" == "\$'" ]]; then
      raw=""
      index=$((index + 2))
      while [[ "$index" -lt "$length" ]]; do
        char="${command:$index:1}"
        if [[ "$char" == "\\" ]]; then
          raw+="${command:$index:2}"
          index=$((index + 2))
        elif [[ "$char" == "'" ]]; then
          index=$((index + 1))
          break
        else
          raw+="$char"
          index=$((index + 1))
        fi
      done
      decoded=$(printf '%b' "$raw")
      if [[ "$decoded" =~ ^-[A-Za-z0-9_-]+$ ]]; then
        transformed+="$decoded"
      else
        transformed+="''"
      fi
    elif [[ "$char" == "'" ]]; then
      transformed+="'"
      index=$((index + 1))
      while [[ "$index" -lt "$length" ]]; do
        char="${command:$index:1}"
        pair="${command:$index:2}"
        if [[ "$char" == "'" ]]; then
          transformed+="'"
          index=$((index + 1))
          break
        elif [[ "$pair" == $'\\\n' ]]; then
          transformed+="__"
          index=$((index + 2))
        elif [[ "$char" == $'\n' ]]; then
          transformed+="__"
          index=$((index + 1))
        else
          transformed+="$char"
          index=$((index + 1))
        fi
      done
    elif [[ "$pair" == $'\\\n' ]]; then
      index=$((index + 2))
    else
      transformed+="$char"
      index=$((index + 1))
    fi
  done

  printf '%s' "$transformed" | xargs printf '%s\n'
}

variadic_args_read_uses_array() {
  local command="$1"
  local token options option
  local index option_index
  local -a words

  words=()
  while IFS= read -r token; do
    words+=("$token")
  done < <(variadic_args_command_words "$command")

  [[ "${words[0]:-}" == read ]] || return 1
  index=1
  while [[ "$index" -lt "${#words[@]}" ]]; do
    token="${words[$index]}"
    [[ "$token" == "--" ]] && return 1
    [[ "$token" == -* && "$token" != "-" ]] || return 1

    options="${token#-}"
    option_index=0
    while [[ "$option_index" -lt "${#options}" ]]; do
      option="${options:$option_index:1}"
      case "$option" in
        a) return 0 ;;
        E|e|r|s) option_index=$((option_index + 1)) ;;
        d|i|n|N|p|t|u)
          if [[ "$option_index" -eq $((${#options} - 1)) ]]; then
            index=$((index + 1))
          fi
          break
          ;;
        *) return 1 ;;
      esac
    done

    index=$((index + 1))
  done

  return 1
}

variadic_args_command_kind() {
  local command="$1"

  if [[ "$command" =~ ^eval([[:space:]]|$) ]]; then
    printf '%s\n' eval
  elif variadic_args_read_uses_array "$command"; then
    printf '%s\n' read-array
  else
    return 1
  fi
}

variadic_args_scan_file() {
  local file="$1"
  local ast_output record end command_start zero_based lineno source_line command kind var
  local -a declared

  declared=()
  while IFS= read -r var; do
    [[ -n "$var" ]] && declared+=("$var")
  done < <(variadic_args_declared_vars "$file")
  [[ ${#declared[@]} -gt 0 ]] || return 0

  if ! ast_output=$(ast-grep scan --stdin --rule "$_CODEBASE_VARIADIC_ARGS_RULE" --json=stream < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not scan %s\n' "$file" >&2
    printf '%s\n' "$ast_output" >&2
    return 2
  fi

  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    end=$(printf '%s\n' "$record" | sed -nE 's/.*"range":\{"byteOffset":\{"start":[0-9]+,"end":([0-9]+)\}.*\},"file":.*/\1/p')
    # Start at ast-grep's secondary command-name range so assignment values do
    # not need to be reparsed as shell words.
    command_start=$(printf '%s\n' "$record" | sed -nE 's/.*"secondary":\[\{"text":"(eval|read)","range":\{"byteOffset":\{"start":([0-9]+),.*/\2/p')
    zero_based=$(printf '%s\n' "$record" | sed -nE 's/.*"range":\{.*"start":\{"line":([0-9]+),"column":[0-9]+\}.*\},"file":.*/\1/p')
    [[ -n "$end" && -n "$command_start" && -n "$zero_based" ]] || {
      printf 'ERROR: could not parse ast-grep match for %s\n' "$file" >&2
      return 2
    }
    lineno=$((zero_based + 1))
    command=$(dd if="$file" bs=1 skip="$command_start" count="$((end - command_start))" 2>/dev/null)

    if ! kind=$(variadic_args_command_kind "$command"); then
      continue
    fi

    source_line=$(sed -n "${lineno}p" "$file")
    variadic_args_has_reasoned_ignore "$source_line" && continue

    for var in ${declared[@]+"${declared[@]}"}; do
      if variadic_args_command_uses_var "$command" "$var"; then
        printf '%s|%s|%s|%s\n' "$lineno" "$kind" "$var" "${source_line#"${source_line%%[![:space:]]*}"}"
      fi
    done
  done <<< "$ast_output"
}

variadic_args_discover_tasks() {
  local target="$1"
  [[ -d "$target/.mise/tasks" ]] || return 0
  fd -t f --exclude fixtures . "$target/.mise/tasks"
}

variadic_args_lint() {
  local encoded_targets="$1"
  local target name toml task_files task_file rel findings finding lineno rest kind var line
  local failures=0 hit_count target_output
  local -a targets files

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done < <(variadic_args_parse_targets "$encoded_targets")

  if [[ ${#targets[@]} -eq 0 ]]; then
    printf 'ERROR: at least one target is required\n' >&2
    return 1
  fi

  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      printf 'ERROR: target does not exist: %s\n' "$target" >&2
      return 1
    fi

    name=$(basename "$target")
    toml="$target/mise.toml"
    if [[ -f "$toml" ]] && rg -q 'codebase:ignore[[:space:]]+variadic-args([[:space:]]|$)' "$toml"; then
      printf 'SKIP  %s (codebase:ignore)\n' "$name"
      continue
    fi

    if ! task_files=$(variadic_args_discover_tasks "$target"); then
      printf 'ERROR: could not discover Mise tasks in %s\n' "$target" >&2
      return 1
    fi
    files=()
    while IFS= read -r task_file; do
      [[ -n "$task_file" ]] && files+=("$task_file")
    done <<< "$task_files"

    if [[ ${#files[@]} -eq 0 ]]; then
      printf 'OK    %s (no Mise tasks found)\n' "$name"
      continue
    fi

    hit_count=0
    target_output=""
    for task_file in "${files[@]}"; do
      rel="${task_file#"$target"/}"
      if ! findings=$(variadic_args_scan_file "$task_file"); then
        return 1
      fi
      while IFS= read -r finding; do
        [[ -n "$finding" ]] || continue
        lineno="${finding%%|*}"
        rest="${finding#*|}"
        kind="${rest%%|*}"
        rest="${rest#*|}"
        var="${rest%%|*}"
        line="${rest#*|}"
        target_output+="  $rel:$lineno: $line"$'\n'
        case "$kind" in
          eval) target_output+="    ERROR: eval of $var can execute caller-controlled shell syntax"$'\n' ;;
          read-array) target_output+="    WARN: read -a loses Mise's quoting for multi-word $var values"$'\n' ;;
        esac
        hit_count=$((hit_count + 1))
      done <<< "$findings"
    done

    if [[ "$hit_count" -gt 0 ]]; then
      printf 'FAIL  %s: %s unsafe variadic Usage consumer(s)\n' "$name" "$hit_count"
      printf '%s' "$target_output"
      printf '%s\n' "  hint: parse single-line values with xargs, or use a dedicated parser when embedded newlines matter"
      printf '%s\n' "        annotate an intentional exception with '# codebase:ignore variadic-args — <reason>'"
      failures=$((failures + 1))
    else
      printf 'OK    %s (%s task file(s) clean)\n' "$name" "${#files[@]}"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
