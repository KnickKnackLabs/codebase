#!/usr/bin/env bats
# Tests for lint:github-actions rule

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

@test "lint: passes on a codebase with valid workflows" {
  run codebase lint:github-actions "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "lint: fails when no GitHub Actions workflows exist" {
  run codebase lint:github-actions "$FIXTURES/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"missing"* ]]
  [[ "$output" == *"no GitHub Actions workflows found"* ]]
}

@test "lint: skips when codebase:ignore github-actions is set in mise.toml" {
  run codebase lint:github-actions "$FIXTURES/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored"* ]]
}

@test "lint: fails on invalid workflow syntax" {
  run codebase lint:github-actions "$FIXTURES/invalid"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"invalid"* ]]
  [[ "$output" == *"GitHub Actions violation"* ]]
}

@test "fix: creates KKL workflow with test task when workflows are missing" {
  target=$(copy_fixture fix-test)

  run codebase lint:github-actions --fix "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FIX"*"fix-test"* ]]
  [[ "$output" == *"OK"*"fix-test"* ]]

  workflow="$target/.github/workflows/test.yml"
  [ -f "$workflow" ]
  grep -q 'actions/checkout@v6' "$workflow"
  grep -q 'jdx/mise-action@v4' "$workflow"
  grep -q 'run: mise run test' "$workflow"
}

@test "fix: includes aggregate codebase lint step" {
  target=$(copy_fixture fix-lints)

  run codebase lint:github-actions --fix "$target"
  [ "$status" -eq 0 ]

  workflow="$target/.github/workflows/test.yml"
  [ -f "$workflow" ]
  grep -q 'Run codebase lints' "$workflow"
  grep -q 'run: codebase lint "$PWD"' "$workflow"
  ! grep -q 'lint:mise-settings' "$workflow"
  ! grep -q 'lint:shellcheck' "$workflow"
}

@test "fix: provisions codebase CLI when configured lint rules are generated" {
  target=$(copy_fixture fix-lints)

  run codebase lint:github-actions --fix "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added"*"shiv plugin"* ]]
  [[ "$output" == *"added"*"shiv:codebase tool"* ]]

  grep -q '^\[plugins\]' "$target/mise.toml"
  grep -q '^shiv = "https://github.com/KnickKnackLabs/vfox-shiv"' "$target/mise.toml"
  grep -q '^\[tools\]' "$target/mise.toml"
  grep -q '^"shiv:codebase" = "latest"' "$target/mise.toml"
}

@test "fix: does not duplicate existing codebase CLI provisioning" {
  target=$(copy_fixture fix-lints-provisioned)

  run codebase lint:github-actions --fix "$target"
  [ "$status" -eq 0 ]

  [ "$(grep -c '^shiv = "https://github.com/KnickKnackLabs/vfox-shiv"' "$target/mise.toml")" -eq 1 ]
  [ "$(grep -c '^"shiv:codebase" = "latest"' "$target/mise.toml")" -eq 1 ]
}

@test "fix: updates existing old codebase pin for aggregate workflow" {
  target=$(copy_fixture fix-lints-provisioned)
  tmp="$target/mise.toml.tmp"
  awk '{ gsub(/"latest"/, "\"0.2.0\""); print }' "$target/mise.toml" > "$tmp"
  mv "$tmp" "$target/mise.toml"

  run codebase lint:github-actions --fix "$target"
  [ "$status" -eq 0 ]

  grep -q '^"shiv:codebase" = "latest"' "$target/mise.toml"
  grep -q 'run: codebase lint "$PWD"' "$target/.github/workflows/test.yml"
}

@test "fix: fails when no safe checks can be inferred" {
  target=$(copy_fixture fix-empty)

  run codebase lint:github-actions --fix "$target"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no checks inferred"* ]]
  [ ! -f "$target/.github/workflows/test.yml" ]
}

@test "lint: checks multiple targets and reports each" {
  run codebase lint:github-actions "$FIXTURES/clean" "$FIXTURES/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
  [[ "$output" == *"FAIL"*"missing"* ]]
}

@test "lint: exit code is the number of failing targets" {
  run codebase lint:github-actions "$FIXTURES/missing" "$FIXTURES/invalid"
  [ "$status" -eq 2 ]
}

@test "lint: fails when target does not exist" {
  run codebase lint:github-actions "$FIXTURES/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}
