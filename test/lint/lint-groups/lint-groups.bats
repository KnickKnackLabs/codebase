#!/usr/bin/env bats
# Tests for lint group expansion (lib/lint-groups.sh) and aggregate dispatch

load ../../test_helper

# Library-level tests (source lint-groups.sh directly)

@test "lint-groups: codebase_available_groups lists @maintained-tool" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_available_groups
  [ "$status" -eq 0 ]
  [[ "$output" == *"@maintained-tool"* ]]
}

@test "lint-groups: codebase_group_members returns 9 rules for @maintained-tool" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_group_members "@maintained-tool"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 9 ]
  [[ "$output" == *"mise-settings"* ]]
  [[ "$output" == *"gum-table"* ]]
  [[ "$output" == *"bats-test-helper"* ]]
  [[ "$output" == *"bats-test-task"* ]]
  [[ "$output" == *"mcr-scope"* ]]
  [[ "$output" == *"or-true"* ]]
  [[ "$output" == *"shellcheck"* ]]
  [[ "$output" == *"caller-pwd-contract"* ]]
  [[ "$output" == *"github-actions"* ]]
}

@test "lint-groups: codebase_group_members fails on unknown group" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_group_members "@nonexistent"
  [ "$status" -ne 0 ]
}

@test "lint-groups: codebase_has_group_reference detects @ prefix" {
  source "$REPO_DIR/lib/lint-groups.sh"
  codebase_has_group_reference "@maintained-tool" "or-true"
  [ "$?" -eq 0 ]
}

@test "lint-groups: codebase_has_group_reference returns 1 when no @ present" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_has_group_reference "mise-settings" "or-true"
  [ "$status" -ne 0 ]
}

@test "lint-groups: codebase_expand_lint_groups expands @maintained-tool to 9 rules" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_expand_lint_groups "@maintained-tool"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 9 ]
}

@test "lint-groups: codebase_expand_lint_groups passes through individual rules" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_expand_lint_groups "or-true" "shellcheck"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"or-true"* ]]
  [[ "$output" == *"shellcheck"* ]]
}

@test "lint-groups: codebase_expand_lint_groups mixes group + individual rules" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_expand_lint_groups "@maintained-tool" "or-true"
  [ "$status" -eq 0 ]
  # 9 from group + 1 individual = 10 (or-true appears twice, preserved)
  [ "${#lines[@]}" -eq 10 ]
}

@test "lint-groups: codebase_expand_lint_groups errors on unknown group" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_expand_lint_groups "@nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"unknown lint group"* ]]
}

@test "lint-groups: codebase_expand_lint_groups errors on unknown group mixed with valid" {
  source "$REPO_DIR/lib/lint-groups.sh"
  run codebase_expand_lint_groups "mise-settings" "@nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"unknown lint group"* ]]
}

# Aggregate dispatch — group expansion in codebase lint

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  REPO_ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"
}

write_config() {
  cat > "$REPO/mise.toml"
}

@test "lint: expands @maintained-tool group and shows preamble" {
  # Create a repo with all the dirs/files that @maintained-tool rules need to pass
  mkdir -p "$REPO/.mise/tasks"
  mkdir -p "$REPO/.github/workflows"
  cat > "$REPO/.github/workflows/test.yml" <<'EOF'
name: Test
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@maintained-tool"]
EOF

  run codebase lint "$REPO"
  echo "STATUS=$status"
  echo "OUTPUT=$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: expanded 9 rule(s) from lint groups"* ]]
  # Verify all 9 rules appear in the output
  [[ "$output" == *"codebase: lint:mise-settings"* ]]
  [[ "$output" == *"codebase: lint:gum-table"* ]]
  [[ "$output" == *"codebase: lint:bats-test-helper"* ]]
  [[ "$output" == *"codebase: lint:bats-test-task"* ]]
  [[ "$output" == *"codebase: lint:mcr-scope"* ]]
  [[ "$output" == *"codebase: lint:or-true"* ]]
  [[ "$output" == *"codebase: lint:shellcheck"* ]]
  [[ "$output" == *"codebase: lint:caller-pwd-contract"* ]]
  [[ "$output" == *"codebase: lint:github-actions"* ]]
}

@test "lint: expands @maintained-tool group with pass-through for extra rules" {
  mkdir -p "$REPO/.mise/tasks"
  mkdir -p "$REPO/.github/workflows"
  cat > "$REPO/.github/workflows/test.yml" <<'EOF'
name: Test
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@maintained-tool"]
EOF

  run codebase lint "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"9 rule(s)"* ]]
  [[ "$output" == *"codebase: all 9 lint rule(s) passed"* ]]
}

@test "lint: lint_exclude removes a rule from expanded group" {
  mkdir -p "$REPO/.mise/tasks"
  mkdir -p "$REPO/.github/workflows"
  cat > "$REPO/.github/workflows/test.yml" <<'EOF'
name: Test
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@maintained-tool"]
lint_exclude = ["caller-pwd-contract"]
EOF

  run codebase lint "$REPO"
  echo "STATUS=$status"
  echo "OUTPUT=$output"
  [ "$status" -eq 0 ]
  # 8 remaining rules
  [[ "$output" == *"expanded 8 rule(s)"* ]]
  [[ "$output" == *"codebase: all 8 lint rule(s) passed"* ]]
  # caller-pwd-contract should NOT appear
  [[ "$output" != *"lint:caller-pwd-contract"* ]]
}

@test "lint: group + individual rules both shown in preamble count" {
  mkdir -p "$REPO/.mise/tasks"
  mkdir -p "$REPO/.github/workflows"
  cat > "$REPO/.github/workflows/test.yml" <<'EOF'
name: Test
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@maintained-tool"]
EOF

  run codebase lint "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"expanded 9 rule(s)"* ]]
}

@test "lint: no-group pass-through still works (backward compat)" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings"]
EOF

  run codebase lint "$REPO"
  [ "$status" -eq 0 ]
  # Should NOT show the groups preamble
  [[ "$output" != *"expanded"* ]]
  [[ "$output" == *"codebase: lint:mise-settings"* ]]
  [[ "$output" == *"codebase: all 1 lint rule(s) passed"* ]]
}

@test "lint: lint:groups task lists available groups" {
  run codebase lint:groups
  [ "$status" -eq 0 ]
  [[ "$output" == *"@maintained-tool"* ]]
  [[ "$output" == *"Usage in mise.toml"* ]]
}

@test "lint: lint:groups --all shows expanded rules" {
  run codebase lint:groups --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"@maintained-tool"* ]]
  [[ "$output" == *"- mise-settings"* ]]
  [[ "$output" == *"- github-actions"* ]]
}