#!/usr/bin/env bats
# Public-path contract for direct aggregate lint enforcement in GitHub Actions.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  WORKFLOW="$REPO/.github/workflows/test.yml"
  mkdir -p "$(dirname "$WORKFLOW")"
  write_config
}

write_config() {
  cat > "$REPO/mise.toml" <<'TOML'
[_.codebase]
name = "fixture"
lint = ["mise-settings", "shellcheck"]
TOML
}

write_workflow() {
  cat > "$WORKFLOW"
}

@test "accepts a direct aggregate command in a normal workflow step" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: if true; then codebase lint "$PWD"; fi
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    fixture (2 configured rule(s), directly enforced in 1 workflow(s))"* ]]
}

@test "accepts mise exec aggregate syntax in a folded run value" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: >-
          mise exec --
          codebase lint .
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 0 ]
}

@test "decodes quoted YAML run scalars" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: 'mise exec -- codebase lint .'
      - run: "codebase lint \"$PWD\""
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 0 ]
}

@test "treats GitHub expressions as opaque pre-shell values" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ github.ref }}"
      - run: codebase lint "${{ github.workspace }}"
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 0 ]
}

@test "does not accept a command spelled inside a GitHub expression" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: ${{ 'codebase lint .' }}
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 1 ]
}

@test "skips repositories without a configured lint portfolio" {
  cat > "$REPO/mise.toml" <<'TOML'
[_.codebase]
name = "fixture"
TOML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  fixture (no configured codebase lint portfolio)"* ]]
}

@test "fails when a configured repository has no normal workflow" {
  rm -rf "$REPO/.github"

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"configured codebase lints are not directly enforced"* ]]
}

@test "does not trace local tasks or accept per-rule loops" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: mise run test
      - run: |
          for rule in mise-settings shellcheck; do
            codebase "lint:$rule" .
          done
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 1 ]
}

@test "ignores comments quoted examples lookalikes and action inputs" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: |
          # codebase lint .
          printf '%s\n' 'codebase lint .'
          my-codebase lint .
      - uses: example/action@v1
        with:
          run: codebase lint .
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 1 ]
}

@test "requires run steps beneath jobs rather than unrelated YAML sequences" {
  write_workflow <<'YAML'
name: Test
examples:
  steps:
    - run: codebase lint .
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo test
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 1 ]
}

@test "fails closed on malformed workflow YAML" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    steps:
      - run: [broken
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"workflow is not parseable YAML"* ]]
  [[ "$output" != *"OK    fixture"* ]]
}

@test "fails closed on malformed Bash in a run value" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: if then
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"workflow run value is not parseable Bash"* ]]
  [[ "$output" != *"OK    fixture"* ]]
}

@test "validates every workflow before accepting an aggregate command" {
  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: codebase lint .
YAML
  cat > "$REPO/.github/workflows/broken.yml" <<'YAML'
name: Broken
jobs:
  test:
    steps:
      - run: if then
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"workflow run value is not parseable Bash"* ]]
  [[ "$output" != *"OK    fixture"* ]]
}

@test "checks only workflow files directly beneath the workflows directory" {
  mkdir -p "$REPO/.github/workflows/nested"
  cat > "$REPO/.github/workflows/nested/test.yml" <<'YAML'
name: Nested
jobs:
  lint:
    steps:
      - run: codebase lint .
YAML

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 1 ]
}

@test "preserves quoted targets and returns the failing-target count" {
  local other="$BATS_TEST_TMPDIR/other repo"
  mkdir -p "$other/.github/workflows"
  cp "$REPO/mise.toml" "$other/mise.toml"

  write_workflow <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: codebase lint .
YAML
  cat > "$other/.github/workflows/test.yaml" <<'YAML'
name: Test
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: mise run test
YAML

  run codebase lint:ci-lint-enforcement "$REPO" "$other"

  [ "$status" -eq 1 ]
  [[ "$output" == *"OK    fixture"* ]]
  [[ "$output" == *"FAIL  fixture"* ]]
}

@test "missing and nonexistent targets fail clearly" {
  run codebase lint:ci-lint-enforcement
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]

  run codebase lint:ci-lint-enforcement "$REPO/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}
