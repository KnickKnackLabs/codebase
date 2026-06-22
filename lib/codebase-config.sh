#!/usr/bin/env bash
# Shared configuration helpers for codebase tasks.
#
# This file is a lib, not a mise task. Self-locate via BASH_SOURCE rather than
# reading MISE_CONFIG_ROOT; agent sessions can inherit a stale MCR from the
# launcher repo. See fold/notes/mise-gotchas.md.

_CODEBASE_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_CONFIG_LIB_DIR/shell-files.sh"

# codebase_git_root <path>
#
# Resolve <path> to the containing git repo root. Returns non-zero when the
# path is not inside a git repository.
codebase_git_root() {
  local path="$1"
  git -C "$path" rev-parse --show-toplevel 2>/dev/null
}

# codebase_resolve_repo <target>
#
# Resolve a caller-relative target path to a repository/config root. If the
# target is inside a git repo, emit that repo's top-level directory. For
# non-git fixture workspaces, fall back to the target directory itself.
codebase_resolve_repo() {
  local target="$1"
  local resolved root git_dir

  resolved=$(resolve_target "$target")

  if [[ ! -e "$resolved" ]]; then
    echo "ERROR: target does not exist: $resolved" >&2
    return 1
  fi

  if [[ -d "$resolved" && -f "$resolved/mise.toml" ]]; then
    (cd "$resolved" && pwd -P)
    return 0
  fi

  git_dir="$resolved"
  [[ -d "$git_dir" ]] || git_dir=$(dirname "$git_dir")
  if root=$(codebase_git_root "$git_dir"); then
    printf '%s\n' "$root"
    return 0
  fi

  if [[ -d "$resolved" ]]; then
    (cd "$resolved" && pwd -P)
    return 0
  fi

  (cd "$(dirname "$resolved")" && pwd -P)
}

# codebase_configured_lint_rules <repo-root>
#
# Emit configured [_.codebase].lint rules, one per line. Rule names are expected
# to be simple task suffixes such as "mise-settings" or "gum-table".
codebase_configured_lint_rules() {
  local repo_root="$1"
  local toml="$repo_root/mise.toml"
  local raw

  [[ -f "$toml" ]] || return 0

  if ! raw=$(mise config get -f "$toml" _.codebase.lint 2>/dev/null); then
    return 0
  fi

  printf '%s\n' "$raw" | awk '{
    gsub(/[\[\]",]/, " ")
    for (i = 1; i <= NF; i++) print $i
  }'
}

# codebase_default_scope_for_rule <rule>
#
# Emit the built-in default scope for rules whose useful target is narrower
# than the whole repo. Rules not listed here default to the repo root.
codebase_default_scope_for_rule() {
  local rule="$1"

  case "$rule" in
    mise-settings) printf '%s\n' "." ;;
    gum-table) printf '%s\n' ".mise/tasks" ;;
    *) printf '%s\n' "." ;;
  esac
}

# codebase_scope_for_rule <repo-root> <rule>
#
# Emit the effective scope for a rule: user override from
# [_.codebase.scope] when present, otherwise the built-in default.
codebase_scope_for_rule() {
  local repo_root="$1"
  local rule="$2"
  local toml="$repo_root/mise.toml"
  local value

  if [[ -f "$toml" ]] && value=$(mise config get -f "$toml" "_.codebase.scope.$rule" 2>/dev/null); then
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  codebase_default_scope_for_rule "$rule"
}

# codebase_targets_for_rule <repo-root> <rule>
#
# Emit the concrete target path(s) for a rule after scope resolution.
# When the scope value is a space-separated list of paths (from TOML string
# values like or-true = ".mise/tasks lib"), emits one line per target.
codebase_targets_for_rule() {
  local repo_root="$1"
  local rule="$2"
  local scope token

  scope=$(codebase_scope_for_rule "$repo_root" "$rule")

  # Handle empty/dot scope — single target: the repo root itself.
  case "$scope" in
    ""|".") printf '%s\n' "$repo_root"; return 0 ;;
  esac

  # Split scope on whitespace into individual path tokens and resolve each.
  # This supports multi-path scopes like ".mise/tasks lib" from TOML.
  for token in $scope; do
    case "$token" in
      /*) printf '%s\n' "$token" ;;
      *) printf '%s/%s\n' "$repo_root" "$token" ;;
    esac
  done
}
