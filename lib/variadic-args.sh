#!/usr/bin/env bash
# Scanner for unsafe Bash consumption of variadic Mise Usage values.

_CODEBASE_VARIADIC_ARGS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_VARIADIC_ARGS_RULE="$_CODEBASE_VARIADIC_ARGS_LIB_DIR/../rules/variadic-args/consumer.yml"
_CODEBASE_VARIADIC_ARGS_EXPANSION_RULE="$_CODEBASE_VARIADIC_ARGS_LIB_DIR/../rules/variadic-args/expansion.yml"
_CODEBASE_VARIADIC_ARGS_INPUT_RULE="$_CODEBASE_VARIADIC_ARGS_LIB_DIR/../rules/variadic-args/input.yml"
_CODEBASE_VARIADIC_ARGS_REDIRECT_RULE="$_CODEBASE_VARIADIC_ARGS_LIB_DIR/../rules/variadic-args/redirect.yml"
_CODEBASE_VARIADIC_ARGS_STDIN_RULE="$_CODEBASE_VARIADIC_ARGS_LIB_DIR/../rules/variadic-args/stdin.yml"
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

variadic_args_expansion_owned_by_nested() {
  local consumer_ranges="$1"
  local command_start="$2"
  local range_start="$3"
  local range_end="$4"
  local expansion_start="$5"
  local nested_command_start nested_range_start nested_end

  while IFS='|' read -r nested_command_start nested_range_start nested_end; do
    [[ -n "$nested_command_start" && -n "$nested_range_start" && -n "$nested_end" ]] || continue
    if [[ "$nested_command_start" -ne "$command_start" &&
          "$nested_range_start" -ge "$range_start" &&
          "$nested_end" -le "$range_end" &&
          "$expansion_start" -ge "$nested_range_start" &&
          "$expansion_start" -lt "$nested_end" ]]; then
      return 0
    fi
  done <<< "$consumer_ranges"

  return 1
}

variadic_args_effective_input_range() {
  local input_ranges="$1"
  local stdin_ranges="$2"
  local consumer_ranges="$3"
  local command_start="$4"
  local range_start="$5"
  local range_end="$6"
  local stdin_start stdin_end input_order input_start input_end
  local nested_command_start nested_range_start nested_end
  local effective_order="" nested

  while IFS='|' read -r stdin_start stdin_end; do
    [[ -n "$stdin_start" && -n "$stdin_end" ]] || continue
    [[ "$stdin_start" -ge "$range_start" && "$stdin_end" -le "$range_end" ]] || continue

    nested=false
    while IFS='|' read -r nested_command_start nested_range_start nested_end; do
      [[ -n "$nested_command_start" && -n "$nested_range_start" && -n "$nested_end" ]] || continue
      if [[ "$nested_command_start" -ne "$command_start" &&
            "$nested_range_start" -ge "$range_start" &&
            "$nested_end" -le "$range_end" &&
            "$stdin_start" -ge "$nested_range_start" &&
            "$stdin_end" -le "$nested_end" ]]; then
        nested=true
        break
      fi
    done <<< "$consumer_ranges"
    $nested && continue

    if [[ -z "$effective_order" || "$stdin_start" -gt "$effective_order" ]]; then
      effective_order="$stdin_start"
    fi
  done <<< "$stdin_ranges"

  [[ -n "$effective_order" ]] || return 1
  while IFS='|' read -r input_order input_start input_end; do
    [[ "$input_order" == "$effective_order" && -n "$input_start" && -n "$input_end" ]] || continue
    printf '%s|%s\n' "$input_start" "$input_end"
    return 0
  done <<< "$input_ranges"

  return 1
}

