#!/usr/bin/env bash
# Shared test helper — routes task invocations through mise instead of
# calling .mise/tasks/* scripts directly.
#
# Why: direct-bash invocation bypasses mise's USAGE parser, CALLER_PWD
# plumbing, and flag handling. Tests that fake the usage_* env vars hide
# real bugs. See fold/notes/bats-tool-testing.md for the full rationale.
#
# Note: we derive REPO_DIR from $BATS_TEST_DIRNAME (set by bats from the
# actual .bats file path), not $MISE_CONFIG_ROOT. MCR is inherited from
# the ambient agent session (whose launcher is itself a mise task) and
# can point at the wrong repo. See fold/notes/mise-gotchas.md for the
# full mechanism.
REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export REPO_DIR

# codebase() — call any codebase task through mise. Tests set CALLER_PWD
# for tasks that need it (pre-commit resolves the target git repo from it).
#
# Notes:
#   - We capture $PWD *before* the cd — otherwise the fallback would
#     resolve against REPO_DIR, not the caller's dir.
#   - Runs in a subshell so the cd doesn't leak into later commands in
#     the calling test. (bats tests are isolated, but defensive.)
codebase() {
  local caller="${CALLER_PWD:-$PWD}"
  ( cd "$REPO_DIR" && CALLER_PWD="$caller" mise run -q "$@" )
}
export -f codebase
