#!/usr/bin/env bats
# Tests for lint:bats-raw-mise-dispatch rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Pass paths
# ============================================================================

@test "bats-raw-mise-dispatch: passes on clean wrapper-based tests" {
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "bats-raw-mise-dispatch: passes when target has no test/ dir" {
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"empty"* ]]
  [[ "$output" == *"no test/ files found"* ]]
}

# ============================================================================
# Invocation signatures — each form fails
# ============================================================================

@test "bats-raw-mise-dispatch: flags 'mise run -q <task>' in BATS test" {
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *"mise run"* ]]
}

@test "bats-raw-mise-dispatch: 'bash -c ... mise run ...' is a known limitation (inside quoted string)" {
  # KNOWN LIMITATION: 'bash -c "... mise run ..."' wraps the dispatch inside
  # a single-quoted string, making it indistinguishable from grep/search
  # patterns at the line-scanning level. The rule does NOT flag this form.
  # If this becomes important, a smarter parser (statement-context-aware)
  # would be needed.
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/dirty-bash-c"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ============================================================================
# Allowlisted files
# ============================================================================

@test "bats-raw-mise-dispatch: does NOT flag 'mise run' in test_helper.bash" {
  # The clean fixture has mise run in test_helper.bash (the wrapper
  # definition) — this should be allowed.
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/clean"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Ignore directives
# ============================================================================

@test "bats-raw-mise-dispatch: inline '# codebase:ignore' suppresses a single line" {
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "bats-raw-mise-dispatch: 'codebase:ignore' in mise.toml skips the target" {
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/ignored-repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-repo"* ]]
}

# ============================================================================
# Output details
# ============================================================================

@test "bats-raw-mise-dispatch: fail output includes file:line citations" {
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test/bad.bats:"*":"* ]]
}

@test "bats-raw-mise-dispatch: fail output includes the remediation hint" {
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats-tool-testing.md"* ]]
  [[ "$output" == *"Call the Tool"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "bats-raw-mise-dispatch: fails when no targets given" {
  run codebase lint:bats-raw-mise-dispatch
  [ "$status" -ne 0 ]
}

@test "bats-raw-mise-dispatch: fails when target does not exist" {
  run codebase lint:bats-raw-mise-dispatch "/nonexistent/path/xyz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# ============================================================================
# Multi-target
# ============================================================================

@test "bats-raw-mise-dispatch: accepts multiple targets and reports each" {
  run codebase lint:bats-raw-mise-dispatch "$FIXTURES/clean" "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty"* ]]
}