variadic_args_read_input_expands_var() {
  local expansions="$1"
  local consumer_ranges="$2"
  local input_ranges="$3"
  local stdin_ranges="$4"
  local redirect_ranges="$5"
  local command_start="$6"
  local range_start="$7"
  local range_end="$8"
  local var="$9"
  local effective input_start input_end expansion_start expansion_var
  local redirect_start redirect_end redirected

  effective=$(variadic_args_effective_input_range \
    "$input_ranges" "$stdin_ranges" "$consumer_ranges" \
    "$command_start" "$range_start" "$range_end") || return 1
  input_start="${effective%%|*}"
  input_end="${effective#*|}"

  while IFS='|' read -r expansion_start expansion_var; do
    [[ -n "$expansion_start" && -n "$expansion_var" ]] || continue
    [[ "$expansion_start" -ge "$input_start" &&
       "$expansion_start" -lt "$input_end" &&
       "$expansion_var" == "$var" ]] || continue
    variadic_args_expansion_owned_by_nested \
      "$consumer_ranges" "$command_start" "$range_start" "$range_end" "$expansion_start" && continue

    redirected=false
    while IFS='|' read -r redirect_start redirect_end; do
      [[ -n "$redirect_start" && -n "$redirect_end" ]] || continue
      if [[ "$redirect_start" -ge "$input_start" &&
            "$redirect_end" -le "$input_end" &&
            ( "$redirect_start" -gt "$input_start" || "$redirect_end" -lt "$input_end" ) &&
            "$expansion_start" -ge "$redirect_start" &&
            "$expansion_start" -lt "$redirect_end" ]]; then
        redirected=true
        break
      fi
    done <<< "$redirect_ranges"
    $redirected || return 0
  done <<< "$expansions"

  return 1
}

variadic_args_eval_uses_var() {
  local command="$1"
  local consumer_ranges="$2"
  local redirect_ranges="$3"
  local command_start="$4"
  local range_end="$5"
  local var="$6"
  local blank_start blank_end relative_start relative_end length padding
  local nested_command_start nested_range_start nested_end

  # eval reparses quoted and escaped text, so raw command text is intentional.
  # Blank input redirects and nested consumers without changing byte offsets.
  while IFS='|' read -r blank_start blank_end; do
    [[ -n "$blank_start" && -n "$blank_end" ]] || continue
    [[ "$blank_start" -ge "$command_start" && "$blank_end" -le "$range_end" ]] || continue
    relative_start=$((blank_start - command_start))
    relative_end=$((blank_end - command_start))
    length=$((relative_end - relative_start))
    printf -v padding '%*s' "$length" ''
    command="${command:0:$relative_start}$padding${command:$relative_end}"
  done <<< "$redirect_ranges"

  while IFS='|' read -r nested_command_start nested_range_start nested_end; do
    [[ -n "$nested_command_start" && -n "$nested_range_start" && -n "$nested_end" ]] || continue
    [[ "$nested_command_start" -ne "$command_start" &&
       "$nested_range_start" -ge "$command_start" &&
       "$nested_end" -le "$range_end" ]] || continue
    relative_start=$((nested_range_start - command_start))
    relative_end=$((nested_end - command_start))
    length=$((relative_end - relative_start))
    printf -v padding '%*s' "$length" ''
    command="${command:0:$relative_start}$padding${command:$relative_end}"
  done <<< "$consumer_ranges"

  variadic_args_command_uses_var "$command" "$var"
}

variadic_args_range_is_maximal() {
  local consumer_ranges="$1"
  local command_start="$2"
  local range_start="$3"
  local range_end="$4"
  local other_command_start other_range_start other_end

  while IFS='|' read -r other_command_start other_range_start other_end; do
    [[ -n "$other_command_start" && -n "$other_range_start" && -n "$other_end" ]] || continue
    if [[ "$other_command_start" -eq "$command_start" &&
          "$other_range_start" -le "$range_start" &&
          "$other_end" -ge "$range_end" &&
          ( "$other_range_start" -lt "$range_start" || "$other_end" -gt "$range_end" ) ]]; then
      return 1
    fi
  done <<< "$consumer_ranges"

  return 0
}

