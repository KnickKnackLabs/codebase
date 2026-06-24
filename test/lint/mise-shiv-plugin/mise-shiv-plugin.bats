#!/usr/bin/env bats
# Tests for mise-shiv-plugin lint rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# Detection

@test "lint: passes when shiv plugin and experimental are present" {
  run codebase lint:mise-shiv-plugin "$FIXTURES/complete"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "lint: fails when shiv plugin entry is missing" {
  run codebase lint:mise-shiv-plugin "$FIXTURES/missing-plugin"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"vfox-shiv"* ]]
  # Should NOT complain about experimental (which is present)
  [[ "$output" != *"experimental"* ]]
}

@test "lint: fails when experimental setting is missing" {
  run codebase lint:mise-shiv-plugin "$FIXTURES/missing-experimental"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"experimental"* ]]
}

@test "lint: fails when both prerequisites are missing" {
  run codebase lint:mise-shiv-plugin "$FIXTURES/missing-both"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"vfox-shiv"* ]]
  [[ "$output" == *"experimental"* ]]
}

@test "lint: passes when no shiv tools are declared" {
  run codebase lint:mise-shiv-plugin "$FIXTURES/no-shiv-tools"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"no shiv tools"* ]]
}

@test "lint: passes when no mise.toml exists" {
  run codebase lint:mise-shiv-plugin "$FIXTURES/no-toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO"* ]]
  [[ "$output" == *"no mise.toml"* ]]
}

@test "lint: skips when codebase:ignore mise-shiv-plugin is set" {
  run codebase lint:mise-shiv-plugin "$FIXTURES/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

@test "lint: checks multiple targets" {
  run codebase lint:mise-shiv-plugin "$FIXTURES/complete" "$FIXTURES/missing-both"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"complete"* ]]
  [[ "$output" == *"FAIL"*"missing-both"* ]]
}

# Error handling

@test "lint: fails when target does not exist" {
  run codebase lint:mise-shiv-plugin /nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "lint: fails when no targets provided" {
  run codebase lint:mise-shiv-plugin
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "lint: supports multiple targets with mixed results" {
  run codebase lint:mise-shiv-plugin \
    "$FIXTURES/complete" \
    "$FIXTURES/missing-plugin" \
    "$FIXTURES/no-shiv-tools" \
    "$FIXTURES/no-toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"complete"* ]]
  [[ "$output" == *"FAIL"*"missing-plugin"* ]]
  [[ "$output" == *"OK"*"no shiv tools"* ]]
  [[ "$output" == *"INFO"*"no mise.toml"* ]]
}
