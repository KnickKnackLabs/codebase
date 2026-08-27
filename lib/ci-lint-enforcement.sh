#!/usr/bin/env bash
# Require repositories with a configured lint portfolio to expose one direct,
# failure-propagating aggregate `codebase lint` GitHub Actions workflow step.
#
# This is intentionally structural rather than a workflow reachability or shell
# dataflow analyzer. It recognizes a whole run value containing only direct
# `codebase lint` or `mise exec -- codebase lint` command syntax. It does not
# trace local tasks, prove workflow reachability, or interpret per-rule loops.

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
  local normalized prefix remainder char next
  local index in_string expression_closed

  # GitHub expands these expressions before handing `run` to the shell. Replace
  # their opaque contents so Bash parsing remains structural and an expression
  # cannot manufacture an apparent Codebase command.
  normalized="$run"
  # shellcheck disable=SC2016 # GitHub expression delimiters are literal.
  while [[ "$normalized" == *'${{'* ]]; do
    prefix=${normalized%%'${{'*}
    remainder=${normalized#*'${{'}
    index=0
    in_string=0
    expression_closed=0

    # GitHub expression strings use single quotes and escape a quote by
    # doubling it. A `}}` inside such a string is data, not the delimiter.
    while [[ "$index" -lt "${#remainder}" ]]; do
      char=${remainder:index:1}
      next=${remainder:index+1:1}
      if [[ "$in_string" -eq 1 ]]; then
        if [[ "$char" == "'" ]]; then
          if [[ "$next" == "'" ]]; then
            index=$((index + 2))
            continue
          fi
          in_string=0
        fi
      elif [[ "$char" == "'" ]]; then
        in_string=1
      elif [[ "$char$next" == '}}' ]]; then
        normalized="${prefix}__GITHUB_EXPRESSION__${remainder:index+2}"
        expression_closed=1
        break
      fi
      index=$((index + 1))
    done

    if [[ "$expression_closed" -eq 0 ]]; then
      printf '%s\n' 'ERROR: unterminated GitHub expression in workflow run value' >&2
      return 1
    fi
  done
  printf '%s\n' "$normalized"
}

ci_lint_enforcement_run_has_aggregate() {
  local run="$1"
  local normalized errors output status pattern

  if ! normalized=$(ci_lint_enforcement_normalize_expressions "$run"); then
    return 2
  fi

  # GitHub substitutes expressions as unescaped text before invoking the shell.
  # An expression can therefore inject control flow that masks the command's
  # status, even when the expression appears inside shell quotes.
  [[ "$normalized" == "$run" ]] || return 1

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

  # A descendant match only proves that the spelling appears somewhere. Require
  # the match to cover the whole parsed run value so `|| true`, conditionals,
  # functions, and surrounding commands cannot suppress or replace its status.
  # shellcheck disable=SC2016 # ast-grep metavariable syntax is literal.
  for pattern in 'codebase lint $$$ARGS' 'mise exec -- codebase lint $$$ARGS'; do
    if output=$(printf '%s\n' "$normalized" | ast-grep run \
      --lang bash --pattern "$pattern" --json=compact --stdin 2>&1); then
      if printf '%s\n' "$output" | jq -e \
        'any(.[]; .charCount.leading == 0 and .charCount.trailing == 0)' \
        >/dev/null; then
        return 0
      fi
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

  # yq can emit a partial object when this stream has no matching run steps.
  # Filter after projection so zero-step workflows produce no candidate record.
  if ! steps=$(yq eval --output-format=json --indent=0 '
    . as $workflow |
    ($workflow.defaults.run.shell // "") as $workflow_shell |
    (.jobs // {}) |
    .[] |
    select(tag == "!!map" and has("steps")) |
    . as $job |
    .steps[] |
    select(tag == "!!map" and has("run")) |
    {
      "shell": (.shell // $job.defaults.run.shell // $workflow_shell),
      "run": .run,
      "continueOnError": (."continue-on-error" // false),
      "jobContinueOnError": ($job."continue-on-error" // false)
    } |
    select(has("run"))
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

    # ast-grep parses Bash. Accept only GitHub's built-in Bash/sh selectors.
    # A custom template beginning with `bash ` can ignore the generated script
    # or mask its status, so it cannot prove failure propagation.
    case "$shell" in
      ""|bash|sh) ;;
      *) continue ;;
    esac

    # A direct command cannot enforce failure when the step or its job is
    # allowed to fail. Dynamic expressions cannot prove the required false value.
    printf '%s\n' "$step" | jq -e \
      '.continueOnError == false and .jobContinueOnError == false' \
      >/dev/null || continue

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
      printf 'OK    %s (%s configured rule(s), direct aggregate declaration in %s workflow(s))\n' \
        "$name" "$rule_count" "$enforcement_count"
    else
      printf 'FAIL  %s: no direct failure-propagating `codebase lint` declaration in GitHub Actions\n' \
        "$name"
      # shellcheck disable=SC2016 # User guidance intentionally shows a literal command.
      printf '%s\n' '  hint: add a run step containing only `codebase lint` (or `mise exec -- codebase lint`).'
      failures=$((failures + 1))
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
