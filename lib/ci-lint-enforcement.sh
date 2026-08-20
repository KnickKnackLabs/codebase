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

ci_lint_enforcement_decode_block() {
  local raw="$1"
  local indicator body

  indicator=${raw%%$'\n'*}
  [[ "$raw" != "$indicator" ]] || {
    printf 'ERROR: YAML block scalar has no body\n' >&2
    return 1
  }
  [[ "$indicator" =~ ^[\|\>][1-9]?[+-]?$ || "$indicator" =~ ^[\|\>][+-][1-9]$ ]] || {
    printf 'ERROR: unsupported YAML block scalar indicator: %s\n' "$indicator" >&2
    return 1
  }
  body=${raw#*$'\n'}

  printf '%s\n' "$body" | awk -v style="${indicator:0:1}" '
    {
      lines[NR] = $0
      if ($0 ~ /[^ ]/) {
        match($0, /[^ ]/)
        indent = RSTART - 1
        if (!have_indent || indent < minimum) minimum = indent
        have_indent = 1
      }
    }
    END {
      if (!have_indent) exit
      previous = ""
      for (i = 1; i <= NR; i++) {
        line = substr(lines[i], minimum + 1)
        if (style == "|") {
          print line
        } else if (i == 1) {
          printf "%s", line
        } else if (previous == "" || line == "") {
          printf "\n%s", line
        } else {
          printf " %s", line
        }
        previous = line
      }
      if (style == ">") printf "\n"
    }
  '
}

ci_lint_enforcement_decode_run() {
  local encoded="$1"
  local raw

  if ! raw=$(printf '%s\n' "$encoded" | jq -r '.'); then
    printf 'ERROR: could not decode extracted YAML scalar\n' >&2
    return 1
  fi

  case "$raw" in
    \|*|\>*)
      ci_lint_enforcement_decode_block "$raw"
      ;;
    \"*)
      [[ "$raw" == *\" ]] || {
        printf 'ERROR: unterminated double-quoted YAML run value\n' >&2
        return 1
      }
      if ! printf '%s\n' "$raw" | jq -r '.'; then
        printf 'ERROR: unsupported double-quoted YAML run value\n' >&2
        return 1
      fi
      ;;
    \'*)
      [[ "$raw" == *\' && "$raw" != *$'\n'* ]] || {
        printf 'ERROR: unsupported single-quoted YAML run value\n' >&2
        return 1
      }
      raw=${raw#\'}
      raw=${raw%\'}
      printf '%s\n' "${raw//\'\'/\'}"
      ;;
    *)
      [[ "$raw" != *$'\n'* ]] || {
        printf 'ERROR: unsupported multiline plain YAML run value\n' >&2
        return 1
      }
      printf '%s\n' "$raw"
      ;;
  esac
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
  local syntax_errors ast_output encoded_values encoded run status
  local found=1

  if ! syntax_errors=$(ast-grep scan \
    --rule "$_CODEBASE_CI_LINT_RULE_DIR/yaml-errors.yml" \
    --json=stream "$workflow" 2>&1); then
    printf 'ERROR: ast-grep could not inspect YAML syntax in %s\n' "$workflow" >&2
    printf '%s\n' "$syntax_errors" >&2
    return 2
  fi
  if [[ -n "$syntax_errors" ]]; then
    printf 'ERROR: workflow is not parseable YAML: %s\n' "$workflow" >&2
    return 2
  fi

  if ! ast_output=$(ast-grep scan \
    --rule "$_CODEBASE_CI_LINT_RULE_DIR/run-values.yml" \
    --json=stream "$workflow" 2>&1); then
    printf 'ERROR: ast-grep could not extract workflow run values from %s\n' "$workflow" >&2
    printf '%s\n' "$ast_output" >&2
    return 2
  fi
  if ! encoded_values=$(printf '%s\n' "$ast_output" |
    jq -c '.metaVariables.single.RUN.text' 2>&1); then
    printf 'ERROR: could not parse extracted workflow run values from %s\n' "$workflow" >&2
    printf '%s\n' "$encoded_values" >&2
    return 2
  fi

  while IFS= read -r encoded; do
    [[ -n "$encoded" ]] || continue
    if ! run=$(ci_lint_enforcement_decode_run "$encoded"); then
      printf 'ERROR: could not decode workflow run value in %s\n' "$workflow" >&2
      return 2
    fi
    if ci_lint_enforcement_run_has_aggregate "$run"; then
      found=0
    else
      status=$?
      [[ "$status" -eq 1 ]] || {
        printf 'ERROR: could not inspect workflow run value in %s\n' "$workflow" >&2
        return "$status"
      }
    fi
  done <<< "$encoded_values"

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
