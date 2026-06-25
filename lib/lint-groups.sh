#!/usr/bin/env bash
# Built-in lint group definitions and expansion helpers.
#
# Groups are named bundles of lint rules that repos can reference with
# the @prefix, e.g. lint = ["@maintained-tool"]. This eliminates the
# need to enumerate every convention rule in every repo's mise.toml.
#
# To add a new group:
#   1. Define it in _CODEBASE_LINT_GROUPS below
#   2. List its rules (lowercase-hyphenated, matching .mise/tasks/lint/<name>)
#   3. Update docs in AGENTS.md and/or README
#
# To add a new rule to an existing group:
#   1. Add the rule name to the group's string
#   2. Ensure member repos can opt out via [_.codebase].lint_exclude if needed

# === Built-in group definitions ===

declare -A _CODEBASE_LINT_GROUPS

# @maintained-tool — the standard convention bundle for maintained KKL
# tool repos (CLI tools, libraries, SDK wrappers). Includes all shared
# conventions that every maintained-tool repo should follow.
_CODEBASE_LINT_GROUPS["@maintained-tool"]="mise-settings gum-table bats-test-helper bats-test-task mcr-scope or-true shellcheck caller-pwd-contract github-actions"

# Future groups:
# _CODEBASE_LINT_GROUPS["@minimal"]="mise-settings shellcheck"
# _CODEBASE_LINT_GROUPS["@ci-only"]="github-actions mise-settings"

# === Public API ===

# codebase_expand_lint_groups <rule-entry>...
#
# Accepts one or more lint entries (rule names or @group references).
# Emits concrete rule names, one per line, expanding @-groups inline.
# Unknown groups produce an ERROR message on stderr and return 1.
# Duplicates are preserved (caller may deduplicate if needed).
codebase_expand_lint_groups() {
  local entry expanded rules

  for entry in "$@"; do
    if [[ "$entry" == @* ]]; then
      expanded="${_CODEBASE_LINT_GROUPS[$entry]:-}"
      if [[ -z "$expanded" ]]; then
        echo "ERROR: unknown lint group '$entry'" >&2
        printf '  known groups:' >&2
        local g
        for g in "${!_CODEBASE_LINT_GROUPS[@]}"; do
          printf ' %s' "$g" >&2
        done
        echo >&2
        return 1
      fi
      # Word-split the expanded string: each token is a rule name.
      # shellcheck disable=SC2086 — intentional word-splitting
      for _rule in $expanded; do
        printf '%s\n' "$_rule"
      done
    else
      printf '%s\n' "$entry"
    fi
  done
}

# codebase_available_groups
#
# Emit all known group names, one per line, suitable for help display.
codebase_available_groups() {
  local name
  for name in "${!_CODEBASE_LINT_GROUPS[@]}"; do
    printf '%s\n' "$name"
  done
}

# codebase_group_members <group-name>
#
# Emit the rule names belonging to a group, one per line.
# Returns 1 if the group is unknown.
codebase_group_members() {
  local group="$1"
  local members="${_CODEBASE_LINT_GROUPS[$group]:-}"
  if [[ -z "$members" ]]; then
    return 1
  fi
  printf '%s\n' $members
}

# codebase_has_group_reference <rule-name>...
#
# Returns 0 if any entry starts with @, 1 otherwise.
codebase_has_group_reference() {
  local entry
  for entry in "$@"; do
    if [[ "$entry" == @* ]]; then
      return 0
    fi
  done
  return 1
}