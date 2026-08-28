#!/usr/bin/env bats
# Evolving lint-group policy and aggregate integration.

load ../../test_helper

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  REPO_ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"
}

write_config() {
  cat > "$REPO/mise.toml"
}

load_groups() {
  # shellcheck source=../../../lib/lint-groups.sh
  source "$REPO_DIR/lib/lint-groups.sh"
}

assert_group_members() {
  local group="$1"
  local expected
  expected=$(cat)

  run codebase_lint_group_members "$group"

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "lint groups: exposes the six groups in stable order" {
  load_groups

  run codebase_available_lint_groups

  [ "$status" -eq 0 ]
  [ "$output" = $'@shell\n@mise\n@bats\n@ci\n@shiv\n@all' ]
}

@test "lint groups: owns the exact current substrate membership" {
  load_groups

  assert_group_members @shell <<'EOF'
shellcheck
or-true
bash-empty-argv-forwarding
bash-empty-array-expansions
exec-stderr-persistence
process-substitution-status
remote-url-output
gum-table
EOF
  assert_group_members @mise <<'EOF'
mise-settings
mise-usage-examples
variadic-args
mcr-scope
EOF
  assert_group_members @bats <<'EOF'
bats-test-helper
bats-test-task
bats-public-task-path
EOF
  assert_group_members @ci <<'EOF'
github-actions
ci-lint-enforcement
EOF
  assert_group_members @shiv <<'EOF'
caller-pwd-contract
mise-shiv-plugin
EOF
}

@test "lint groups: @all composes the substrate groups in stable order" {
  local expected
  local group
  load_groups

  expected=$(
    while IFS= read -r group; do
      codebase_lint_group_members "$group"
    done <<< "$(codebase_substrate_lint_groups)"
  )

  run codebase_lint_group_members @all

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "lint groups: every member resolves to a concrete executable lint task" {
  load_groups

  while IFS= read -r rule; do
    [ -x "$REPO_DIR/.mise/tasks/lint/$rule" ]
  done <<< "$(codebase_lint_group_members @all)"
}

@test "lint groups: mixed entries preserve first occurrence and stable order" {
  load_groups

  run codebase_expand_lint_entries mise-settings @mise shellcheck @shell mise-settings

  [ "$status" -eq 0 ]
  [ "$output" = $'mise-settings\nmise-usage-examples\nvariadic-args\nmcr-scope\nshellcheck\nor-true\nbash-empty-argv-forwarding\nbash-empty-array-expansions\nexec-stderr-persistence\nprocess-substitution-status\nremote-url-output\ngum-table' ]
}

@test "lint groups: unknown groups fail closed with discovery guidance" {
  load_groups

  run codebase_expand_lint_entries mise-settings @unknown

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown lint group: @unknown"* ]]
  [[ "$output" == *"Known groups: @shell @mise @bats @ci @shiv @all"* ]]
}

@test "lint groups: public discovery shows membership and evolution contract" {
  run codebase lint:groups

  [ "$status" -eq 0 ]
  [[ "$output" == *$'@shell\n  shellcheck'* ]]
  [[ "$output" == *$'@all\n  shellcheck'* ]]
  [[ "$output" == *"Repositories opt into"* ]]
  [[ "$output" == *"lint_exclude"* ]]
}

@test "lint groups: aggregate expands a group and applies concrete exclusions" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@mise"]
lint_exclude = ["mise-usage-examples", "variadic-args", "mcr-scope"]
EOF

  run codebase lint "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:mise-settings $REPO_ROOT"* ]]
  [[ "$output" == *"codebase: all 1 lint rule(s) passed"* ]]
  [[ "$output" != *"lint:mise-usage-examples"* ]]
  [[ "$output" != *"lint:variadic-args"* ]]
  [[ "$output" != *"lint:mcr-scope"* ]]
}

@test "lint groups: aggregate deduplicates mixed concrete and group entries" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings", "@mise", "mise-settings"]
lint_exclude = ["mise-usage-examples", "variadic-args", "mcr-scope"]
EOF

  run codebase lint "$REPO"

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^codebase: lint:mise-settings ')" -eq 1 ]
  [[ "$output" == *"codebase: all 1 lint rule(s) passed"* ]]
}

@test "lint groups: unknown groups stop aggregate execution before any lint" {
  write_config <<'EOF'
[settings]
quiet = true

[_.codebase]
lint = ["mise-settings", "@unknown"]
EOF

  run codebase lint "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown lint group: @unknown"* ]]
  [[ "$output" != *"codebase: lint:mise-settings"* ]]
}

@test "lint groups: lint_exclude rejects group names" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@mise"]
lint_exclude = ["@ci"]
EOF

  run codebase lint "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"lint_exclude accepts concrete lint names"* ]]
  [[ "$output" == *"@ci"* ]]
  [[ "$output" != *"codebase: lint:"* ]]
}

@test "lint groups: scope overrides apply to concrete rules after expansion" {
  mkdir -p "$REPO/scripts"
  cat > "$REPO/scripts/clean" <<'EOF'
#!/usr/bin/env bash
echo clean
EOF
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@shell"]
lint_exclude = ["shellcheck", "or-true", "bash-empty-argv-forwarding", "bash-empty-array-expansions", "exec-stderr-persistence", "process-substitution-status", "remote-url-output"]

[_.codebase.scope]
gum-table = "scripts"
EOF

  run codebase lint "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:gum-table $REPO_ROOT/scripts"* ]]
  [[ "$output" == *"codebase: all 1 lint rule(s) passed"* ]]
}

@test "lint groups: public aggregate preserves target paths containing spaces" {
  SPACED_REPO="$BATS_TEST_TMPDIR/repo with spaces"
  mkdir -p "$SPACED_REPO"
  git -C "$SPACED_REPO" init -q
  SPACED_ROOT="$(git -C "$SPACED_REPO" rev-parse --show-toplevel)"
  cat > "$SPACED_REPO/mise.toml" <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@mise"]
lint_exclude = ["mise-settings", "mise-usage-examples", "mcr-scope"]
EOF

  run codebase lint "$SPACED_REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:variadic-args $SPACED_ROOT"* ]]
}

@test "lint groups: CI enforcement counts the effective expanded portfolio" {
  mkdir -p "$REPO/.github/workflows"
  cat > "$REPO/.github/workflows/test.yml" <<'EOF'
name: Test
on: [push]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: codebase lint .
EOF
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@mise"]
lint_exclude = ["mise-usage-examples", "variadic-args", "mcr-scope"]
EOF

  run codebase lint:ci-lint-enforcement "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1 configured rule(s)"* ]]
  [[ "$output" == *"direct aggregate declaration"* ]]
}

@test "lint groups: excluding every expanded rule fails visibly" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["@ci"]
lint_exclude = ["github-actions", "ci-lint-enforcement"]
EOF

  run codebase lint "$REPO"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no lint rules configured after group expansion and exclusions"* ]]
  [[ "$output" == *"codebase lint:groups"* ]]
}
