#!/usr/bin/env bash
# Require repositories with a configured lint portfolio to expose one direct
# aggregate `codebase lint` command in a normal GitHub Actions workflow step.
#
# This is intentionally structural rather than a shell dataflow analyzer. It
# recognizes direct `codebase lint` and `mise exec -- codebase lint` command
# syntax in jobs.*.steps[*].run values. It does not trace local tasks, prove
# conditional reachability, or interpret hard-coded per-rule loops.

_CODEBASE_CI_LINT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_CI_LINT_RULE_DIR="$_CODEBASE_CI_LINT_LIB_DIR/../rules/ci-lint-enforcement"
# shellcheck source=./codebase-config.sh
source "$_CODEBASE_CI_LINT_LIB_DIR/codebase-config.sh"

ci_lint_enforcement_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0
  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

ci_lint_enforcement_workflows() {
  local repo="$1"
  local workflows_dir="$repo/.github/workflows"
  local workflow

  [[ -d "$workflows_dir" ]] || return 0
  for workflow in "$workflows_dir"/*.yml "$workflows_dir"/*.yaml; do
    [[ -f "$workflow" ]] && printf '%s\n' "$workflow"
  done | LC_ALL=C sort
}

ci_lint_enforcement_normalize_expressions() {
  local run="$1"
  local normalized prefix remainder

  # GitHub expands these expressions before handing `run` to the shell. Replace
  # their opaque contents so Bash parsing remains structural and an expression
  # cannot manufacture an apparent Codebase command.
  normalized="$run"
  # shellcheck disable=SC2016 # GitHub expression delimiters are literal.
  while [[ "$normalized" == *'${{'* ]]; do
    prefix=${normalized%%'${{'*}
    remainder=${normalized#*'${{'}
    if [[ "$remainder" != *'}}'* ]]; then
      printf '%s\n' 'ERROR: unterminated GitHub expression in workflow run value' >&2
      return 1
    fi
    normalized="${prefix}__GITHUB_EXPRESSION__${remainder#*'}}'}"
  done
  printf '%s\n' "$normalized"
}

ci_lint_enforcement_run_has_aggregate() {
  local run="$1"
  local normalized errors output status pattern

  if ! normalized=$(ci_lint_enforcement_normalize_expressions "$run"); then
    return 2
  fi

  if ! errors=$(printf '%s\n' "$normalized" | ast-grep scan \
    --rule "$_CODEBASE_CI_LINT_RULE_DIR/bash-errors.yml" \
    --json=stream --stdin 2>&1); then
    printf 'ERROR: ast-grep could not inspect workflow Bash syntax\n' >&2
    printf '%s\n' "$errors" >&2
    return 2
  fi
  if [[ -n "$errors" ]]; then
    printf 'ERROR: workflow run value is not parseable Bash\n' >&2
    return 2
  fi

  # shellcheck disable=SC2016 # ast-grep metavariable syntax is literal.
  for pattern in 'codebase lint $$$ARGS' 'mise exec -- codebase lint $$$ARGS'; do
    if output=$(printf '%s\n' "$normalized" | ast-grep run \
      --lang bash --pattern "$pattern" --json=compact --stdin 2>&1); then
      return 0
    else
      status=$?
      if [[ "$status" -ne 1 || "$output" != '[]' ]]; then
        printf 'ERROR: ast-grep could not inspect aggregate lint commands\n' >&2
        printf '%s\n' "$output" >&2
        return 2
      fi
    fi
  done
  return 1
}

ci_lint_enforcement_workflow_has_aggregate() {
  local workflow="$1"
  local steps step shell run status
  local found=1

  if ! steps=$(yq eval --output-format=json --indent=0 '
    .jobs // {} |
    .[] |
    select(tag == "!!map") |
    .steps // [] |
    .[] |
    select(tag == "!!map" and has("run")) |
    {"shell": (.shell // ""), "run": .run}
  ' "$workflow" 2>&1); then
    printf 'ERROR: workflow is not parseable YAML: %s\n' "$workflow" >&2
    printf '%s\n' "$steps" >&2
    return 2
  fi

  while IFS= read -r step; do
    [[ -n "$step" ]] || continue
    if ! shell=$(printf '%s\n' "$step" | jq -er '.shell | select(type == "string")') ||
      ! run=$(printf '%s\n' "$step" | jq -er '.run | select(type == "string")'); then
      printf 'ERROR: workflow run step does not contain string shell and run values in %s\n' \
        "$workflow" >&2
      return 2
    fi

    # ast-grep parses Bash. Ignore steps that explicitly select another
    # interpreter rather than rejecting otherwise valid workflow syntax.
    case "$shell" in
      ""|bash|bash\ *|sh|sh\ *) ;;
      *) continue ;;
    esac

    if ci_lint_enforcement_run_has_aggregate "$run"; then
      found=0
    else
      status=$?
      [[ "$status" -eq 1 ]] || {
        printf 'ERROR: could not inspect workflow run value in %s\n' "$workflow" >&2
        return "$status"
      }
    fi
  done <<< "$steps"

  return "$found"
}

ci_lint_enforcement_lint() {
  local encoded_targets="$1"
  local target resolved repo name rules rule_count workflow status enforcement_count
  local failures=0
  local -a targets workflows

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$target")
  done < <(ci_lint_enforcement_parse_targets "$encoded_targets")

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
    repo=$(codebase_resolve_repo "$resolved") || return 1
    name=$(codebase_name "$repo") || return 1
    rules=$(codebase_configured_lint_rules "$repo")
    if [[ -z "$rules" ]]; then
      printf 'SKIP  %s (no configured codebase lint portfolio)\n' "$name"
      continue
    fi
    rule_count=$(printf '%s\n' "$rules" | awk 'NF { count++ } END { print count + 0 }')

    workflows=()
    while IFS= read -r workflow; do
      [[ -n "$workflow" ]] && workflows+=("$workflow")
    done < <(ci_lint_enforcement_workflows "$repo")

    enforcement_count=0
    for workflow in ${workflows[@]+"${workflows[@]}"}; do
      if ci_lint_enforcement_workflow_has_aggregate "$workflow"; then
        enforcement_count=$((enforcement_count + 1))
      else
        status=$?
        [[ "$status" -eq 1 ]] || return "$status"
      fi
    done

    if [[ "$enforcement_count" -gt 0 ]]; then
      printf 'OK    %s (%s configured rule(s), directly enforced in %s workflow(s))\n' \
        "$name" "$rule_count" "$enforcement_count"
    else
      printf 'FAIL  %s: configured codebase lints are not directly enforced in GitHub Actions\n' "$name"
      # shellcheck disable=SC2016 # User guidance intentionally shows a literal command.
      printf '%s\n' '  hint: add a workflow step whose run value directly calls `codebase lint`.'
      failures=$((failures + 1))
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
