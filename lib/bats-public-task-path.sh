#!/usr/bin/env bash
# Detect BATS tests that reconstruct this repository's Mise task dispatch path
# instead of calling the exported test wrapper.

_CODEBASE_BATS_PATH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_BATS_PATH_RULE_DIR="$_CODEBASE_BATS_PATH_LIB_DIR/../rules/bats-public-task-path"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_BATS_PATH_LIB_DIR/shell-files.sh"

bats_public_task_path_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0
  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

bats_public_task_path_normalize() {
  local source="$1"
  local line test_count=0
  local test_pattern='^[[:blank:]]*@test[[:blank:]]+(.*[^[:blank:]])[[:blank:]]+\{(.*)$'
  local comment_pattern='^[[:blank:]]*(function[[:blank:]]+)?[^[:blank:]()]+[[:blank:]]*\(?\)?[[:blank:]]+\{[[:blank:]]+#[[:blank:]]*@test[[:blank:]]*$'

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $test_pattern ]]; then
      test_count=$((test_count + 1))
      printf '__codebase_bats_test_%s() {%s\n' "$test_count" "${BASH_REMATCH[2]}"
    elif [[ "$line" =~ $comment_pattern ]]; then
      test_count=$((test_count + 1))
      printf '__codebase_bats_test_%s() { # @test\n' "$test_count"
    else
      printf '%s\n' "$line"
    fi
  done < "$source"
}

bats_public_task_path_has_parse_errors() {
  local source="$1"
  local errors

  if ! errors=$(ast-grep scan \
    --rule "$_CODEBASE_BATS_PATH_RULE_DIR/bash-errors.yml" \
    --json=stream "$source" 2>&1); then
    printf 'ERROR: ast-grep could not inspect BATS Bash syntax: %s\n' "$source" >&2
    printf '%s\n' "$errors" >&2
    return 2
  fi
  [[ -z "$errors" ]]
}

bats_public_task_path_whole_match() {
  local command="$1"
  local pattern="$2"
  local output

  output=$(printf '%s\n' "$command" | ast-grep run \
    --lang bash --pattern "$pattern" --json=compact --stdin 2>/dev/null) || true
  printf '%s\n' "$output" | jq -e \
    'any(.[]; .charCount.leading == 0 and .charCount.trailing == 0)' \
    >/dev/null 2>&1
}

bats_public_task_path_strip_mise_assignments() {
  local command="$1"
  local scratch_dir scratch matches end

  scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/codebase-bats-assignment.XXXXXX")
  scratch="$scratch_dir/command.sh"
  printf '%s\n' "$command" > "$scratch"
  if ! matches=$(ast-grep scan \
    --rule "$_CODEBASE_BATS_PATH_RULE_DIR/mise-assignments.yml" \
    --json=compact "$scratch" 2>/dev/null); then
    rm -rf "$scratch_dir"
    return 1
  fi
  rm -rf "$scratch_dir"
  end=$(printf '%s\n' "$matches" | jq -r \
    'if length == 0 then 0 else ([.[].range.byteOffset.end] | max) end')
  [[ "$end" -gt 0 ]] || return 1
  printf '%s\n' "${command:end}" | sed 's/^[[:space:]]*//'
}

