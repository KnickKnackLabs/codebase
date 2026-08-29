#!/usr/bin/env bash
# Built-in evolving lint groups and portable expansion helpers.
#
# Repositories that select a group opt into its future membership when they
# upgrade Codebase. Concrete lint tasks still own applicability.

# codebase_substrate_lint_groups
#
# Emit the independently maintained substrate groups in stable order.
codebase_substrate_lint_groups() {
  printf '%s\n' '@shell' '@mise' '@bats' '@ci' '@shiv'
}

# codebase_available_lint_groups
#
# Emit every selectable group in stable discovery order.
codebase_available_lint_groups() {
  codebase_substrate_lint_groups
  printf '%s\n' '@all'
}

# codebase_lint_group_members <group>
#
# Emit concrete group members in stable execution order.
codebase_lint_group_members() {
  local group="$1"

  case "$group" in
    @shell)
      printf '%s\n' \
        shellcheck \
        or-true \
        bash-empty-argv-forwarding \
        bash-empty-array-expansions \
        exec-stderr-persistence \
        process-substitution-status \
        remote-url-output \
        gum-table
      ;;
    @mise)
      printf '%s\n' \
        mise-settings \
        mise-usage-examples \
        variadic-args \
        mcr-scope
      ;;
    @bats)
      printf '%s\n' \
        bats-test-helper \
        bats-test-task \
        bats-public-task-path
      ;;
    @ci)
      printf '%s\n' \
        github-actions \
        ci-lint-enforcement
      ;;
    @shiv)
      printf '%s\n' \
        caller-pwd-contract \
        mise-shiv-plugin
      ;;
    @all)
      local substrate
      while IFS= read -r substrate; do
        codebase_lint_group_members "$substrate"
      done <<< "$(codebase_substrate_lint_groups)"
      ;;
    *)
      printf 'ERROR: unknown lint group: %s\n' "$group" >&2
      printf 'Known groups: ' >&2
      codebase_available_lint_groups | paste -sd ' ' - >&2
      return 1
      ;;
  esac
}

# codebase_expand_lint_entries <entry>...
#
# Expand concrete names and @groups left to right, deduplicating by first
# occurrence. Uses only Bash 3.2-compatible primitives.
codebase_expand_lint_entries() {
  local entry members rule
  local seen=' '

  for entry in "$@"; do
    if [[ "$entry" == @* ]]; then
      if ! members=$(codebase_lint_group_members "$entry"); then
        return 1
      fi
    else
      members="$entry"
    fi

    while IFS= read -r rule; do
      [[ -n "$rule" ]] || continue
      case "$seen" in
        *" $rule "*) continue ;;
      esac
      printf '%s\n' "$rule"
      seen="${seen}${rule} "
    done <<< "$members"
  done
}
