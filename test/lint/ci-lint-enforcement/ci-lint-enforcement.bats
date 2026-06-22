#!/usr/bin/env bats
# Tests for lint:ci-lint-enforcement rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

copy_fixture() {
  local name="$1"
  local dest="$BATS_TEST_TMPDIR/$name"
  cp -R "$FIXTURES/$name" "$dest"
  echo "$dest"
}

# ── direct enforcement ──────────────────────────────────────────────────────

@test "lint: passes when aggregate codebase lint is in workflow" {
  run codebase lint:ci-lint-enforcement "$FIXTURES/enforced-direct"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"enforced-direct"* ]]
  [[ "$output" == *"2 rule(s)"* ]]
}

# ── indirect enforcement via local task ─────────────────────────────────────

@test "lint: passes when aggregate lint runs through local task delegation" {
  run codebase lint:ci-lint-enforcement "$FIXTURES/enforced-indirect"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"enforced-indirect"* ]]
  [[ "$output" == *"3 rule(s)"* ]]
}

# ── missing enforcement ─────────────────────────────────────────────────────

@test "lint: fails when lint configured but not enforced in CI" {
  run codebase lint:ci-lint-enforcement "$FIXTURES/missing-enforcement"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"missing-enforcement"* ]]
  [[ "$output" == *"no aggregate enforcement in CI"* ]]
}

# ── hard-coded per-rule loop ────────────────────────────────────────────────

@test "lint: warns on hard-coded per-rule loops" {
  run codebase lint:ci-lint-enforcement "$FIXTURES/hardcoded-loop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"*"hardcoded-loop"* ]]
  [[ "$output" == *"per-rule invocation"* ]]
  [[ "$output" == *"3 per-rule invocation(s)"* ]]
}

# ── no lint config → skip ───────────────────────────────────────────────────

@test "lint: skips when no [_.codebase].lint is configured" {
  run codebase lint:ci-lint-enforcement "$FIXTURES/no-config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"no-config"* ]]
  [[ "$output" == *"no [_.codebase].lint configured"* ]]
}

# ── codebase:ignore ────────────────────────────────────────────────────────

@test "lint: skips when codebase:ignore ci-lint-enforcement is set" {
  run codebase lint:ci-lint-enforcement "$FIXTURES/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored"* ]]
}

# ── --fix mode ──────────────────────────────────────────────────────────────

@test "fix: adds aggregate lint step to workflow when missing" {
  target=$(copy_fixture missing-enforcement)

  run codebase lint:ci-lint-enforcement --fix "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIXED"*"missing-enforcement"* ]]

  workflow="$target/.github/workflows/test.yml"
  [ -f "$workflow" ]
  grep -q 'Run codebase lints' "$workflow"
  grep -q 'codebase lint "\$PWD"' "$workflow"
}

@test "fix: provisions codebase CLI tooling when missing" {
  target=$(copy_fixture missing-enforcement)

  run codebase lint:ci-lint-enforcement --fix "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"provisioned"* ]]

  grep -q 'shiv = "https://github.com/KnickKnackLabs/vfox-shiv"' "$target/mise.toml"
  grep -q '"shiv:codebase"' "$target/mise.toml"
}

@test "fix: does not duplicate existing provisioning" {
  target=$(copy_fixture enforced-direct)

  run codebase lint:ci-lint-enforcement --fix "$target"
  [ "$status" -eq 0 ]

  # Should not change the workflow since it already has enforcement
  grep -q 'Run codebase lints' "$target/.github/workflows/test.yml"
  [ "$(grep -c 'Run codebase lints' "$target/.github/workflows/test.yml")" -eq 1 ]
}

@test "fix: warns about remaining per-rule loops" {
  target=$(copy_fixture loop-only)

  run codebase lint:ci-lint-enforcement --fix "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIXED"*"loop-only"* ]]
  [[ "$output" == *"WARN"*"loop-only"* ]]
  [[ "$output" == *"3 per-rule loop(s) remain"* ]]

  # Should still have added aggregate step
  grep -q 'Run codebase lints' "$target/.github/workflows/test.yml"
}

# ── edge cases ──────────────────────────────────────────────────────────────

@test "lint: fails when lint configured but no workflows exist" {
  run codebase lint:ci-lint-enforcement "$FIXTURES/no-workflows"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"no-workflows"* ]]
  [[ "$output" == *"no CI workflows found"* ]]
}

@test "lint: passes multiple targets — mixed pass and fail" {
  run codebase lint:ci-lint-enforcement \
    "$FIXTURES/enforced-direct" \
    "$FIXTURES/missing-enforcement"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"enforced-direct"* ]]
  [[ "$output" == *"FAIL"*"missing-enforcement"* ]]
}

@test "lint: fails when target does not exist" {
  run codebase lint:ci-lint-enforcement "$FIXTURES/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}