bats_public_task_path_dispatch_match() {
  local command="$1"
  local inspect stripped pattern output attempt

  [[ "$command" == *mise* ]] || return 1
  inspect="$command"

  for attempt in 1 2; do
    # shellcheck disable=SC2016 # ast-grep metavariables are literal.
    for pattern in \
      'mise $$$PRE run $$$ARGS' \
      'run mise $$$PRE run $$$ARGS' \
      'env $$$ENV mise $$$PRE run $$$ARGS' \
      'run env $$$ENV mise $$$PRE run $$$ARGS'; do
      output=$(printf '%s\n' "$inspect" | ast-grep run \
        --lang bash --pattern "$pattern" --json=compact --stdin 2>/dev/null) || true
      if printf '%s\n' "$output" | jq -e \
        'any(.[]; .charCount.leading == 0 and .charCount.trailing == 0)' \
        >/dev/null 2>&1; then
        printf '%s\n' "$output" | jq -c \
          '[.[] | select(.charCount.leading == 0 and .charCount.trailing == 0)][0]'
        return 0
      fi
    done

    [[ "$attempt" -eq 1 ]] || break
    if stripped=$(bats_public_task_path_strip_mise_assignments "$command"); then
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
      "'\$REPO_DIR'"|"'\${REPO_DIR}'"|'$MISE_CONFIG_ROOT'|'${MISE_CONFIG_ROOT}'|\
      '"$MISE_CONFIG_ROOT"'|'"${MISE_CONFIG_ROOT}"'|"'\$MISE_CONFIG_ROOT'"|\
      "'\${MISE_CONFIG_ROOT}'") return 0 ;;
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
  local pattern output word

  [[ "$command" == *bash* && "$command" == *-c* ]] || return 1
  # shellcheck disable=SC2016 # ast-grep metavariables are literal.
  for pattern in \
    'bash -c $SCRIPT' \
    'bash -c $SCRIPT $$$REST' \
    'run bash -c $SCRIPT' \
    'run bash -c $SCRIPT $$$REST' \
    'env $$$ENV bash -c $SCRIPT' \
    'env $$$ENV bash -c $SCRIPT $$$REST' \
    'run env $$$ENV bash -c $SCRIPT' \
    'run env $$$ENV bash -c $SCRIPT $$$REST'; do
    output=$(printf '%s\n' "$command" | ast-grep run \
      --lang bash --pattern "$pattern" --json=compact --stdin 2>/dev/null) || true
    if printf '%s\n' "$output" | jq -e \
      'any(.[]; .charCount.leading == 0 and .charCount.trailing == 0)' \
      >/dev/null 2>&1; then
      word=$(printf '%s\n' "$output" | jq -r \
        '[.[] | select(.charCount.leading == 0 and .charCount.trailing == 0)][0].metaVariables.single.SCRIPT.text')
      bats_public_task_path_decode_static_word "$word"
      return $?
    fi
  done
  return 1
}