variadic_args_command_words() {
  local command="$1"
  local transformed="" char pair raw decoded ansi_control
  local index=0 length

  length="${#command}"

  # xargs handles ordinary shell quotes but not Bash's $'...' form. Decode
  # ANSI-C fragments only in unquoted shell context, retaining concatenation
  # with adjacent text. Poison fragments containing non-option characters so
  # erasing them cannot turn an invalid word into an option.
  while [[ "$index" -lt "$length" ]]; do
    char="${command:$index:1}"
    pair="${command:$index:2}"
    if [[ "$pair" == "\$'" ]]; then
      raw=""
      ansi_control=false
      index=$((index + 2))
      while [[ "$index" -lt "$length" ]]; do
        char="${command:$index:1}"
        if [[ "$char" == "\\" ]]; then
          [[ "${command:$((index + 1)):1}" == c ]] && ansi_control=true
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
      if $ansi_control || ! printf -v decoded '%b' "$raw" 2>/dev/null; then
        decoded="."
      fi
      if [[ "$decoded" =~ ^[A-Za-z0-9_-]*$ ]]; then
        transformed+="$decoded"
      else
        transformed+="."
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
          if [[ "$char" == '$' ]]; then
            transformed+="."
          else
            transformed+="$char"
          fi
          index=$((index + 1))
        fi
      done
    elif [[ "$char" == '"' ]]; then
      transformed+='"'
      index=$((index + 1))
      while [[ "$index" -lt "$length" ]]; do
        char="${command:$index:1}"
        pair="${command:$index:2}"
        if [[ "$char" == '"' ]]; then
          transformed+='"'
          index=$((index + 1))
          break
        elif [[ "$pair" == $'\\\n' ]]; then
          index=$((index + 2))
        elif [[ "$char" == "\\" ]]; then
          if [[ "${command:$((index + 1)):1}" == '$' ]]; then
            transformed+="."
          else
            transformed+="${command:$index:2}"
          fi
          index=$((index + 2))
        else
          transformed+="$char"
          index=$((index + 1))
        fi
      done
    elif [[ "$pair" == $'\\\n' ]]; then
      index=$((index + 2))
    elif [[ "$char" == "\\" ]]; then
      if [[ "${command:$((index + 1)):1}" == '$' ]]; then
        transformed+="."
      else
        transformed+="${command:$index:2}"
      fi
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
  local token options option array_name
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
        a)
          array_name="${options:$((option_index + 1))}"
          if [[ -z "$array_name" ]]; then
            index=$((index + 1))
            array_name="${words[$index]:-}"
          fi
          if [[ "$array_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ || "$array_name" == *'$'* ]]; then
            return 0
          fi
          return 1
          ;;
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
  local ast_output expansion_output input_output redirect_output stdin_output
  local expansions="" consumer_ranges="" input_ranges="" redirect_ranges="" stdin_ranges="" record
  local range_start end input_order prefix command_start zero_based lineno source_line command kind var
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
  if ! expansion_output=$(ast-grep scan --stdin --rule "$_CODEBASE_VARIADIC_ARGS_EXPANSION_RULE" --json=stream < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not scan expansions in %s\n' "$file" >&2
    printf '%s\n' "$expansion_output" >&2
    return 2
  fi
  if ! input_output=$(ast-grep scan --stdin --rule "$_CODEBASE_VARIADIC_ARGS_INPUT_RULE" --json=stream < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not scan redirected inputs in %s\n' "$file" >&2
    printf '%s\n' "$input_output" >&2
    return 2
  fi
  if ! redirect_output=$(ast-grep scan --stdin --rule "$_CODEBASE_VARIADIC_ARGS_REDIRECT_RULE" --json=stream < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not scan redirects in %s\n' "$file" >&2
    printf '%s\n' "$redirect_output" >&2
    return 2
  fi
  if ! stdin_output=$(ast-grep scan --stdin --rule "$_CODEBASE_VARIADIC_ARGS_STDIN_RULE" --json=stream < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not scan standard-input redirects in %s\n' "$file" >&2
    printf '%s\n' "$stdin_output" >&2
    return 2
  fi
  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    range_start="${record#*\"byteOffset\":{\"start\":}"
    range_start="${range_start%%,*}"
    end="${record#*\"byteOffset\":{\"start\":"$range_start",\"end\":}"
    end="${end%%\}*}"
    input_order=$(printf '%s\n' "$record" | sed -nE 's/.*"secondary":\[\{"text":.*"range":\{"byteOffset":\{"start":([0-9]+),.*/\1/p')
    [[ -n "$input_order" ]] || input_order="$range_start"
    [[ "$input_order" =~ ^[0-9]+$ && "$range_start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || {
      printf 'ERROR: could not parse ast-grep redirected input match for %s\n' "$file" >&2
      return 2
    }
    input_ranges+="$input_order|$range_start|$end"$'\n'
  done <<< "$input_output"

  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    range_start="${record#*\"byteOffset\":{\"start\":}"
    range_start="${range_start%%,*}"
    end="${record#*\"byteOffset\":{\"start\":"$range_start",\"end\":}"
    end="${end%%\}*}"
    [[ "$range_start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || {
      printf 'ERROR: could not parse ast-grep redirect match for %s\n' "$file" >&2
      return 2
    }
    redirect_ranges+="$range_start|$end"$'\n'
  done <<< "$redirect_output"

  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    range_start="${record#*\"byteOffset\":{\"start\":}"
    range_start="${range_start%%,*}"
    end="${record#*\"byteOffset\":{\"start\":"$range_start",\"end\":}"
    end="${end%%\}*}"
    [[ "$range_start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || {
      printf 'ERROR: could not parse ast-grep standard-input match for %s\n' "$file" >&2
      return 2
    }
    stdin_ranges+="$range_start|$end"$'\n'
    if [[ "$range_start" -ge 2 ]]; then
      prefix=$(dd if="$file" bs=1 skip="$((range_start - 2))" count=2 2>/dev/null)
      if [[ "$prefix" == "<<" ]]; then
        input_ranges+="$range_start|$range_start|$end"$'\n'
      fi
    fi
  done <<< "$stdin_output"

  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    record=$(printf '%s\n' "$record" | sed -nE 's/^\{"text":"([A-Za-z_][A-Za-z0-9_]*)","range":\{"byteOffset":\{"start":([0-9]+),.*/\2|\1/p')
    [[ -n "$record" ]] || {
      printf 'ERROR: could not parse ast-grep expansion match for %s\n' "$file" >&2
      return 2
    }
    expansions+="$record"$'\n'
  done <<< "$expansion_output"

  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    range_start="${record#*\"byteOffset\":{\"start\":}"
    range_start="${range_start%%,*}"
    end=$(printf '%s\n' "$record" | sed -nE 's/.*"range":\{"byteOffset":\{"start":[0-9]+,"end":([0-9]+)\}.*\},"file":.*/\1/p')
    command_start=$(printf '%s\n' "$record" | sed -nE 's/.*"secondary":\[\{"text":"(eval|read)","range":\{"byteOffset":\{"start":([0-9]+),.*/\2/p')
    [[ "$range_start" =~ ^[0-9]+$ && -n "$end" && -n "$command_start" ]] || {
      printf 'ERROR: could not parse ast-grep match for %s\n' "$file" >&2
      return 2
    }
    consumer_ranges+="$command_start|$range_start|$end"$'\n'
  done <<< "$ast_output"

  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    range_start="${record#*\"byteOffset\":{\"start\":}"
    range_start="${range_start%%,*}"
    end=$(printf '%s\n' "$record" | sed -nE 's/.*"range":\{"byteOffset":\{"start":[0-9]+,"end":([0-9]+)\}.*\},"file":.*/\1/p')
    # Classify from ast-grep's secondary command-name range so assignment
    # values and leading redirects do not need to be reparsed as shell words.
    command_start=$(printf '%s\n' "$record" | sed -nE 's/.*"secondary":\[\{"text":"(eval|read)","range":\{"byteOffset":\{"start":([0-9]+),.*/\2/p')
    zero_based=$(printf '%s\n' "$record" | sed -nE 's/.*"range":\{.*"start":\{"line":([0-9]+),"column":[0-9]+\}.*\},"file":.*/\1/p')
    [[ "$range_start" =~ ^[0-9]+$ && -n "$end" && -n "$command_start" && -n "$zero_based" ]] || {
      printf 'ERROR: could not parse ast-grep match for %s\n' "$file" >&2
      return 2
    }
    variadic_args_range_is_maximal "$consumer_ranges" "$command_start" "$range_start" "$end" || continue
    lineno=$((zero_based + 1))
    command=$(dd if="$file" bs=1 skip="$command_start" count="$((end - command_start))" 2>/dev/null)

    if ! kind=$(variadic_args_command_kind "$command"); then
      continue
    fi

    source_line=$(sed -n "${lineno}p" "$file")
    variadic_args_has_reasoned_ignore "$source_line" && continue

    for var in ${declared[@]+"${declared[@]}"}; do
      if [[ "$kind" == eval ]] && variadic_args_eval_uses_var \
        "$command" "$consumer_ranges" "$redirect_ranges" \
        "$command_start" "$end" "$var"; then
        printf '%s|%s|%s|%s\n' "$lineno" "$kind" "$var" "${source_line#"${source_line%%[![:space:]]*}"}"
      elif [[ "$kind" == read-array ]] && variadic_args_read_input_expands_var \
        "$expansions" "$consumer_ranges" "$input_ranges" "$stdin_ranges" "$redirect_ranges" \
        "$command_start" "$range_start" "$end" "$var"; then
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
