#!/usr/bin/env bash
# Validate the Mise backend contract for repositories that declare shiv tools.

_MISE_SHIV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./shell-files.sh
source "$_MISE_SHIV_LIB_DIR/shell-files.sh"

_MISE_SHIV_PLUGIN_URL="https://github.com/KnickKnackLabs/vfox-shiv"

mise_shiv_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0

  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

mise_shiv_tools_declared() {
  local toml="$1"
  local tools

  if ! tools=$(mise config get -f "$toml" tools 2>/dev/null); then
    return 1
  fi

  if grep -qE '^"shiv:[^"]+"[[:space:]]*=' <<< "$tools"; then
    return 0
  fi

  # Mise renders table-form tool options such as
  # [tools."shiv:codebase"] as ["shiv:codebase"] here.
  grep -qE '^\["shiv:[^"]+"(\.|\])' <<< "$tools"
}

mise_shiv_plugin_source_valid() {
  local source="$1"

  [[ "$source" =~ ^https://github\.com/KnickKnackLabs/vfox-shiv(\.git)?(#[^[:space:]]+)?$ ]]
}

mise_shiv_config_value() {
  local toml="$1"
  local key="$2"

  mise config get -f "$toml" "$key" 2>/dev/null
}

mise_shiv_plugin_lint() {
  local encoded_targets="$1"
  local failures=0 target name toml parse_output experimental plugin
  local -a targets missing

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done < <(mise_shiv_parse_targets "$encoded_targets")

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "ERROR: at least one target is required" >&2
    return 1
  fi

  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      echo "ERROR: target does not exist: $target" >&2
      return 1
    fi

    name=$(basename "$target")
    toml="$target/mise.toml"

    if [[ ! -f "$toml" ]]; then
      echo "FAIL  $name: no mise.toml found"
      failures=$((failures + 1))
      continue
    fi

    if grep -m1 -q 'codebase:ignore mise-shiv-plugin' "$toml"; then
      echo "SKIP  $name (codebase:ignore)"
      continue
    fi

    if ! parse_output=$(mise config get -f "$toml" 2>&1); then
      echo "FAIL  $name: mise.toml could not be parsed"
      printf '%s\n' "$parse_output" | sed 's/^/  /'
      failures=$((failures + 1))
      continue
    fi

    if ! mise_shiv_tools_declared "$toml"; then
      echo "OK    $name (no shiv tools declared)"
      continue
    fi

    missing=()
    experimental=""
    plugin=""
    if ! experimental=$(mise_shiv_config_value "$toml" settings.experimental); then
      :
    fi
    if ! plugin=$(mise_shiv_config_value "$toml" plugins.shiv); then
      :
    fi

    [[ "$experimental" == "true" ]] || missing+=("settings.experimental = true")
    mise_shiv_plugin_source_valid "$plugin" || missing+=("plugins.shiv = \"$_MISE_SHIV_PLUGIN_URL\"")

    if [[ ${#missing[@]} -eq 0 ]]; then
      echo "OK    $name"
    else
      echo "FAIL  $name: missing or invalid ${missing[*]}"
      failures=$((failures + 1))
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
