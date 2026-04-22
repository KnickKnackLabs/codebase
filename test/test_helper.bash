#!/usr/bin/env bash
# Shared test helper — routes task invocations through mise instead of
# calling .mise/tasks/* scripts directly.
#
# Why: direct-bash invocation bypasses mise's USAGE parser, CALLER_PWD
# plumbing, and flag handling. Tests that fake the usage_* env vars hide
# real bugs. See fold/notes/bats-tool-testing.md for the full rationale.

if [ -z "${MISE_CONFIG_ROOT:-}" ]; then
  echo "MISE_CONFIG_ROOT not set — run tests via: mise run test" >&2
  exit 1
fi

# codebase() — call any codebase task through mise. Tests set CALLER_PWD
# for tasks that need it (pre-commit resolves the target git repo from it).
#
# Notes:
#   - We capture $PWD *before* the cd — otherwise the fallback would
#     resolve against MISE_CONFIG_ROOT, not the caller's dir.
#   - Runs in a subshell so the cd doesn't leak into later commands in
#     the calling test. (bats tests are isolated, but defensive.)
codebase() {
  local caller="${CALLER_PWD:-$PWD}"
  ( cd "$MISE_CONFIG_ROOT" && CALLER_PWD="$caller" mise run -q "$@" )
}
export -f codebase