bats_public_task_path_fixture_payload() {
  local payload="$1"
  local pattern output match dir

  # This is the maintained copied-fixture form: select another workspace and
  # scrub the parent test's REPO_DIR before asking Mise to resolve the task.
  # Require it to be the whole payload so surrounding root dispatch cannot hide.
  # shellcheck disable=SC2016 # ast-grep metavariables are literal.
  pattern='cd $DIR && env -u REPO_DIR mise $$$PRE run $$$ARGS'
  output=$(printf '%s\n' "$payload" | ast-grep run \
    --lang bash --pattern "$pattern" --json=compact --stdin 2>/dev/null) || true
  if ! printf '%s\n' "$output" | jq -e \
    'any(.[]; .charCount.leading == 0 and .charCount.trailing == 0)' \
    >/dev/null 2>&1; then
    return 1
  fi
  match=$(printf '%s\n' "$output" | jq -c \
    '[.[] | select(.charCount.leading == 0 and .charCount.trailing == 0)][0]')
  dir=$(printf '%s\n' "$match" | jq -r '.metaVariables.single.DIR.text')
  if printf '%s\n' "$match" | jq -e '
    (.metaVariables.multi.PRE // [])
    | any(.text == "-C" or .text == "--cd" or (.text | startswith("--cd=")))
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

  if ! errors=$(ast-grep scan \
    --rule "$_CODEBASE_BATS_PATH_RULE_DIR/bash-errors.yml" \
    --json=stream "$scratch" 2>&1); then
    rm -rf "$scratch_dir"
    return 2
  fi
  if [[ -n "$errors" ]]; then
    rm -rf "$scratch_dir"
    return 2
  fi

  if ! commands=$(ast-grep scan \
    --rule "$_CODEBASE_BATS_PATH_RULE_DIR/commands.yml" \
    --json=compact "$scratch" 2>&1); then
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

bats_public_task_path_command_is_raw() {
  local command="$1"
  local match payload status

  if match=$(bats_public_task_path_dispatch_match "$command") && \
    bats_public_task_path_match_is_raw "$match"; then
    return 0
  fi

  if payload=$(bats_public_task_path_shell_payload "$command"); then
    if bats_public_task_path_script_has_raw_dispatch "$payload"; then
      return 0
    else
      status=$?
      [[ "$status" -eq 1 ]] || return "$status"
    fi
  fi
  return 1
}

bats_public_task_path_scan_file() {
  local source="$1"
  local normalized_dir normalized commands item line command original status

  normalized_dir=$(mktemp -d "${TMPDIR:-/tmp}/codebase-bats-normalized.XXXXXX")
  normalized="$normalized_dir/normalized.sh"
  bats_public_task_path_normalize "$source" > "$normalized"

  if bats_public_task_path_has_parse_errors "$normalized"; then
    :
  else
    status=$?
    printf 'ERROR: BATS Bash syntax is not structurally parseable: %s\n' "$source" >&2
    rm -rf "$normalized_dir"
    return "$status"
  fi
  if ! commands=$(ast-grep scan \
    --rule "$_CODEBASE_BATS_PATH_RULE_DIR/commands-in-tests.yml" \
    --json=compact "$normalized" 2>&1); then
    printf 'ERROR: ast-grep could not inspect BATS test bodies: %s\n' "$source" >&2
    printf '%s\n' "$commands" >&2
    rm -rf "$normalized_dir"
    return 2
  fi
  rm -rf "$normalized_dir"

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    line=$(printf '%s\n' "$item" | jq -r '.range.start.line + 1')
    command=$(printf '%s\n' "$item" | jq -r '.text')
    original=$(awk -v line="$line" 'NR == line { print; exit }' "$source")
    [[ "$original" == *'codebase:ignore bats-public-task-path'* ]] && continue

    if bats_public_task_path_command_is_raw "$command"; then
      printf '%s: %s\n' "$line" "${original#"${original%%[![:space:]]*}"}"
    else
      status=$?
      if [[ "$status" -ne 1 ]]; then
        printf 'ERROR: could not inspect nested Bash payload at %s:%s\n' "$source" "$line" >&2
        return "$status"
      fi
    fi
  done < <(printf '%s\n' "$commands" | jq -c '.[]')
}

bats_public_task_path_lint() {
  local encoded_targets="$1"
  local target resolved name toml file hit status failures=0 hit_count target_output
  local -a targets files

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$target")
  done < <(bats_public_task_path_parse_targets "$encoded_targets")
  if [[ ${#targets[@]} -eq 0 ]]; then
    printf '%s\n' 'ERROR: at least one target is required' >&2
    return 1
  fi

  for target in "${targets[@]}"; do
    resolved=$(resolve_target "$target")
    if [[ ! -e "$resolved" ]]; then
      printf 'ERROR: target does not exist: %s\n' "$resolved" >&2
      return 1
    fi
    name=$(basename "$resolved")
    toml="$resolved/mise.toml"
    if [[ -f "$toml" ]] && rg -q 'codebase:ignore bats-public-task-path' "$toml"; then
      printf 'SKIP  %s (codebase:ignore)\n' "$name"
      continue
    fi

    files=()
    if [[ -d "$resolved/test" ]]; then
      while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
      done < <(fd -t f -e bats --exclude fixtures . "$resolved/test" | LC_ALL=C sort)
    fi
    if [[ ${#files[@]} -eq 0 ]]; then
      printf 'OK    %s (no BATS test files found)\n' "$name"
      continue
    fi

    hit_count=0
    target_output=""
    for file in "${files[@]}"; do
      if hit=$(bats_public_task_path_scan_file "$file"); then
        :
      else
        status=$?
        return "$status"
      fi
      while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        target_output+="  ${file#"$resolved"/}:$hit"$'\n'
        hit_count=$((hit_count + 1))
      done <<< "$hit"
    done

    if [[ "$hit_count" -gt 0 ]]; then
      printf 'FAIL  %s: %s raw repository Mise dispatch(es) in BATS test bodies\n' \
        "$name" "$hit_count"
      printf '%s' "$target_output"
      # shellcheck disable=SC2016 # User guidance is intentionally literal.
      printf '%s\n' '  hint: call the exported test wrapper; use explicit `mise -C <fixture>` only for fixture workspaces.'
      failures=$((failures + 1))
    else
      printf 'OK    %s (%s BATS file(s) use public task paths)\n' "$name" "${#files[@]}"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
