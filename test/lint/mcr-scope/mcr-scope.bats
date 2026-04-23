#!/usr/bin/env bats
# Tests for lint:mcr-scope rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Detection
# ============================================================================

@test "mcr-scope: passes on a clean codebase" {
  run codebase lint:mcr-scope "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "mcr-scope: flags MISE_CONFIG_ROOT in test helpers" {
  run codebase lint:mcr-scope "$FIXTURES/dirty-test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-test"* ]]
  [[ "$output" == *"test/helpers.bash"* ]]
  [[ "$output" == *"MISE_CONFIG_ROOT"* ]]
}

@test "mcr-scope: flags MISE_CONFIG_ROOT in .bats files" {
  run codebase lint:mcr-scope "$FIXTURES/dirty-test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test/foo.bats"* ]]
}

@test "mcr-scope: flags MISE_CONFIG_ROOT in lib files" {
  run codebase lint:mcr-scope "$FIXTURES/dirty-lib"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty-lib"* ]]
  [[ "$output" == *"lib/bad.sh"* ]]
}

@test "mcr-scope: flags hits in both test/ and lib/ trees" {
  run codebase lint:mcr-scope "$FIXTURES/dirty-both"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test/helpers.bash"* ]]
  [[ "$output" == *"lib/util.sh"* ]]
}

@test "mcr-scope: flags brace-form references (all bash expansion operators)" {
  run codebase lint:mcr-scope "$FIXTURES/brace-form"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  # Six distinct brace-form hits: ${MCR:-}, ${MCR}, ${MCR:+},
  # ${MCR%}, ${MCR#}, ${MCR/}.
  [[ "$output" == *"6 "* ]]
}

@test "mcr-scope: does NOT flag MCR in full-line comments" {
  run codebase lint:mcr-scope "$FIXTURES/comment-only"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "test_helper: REPO_DIR resolves to the repo root (regression — #17 bug)" {
  # Regression guard: the original dogfood used $BATS_TEST_DIRNAME, which
  # inside a loaded helper is the calling .bats file's dir, not the
  # helper's. Tests appeared to pass but REPO_DIR silently held the wrong
  # value. Use ${BASH_SOURCE[0]} to self-locate test_helper.bash.
  # If this test breaks, the fix regressed — see test/test_helper.bash.
  [ -f "$REPO_DIR/mise.toml" ]
  [ -d "$REPO_DIR/.mise/tasks" ]
  [ -f "$REPO_DIR/.mise/tasks/test" ]
}

@test "mcr-scope: flags extension-less bash files under lib/ via shebang" {
  run codebase lint:mcr-scope "$FIXTURES/shebang-lib"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lib/helper"* ]]
}

@test "mcr-scope: does NOT scan */fixtures/* (lint-rule synthetic inputs)" {
  # Regression guard: lint-rule fixtures intentionally contain MCR refs as
  # negative cases. Scanning them would produce self-flagging meta-
  # recursion. The outer 'test/real-helper.bash' is clean; the nested
  # '*/fixtures/*' paths contain MCR and must be skipped.
  run codebase lint:mcr-scope "$FIXTURES/nested-fixtures"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" != *"FAIL"* ]]
}

@test "mcr-scope: does NOT scan .mise/tasks/* (task context is fine)" {
  # no-test-lib has MCR in a task script, which is legitimate.
  run codebase lint:mcr-scope "$FIXTURES/no-test-lib"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" != *"FAIL"* ]]
}

@test "mcr-scope: passes on a target with no test/ or lib/" {
  run codebase lint:mcr-scope "$FIXTURES/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no test/ or lib/ files found"* ]]
}

# ============================================================================
# Ignore directives
# ============================================================================

@test "mcr-scope: inline '# codebase:ignore' suppresses a single line" {
  run codebase lint:mcr-scope "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "mcr-scope: 'codebase:ignore mcr-scope' in mise.toml skips the whole target" {
  run codebase lint:mcr-scope "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

# ============================================================================
# Output details
# ============================================================================

@test "mcr-scope: fail output includes file:line citations" {
  run codebase lint:mcr-scope "$FIXTURES/dirty-lib"
  [ "$status" -ne 0 ]
  # Expect "lib/bad.sh:4:" (line 4 of bad.sh has the source directive)
  [[ "$output" == *"lib/bad.sh:"*":"* ]]
}

@test "mcr-scope: fail output includes the remediation hint" {
  run codebase lint:mcr-scope "$FIXTURES/dirty-test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BATS_TEST_DIRNAME"* ]]
  [[ "$output" == *"BASH_SOURCE"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "mcr-scope: fails when no targets given" {
  run codebase lint:mcr-scope
  [ "$status" -ne 0 ]
  # Same convention as lint:or-true and lint:shellcheck — the mise USAGE
  # parser emits the error before our script runs.
}

@test "mcr-scope: fails when target does not exist" {
  run codebase lint:mcr-scope "/nonexistent/path/xyz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# ============================================================================
# Multi-target
# ============================================================================

@test "mcr-scope: accepts multiple targets and reports each" {
  run codebase lint:mcr-scope "$FIXTURES/clean" "$FIXTURES/dirty-test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty-test"* ]]
}
