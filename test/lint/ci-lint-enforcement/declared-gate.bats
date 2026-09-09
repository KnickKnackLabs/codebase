#!/usr/bin/env bats
# The opt-in gate trusts repository ownership, not inferred task contents.
# shellcheck disable=SC2016 # Fixtures intentionally contain unevaluated shell/GitHub syntax.
load ../../test_helper
load test_helper
bats_require_minimum_version 1.5.0

write_gate() {
  write_config
  printf 'ci_lint_gate = %s\n' "$1" >> "$REPO/mise.toml"
}

write_gate_workflow() {
  cat > "$WORKFLOW" <<'YAML'
name: Test
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - run: |
YAML
  printf '%s\n' "$1" | awk '{ print "          " $0 }' >> "$WORKFLOW"
}

@test "a validate task name without an explicit declaration does not qualify" {
  write_gate_workflow 'mise run validate --verbose'
  run codebase lint:ci-lint-enforcement "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"_.codebase.ci_lint_gate"* ]]
}

@test "trusts the exact declared gate without executing or resolving its task" {
  write_gate '"mise run validate --verbose"'
  write_gate_workflow 'mise run validate --verbose'
  [ ! -e "$REPO/.mise/tasks/validate" ]

  run codebase lint:ci-lint-enforcement "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"direct or declared gate in 1 workflow(s)"* ]]
  [[ "$output" == *"trusted gate: mise run validate --verbose (task internals not inspected)"* ]]
}

@test "decodes folded YAML and permits whitespace only around the whole declared command" {
  write_gate '"mise run validate --verbose"'
  write_workflow <<'YAML'
name: Test
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - run: >-
          mise run validate
          --verbose
      - run: "  mise run validate --verbose  "
YAML
  run codebase lint:ci-lint-enforcement "$REPO"
  [ "$status" -eq 0 ]
}

@test "does not accept changed arguments quoting wrappers examples or interpolated gates" {
  write_gate '"mise run validate --verbose"'
  local command
  for command in \
    'mise run validate' \
    'mise run validate --verbose --skip-lint' \
    "mise run 'validate' --verbose" \
    'mise run  validate --verbose' \
    'mise run validate --verbose || true' \
    'mise run validate --verbose; echo done' \
    'if true; then mise run validate --verbose; fi' \
    'check() { mise run validate --verbose; }; check' \
    '# mise run validate --verbose' \
    'echo "mise run validate --verbose"' \
    'mise run validate --verbose # same spelling is not the whole command' \
    '${{ '\''mise run validate --verbose'\'' }}'; do
    write_gate_workflow "$command"
    run codebase lint:ci-lint-enforcement "$REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *"or use the exact declared CI gate: mise run validate --verbose"* ]]
  done
}

@test "declared gates cannot opt out of step job or shell failure propagation checks" {
  write_gate '"mise run validate --verbose"'
  write_workflow <<'YAML'
name: Test
jobs:
  allowed-job:
    continue-on-error: true
    runs-on: ubuntu-latest
    steps:
      - run: mise run validate --verbose
  allowed-steps:
    runs-on: ubuntu-latest
    steps:
      - continue-on-error: true
        run: mise run validate --verbose
      - continue-on-error: ${{ false }}
        run: mise run validate --verbose
      - shell: python
        run: mise run validate --verbose
      - shell: bash -c "exit 0" {0}
        run: mise run validate --verbose
  inherited-shell:
    defaults:
      run:
        shell: python
    runs-on: ubuntu-latest
    steps:
      - run: mise run validate --verbose
YAML
  run codebase lint:ci-lint-enforcement "$REPO"
  [ "$status" -eq 1 ]
}

@test "a valid gate declaration retains the direct lint alternative" {
  write_gate '"mise run validate --verbose"'
  write_gate_workflow 'codebase lint "$PWD"'
  run codebase lint:ci-lint-enforcement "$REPO"
  [ "$status" -eq 0 ]
}

@test "invalid gate declarations fail closed even beside a direct lint step" {
  write_gate_workflow 'codebase lint .'
  local declaration
  for declaration in \
    'false' \
    '17' \
    '["mise", "run", "validate"]' \
    '{ command = "mise run validate" }' \
    '""' \
    '"mise run validate || true"' \
    '"$(echo mise) run validate"' \
    '"FOO=bar mise run validate"' \
    '"mise run validate > result"' \
    '"mise run validate\n"' \
    '"mise run validate\t"' \
    '" mise run validate"' \
    '"mise run validate "' \
    '"mise run  validate"' \
    '"mise run validate *"' \
    '"mise run validate $TASK"' \
    '"mise run validate ${{ github.ref }}"'; do
    write_gate "$declaration"
    run codebase lint:ci-lint-enforcement "$REPO"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ci_lint_gate must be one nonempty literal command"* ]]
    [[ "$output" != *"OK    fixture"* ]]
  done
}

@test "malformed configuration cannot disappear into the no-portfolio skip" {
  write_gate_workflow 'codebase lint .'
  printf 'ci_lint_gate = [broken\n' >> "$REPO/mise.toml"
  run codebase lint:ci-lint-enforcement "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read CI lint policy"* ]]
  [[ "$output" != *"SKIP"* ]]
}

@test "a declared gate does not bypass validation of other workflow run values" {
  write_gate '"mise run validate --verbose"'
  write_gate_workflow 'mise run validate --verbose'
  cp "$WORKFLOW" "$REPO/.github/workflows/accepted.yml"
  write_gate_workflow 'if then'
  run codebase lint:ci-lint-enforcement "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"workflow run value is not parseable Bash"* ]]
  [[ "$output" != *"OK    fixture"* ]]
}

@test "gate declarations stay scoped to each target repository" {
  local other="$BATS_TEST_TMPDIR/other repo"
  mkdir -p "$other/.github/workflows"
  cp "$REPO/mise.toml" "$other/mise.toml"
  write_gate '"mise run validate --verbose"'
  write_gate_workflow 'mise run validate --verbose'
  cp "$WORKFLOW" "$other/.github/workflows/test.yml"

  run codebase lint:ci-lint-enforcement "$REPO" "$other"
  [ "$status" -eq 1 ]
  [[ "$output" == *"OK    fixture"* ]]
  [[ "$output" == *"FAIL  fixture"* ]]
}

@test "public help exposes the explicit trust setting" {
  run codebase lint:ci-lint-enforcement --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"_.codebase.ci_lint_gate"* ]]
  [[ "$output" == *"docs/ci-lint-enforcement.md"* ]]
}
