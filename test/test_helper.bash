#!/usr/bin/env bash
# Shared test helper — routes task invocations through mise instead of
# calling .mise/tasks/* scripts directly.
#
# Why: direct-bash invocation bypasses mise's USAGE parser, CALLER_PWD
# plumbing, and flag handling. Tests that fake the usage_* env vars hide
# real bugs. See fold/notes/bats-tool-testing.md for the full rationale.
#
# Note: we self-locate REPO_DIR via ${BASH_SOURCE[0]} rather than
# $BATS_TEST_DIRNAME or $MISE_CONFIG_ROOT.
#
#   - $MISE_CONFIG_ROOT is unreliable here: agent sessions are themselves
#     mise tasks, so MCR in the session shell points at the launcher's
#     repo, not the repo under test. See fold/notes/mise-gotchas.md for
#     the full mechanism.
#
#   - $BATS_TEST_DIRNAME inside a loaded helper is the *calling .bats
#     file's* directory, not this helper's directory. Since codebase's
#     test files are nested (test/scan/scan.bats, test/lint/mcr-scope/
#     mcr-scope.bats, etc.), $BATS_TEST_DIRNAME/.. resolves to a
#     different path depending on which file loaded us. ${BASH_SOURCE[0]}
#     is this file's own path — stable across loaders.
#
# See three-primitives-three-contexts.md in den for the full table.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
