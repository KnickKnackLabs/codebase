#!/usr/bin/env bash
# Require examples for every public file-based Mise task with arguments or flags.

_MISE_USAGE_EXAMPLES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./shell-files.sh
source "$_MISE_USAGE_EXAMPLES_LIB_DIR/shell-files.sh"

mise_usage_examples_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0

  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

mise_usage_examples_ignore_has_reason() {
  local file="$1"

  rg -q '^[[:space:]]*#[[:space:]]*codebase:ignore[[:space:]]+mise-usage-examples[[:space:]]+--[[:space:]]+[^[:space:]]' "$file"
}

mise_usage_examples_header_state() {
  local file="$1"

  awk '
    NR == 1 && /^#!/ { next }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ {
      if ($0 ~ /^#USAGE[[:space:]]+(arg|flag)([[:space:]]|$)/) {
        has_interface = 1
      }
      if ($0 ~ /^#USAGE[[:space:]]+example([[:space:]]|$)/) {
        has_example = 1
      }
      next
    }
    { exit }
    END { printf "%d %d\n", has_interface, has_example }
  ' "$file"
}

mise_usage_examples_public_tasks() {
  local target="$1"
  local tasks_root="$target/.mise/tasks"
  local tasks_json

  [[ -d "$tasks_root" ]] || return 0

  if ! tasks_json=$(mise -q -C "$target" tasks --json 2>&1); then
    printf 'ERROR: Mise could not inspect public tasks in %s\n' "$target" >&2
    printf '%s\n' "$tasks_json" | sed 's/^/  /' >&2
    return 1
  fi

  if ! jq -c --arg prefix "$tasks_root/" '
    .[]
    | select(.source | type == "string" and startswith($prefix))
    | {name, source}
  ' <<< "$tasks_json"; then
    printf 'ERROR: Mise returned invalid task metadata for %s\n' "$target" >&2
    return 1
  fi
}

mise_usage_examples_check_target() {
  local target="$1"
  local name tasks_root task_record task_name task source state has_interface has_example tasks
  local target_failures=0

  name=$(basename "$target")
  tasks_root="$target/.mise/tasks"

  if [[ -f "$target/mise.toml" ]] && mise_usage_examples_ignore_has_reason "$target/mise.toml"; then
    echo "SKIP  $name (codebase:ignore mise-usage-examples)"
    return 0
  fi

  if [[ ! -d "$tasks_root" ]]; then
    echo "OK    $name (no .mise/tasks)"
    return 0
  fi

  if ! tasks=$(mise_usage_examples_public_tasks "$target"); then
    return 1
  fi

  while IFS= read -r task_record; do
    [[ -n "$task_record" ]] || continue
    task_name=$(jq -r '.name' <<< "$task_record")
    source=$(jq -r '.source' <<< "$task_record")
    task="$source"
    if ! state=$(mise_usage_examples_header_state "$task"); then
      printf 'ERROR: could not inspect Mise task source: %s\n' "$task" >&2
      return 1
    fi
    read -r has_interface has_example <<< "$state"

    [[ "$has_interface" == "1" ]] || continue
    [[ "$has_example" == "1" ]] && continue
    mise_usage_examples_ignore_has_reason "$task" && continue

    printf 'FAIL  %s  %s: public task %s declares arguments or flags but no #USAGE example\n' \
      "$name" "${task#"$target/"}" "$task_name"
    target_failures=$((target_failures + 1))
  done <<< "$tasks"

  if [[ "$target_failures" -eq 0 ]]; then
    echo "OK    $name"
  fi

  [[ "$target_failures" -le 255 ]] || target_failures=255
  return "$target_failures"
}

mise_usage_examples_lint() {
  local encoded_targets="$1"
  local target canonical status
  local failures=0
  local -a targets

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done < <(mise_usage_examples_parse_targets "$encoded_targets")

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "ERROR: at least one target is required" >&2
    return 1
  fi

  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      echo "ERROR: target does not exist: $target" >&2
      return 1
    fi
    if [[ ! -d "$target" ]]; then
      echo "ERROR: target is not a directory: $target" >&2
      return 1
    fi

    canonical=$(cd "$target" && pwd -P)
    if mise_usage_examples_check_target "$canonical"; then
      :
    else
      status=$?
      failures=$((failures + status))
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
