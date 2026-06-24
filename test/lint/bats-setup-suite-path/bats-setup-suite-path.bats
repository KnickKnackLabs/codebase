#!/usr/bin/env bats
# Tests for bats-setup-suite-path lint rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# Detection

@test "lint: passes when no test/setup_suite.bash exists" {
  run codebase lint:bats-setup-suite-path "$FIXTURES/no-setup-suite"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"no test/setup_suite.bash"* ]]
}

@test "lint: passes when BATS_LIBEXEC is preserved correctly" {
  run codebase lint:bats-setup-suite-path "$FIXTURES/preserved"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"preserves BATS_LIBEXEC correctly"* ]]
}

@test "lint: fails when mise env is called without BATS_LIBEXEC preservation" {
  run codebase lint:bats-setup-suite-path "$FIXTURES/missing-preserve"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"mise env without BATS_LIBEXEC preservation"* ]]
  # Should mention the fix
  [[ "$output" == *"bats_libexec"* ]]
  [[ "$output" == *"BATS_LIBEXEC:-"* ]]
}

@test "lint: passes when setup_suite.bash doesn't call mise env" {
  run codebase lint:bats-setup-suite-path "$FIXTURES/no-mise-env"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"doesn't call mise env"* ]]
}

@test "lint: skips when inline codebase:ignore is present" {
  run codebase lint:bats-setup-suite-path "$FIXTURES/ignored-inline"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

@test "lint: skips when repo-level codebase:ignore is present in mise.toml" {
  run codebase lint:bats-setup-suite-path "$FIXTURES/ignored-repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

@test "lint: passes when no test/ directory exists" {
  run codebase lint:bats-setup-suite-path "$FIXTURES/no-test-dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"no test/setup_suite.bash"* ]]
}

@test "lint: handles multiple targets with mixed results" {
  run codebase lint:bats-setup-suite-path \
    "$FIXTURES/preserved" \
    "$FIXTURES/missing-preserve" \
    "$FIXTURES/no-mise-env"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"preserved"* ]]
  [[ "$output" == *"FAIL"*"missing-preserve"* ]]
  [[ "$output" == *"OK"*"no-mise-env"* ]]
}

# Error handling

@test "lint: fails when target does not exist" {
  run codebase lint:bats-setup-suite-path /nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "lint: fails when no targets provided" {
  run codebase lint:bats-setup-suite-path
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}
