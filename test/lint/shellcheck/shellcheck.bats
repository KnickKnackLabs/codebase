#!/usr/bin/env bats
# Tests for lint:shellcheck rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# ============================================================================
# Detection
# ============================================================================

@test "lint: passes on a clean codebase" {
  run codebase lint:shellcheck "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "lint: fails on a codebase with shellcheck violations" {
  run codebase lint:shellcheck "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *"violation"* ]]
}

@test "lint: fail output includes the violating file path" {
  run codebase lint:shellcheck "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken"* ]]
}

@test "lint: fail output includes shellcheck error codes" {
  run codebase lint:shellcheck "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  # The broken fixture hits SC2086 (double-quote) and/or SC2045 (iterating ls)
  [[ "$output" == *"SC"* ]]
}

# ============================================================================
# Ignore directive
# ============================================================================

@test "lint: skips when codebase:ignore shellcheck is set in mise.toml" {
  run codebase lint:shellcheck "$FIXTURES/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored"* ]]
}

# ============================================================================
# Default excludes (SC1091, SC2034, SC2154)
#
# The fixture excludes-applied/ triggers all three codes in DEFAULT_EXCLUDES.
# These tests prove the defaults actually suppress them — without this
# coverage, the exclude list could silently regress.
# ============================================================================

@test "lint: default excludes suppress SC1091/SC2034/SC2154" {
  run codebase lint:shellcheck "$FIXTURES/excludes-applied"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"excludes-applied"* ]]
  [[ "$output" != *"SC1091"* ]]
  [[ "$output" != *"SC2034"* ]]
  [[ "$output" != *"SC2154"* ]]
}

@test "lint: confirms the excludes-applied fixture actually triggers the codes" {
  # Meta-test: without our defaults, shellcheck flags the fixture.
  # If this starts failing, the fixture stopped triggering SC1091/2034/2154
  # and the test above becomes vacuously true.
  local sc
  sc=$(mise which shellcheck)
  run "$sc" --shell=bash "$FIXTURES/excludes-applied/.mise/tasks/with-source"
  [[ "$output" == *"SC1091"* ]]
  [[ "$output" == *"SC2034"* ]]
  [[ "$output" == *"SC2154"* ]]
}

# ============================================================================
# Scope
# ============================================================================

@test "lint: works on a codebase with no mise.toml" {
  run codebase lint:shellcheck "$FIXTURES/no-toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-toml"* ]]
}

@test "lint: passes on a codebase with no shell files" {
  run codebase lint:shellcheck "$FIXTURES/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"empty"* ]]
  [[ "$output" == *"no shell files"* ]]
}

@test "lint: checks both .mise/tasks and lib/ directories" {
  run codebase lint:shellcheck "$FIXTURES/mixed"
  [ "$status" -ne 0 ]
  # Violation is in lib/bad.sh, not in the task — proves lib/ is scanned
  [[ "$output" == *"bad.sh"* ]]
}

# ============================================================================
# Multi-target
# ============================================================================

@test "lint: checks multiple targets and reports each" {
  run codebase lint:shellcheck "$FIXTURES/clean" "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"dirty"* ]]
}

@test "lint: exit code is the number of failing targets" {
  run codebase lint:shellcheck "$FIXTURES/dirty" "$FIXTURES/mixed"
  [ "$status" -eq 2 ]
}

# ============================================================================
# Error paths
# ============================================================================

@test "lint: fails when target does not exist" {
  run codebase lint:shellcheck "$FIXTURES/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "lint: fails when no targets given" {
  run codebase lint:shellcheck
  [ "$status" -ne 0 ]
  # mise's USAGE parser rejects the missing required <targets> arg
  # before the task's own check fires. Asserting on both the 'Missing
  # required arg' literal and the arg name so the test breaks loudly if
  # either changes — we *want* to notice a mise upgrade that reformats
  # this error.
  [[ "$output" == *"Missing required arg"* ]]
  [[ "$output" == *"<targets>"* ]]
}
