#!/usr/bin/env bats
# Tests for aggregate `codebase lint`

load ../test_helper

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  REPO_ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"
}

write_config() {
  cat > "$REPO/mise.toml"
}

write_clean_task() {
  mkdir -p "$REPO/.mise/tasks"
  cat > "$REPO/.mise/tasks/clean" <<'EOF'
#!/usr/bin/env bash
echo ok
EOF
}

write_bad_table_script() {
  local dir="$1"
  mkdir -p "$REPO/$dir"
  cat > "$REPO/$dir/table" <<'EOF'
#!/usr/bin/env bash
for item in alpha beta; do
  printf "%-10s %s\n" "$item" ok
done
EOF
}

@test "lint: runs configured rules and passes" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings"]
EOF

  run codebase lint "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:mise-settings"* ]]
  [[ "$output" == *"OK"*"repo"* ]]
  [[ "$output" == *"codebase: all 1 lint rule(s) passed"* ]]
}

@test "lint: default target resolves from CODEBASE_CALLER_PWD" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings"]
EOF

  CODEBASE_CALLER_PWD="$REPO" run codebase lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:mise-settings $REPO_ROOT"* ]]
}

@test "lint: relative target resolves from CODEBASE_CALLER_PWD" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings"]
EOF

  CODEBASE_CALLER_PWD="$BATS_TEST_TMPDIR" run codebase lint repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:mise-settings $REPO_ROOT"* ]]
}

@test "lint: target directory config wins over containing git root" {
  mkdir -p "$REPO/nested"
  cat > "$REPO/nested/mise.toml" <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["mise-settings"]
EOF
  nested_root="$(cd "$REPO/nested" && pwd -P)"

  run codebase lint "$REPO/nested"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:mise-settings $nested_root"* ]]
}

@test "lint: honors default rule scopes" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["gum-table"]
EOF
  write_clean_task
  write_bad_table_script scripts

  run codebase lint "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:gum-table $REPO_ROOT/.mise/tasks"* ]]
  [[ "$output" == *"codebase: all 1 lint rule(s) passed"* ]]
}

@test "lint: honors user scope overrides" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = ["gum-table"]

[_.codebase.scope]
gum-table = "scripts"
EOF
  write_clean_task
  write_bad_table_script scripts

  run codebase lint "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"codebase: lint:gum-table $REPO_ROOT/scripts"* ]]
  [[ "$output" == *"WARN"*"scripts:table"* ]]
  [[ "$output" == *"codebase: 1 lint rule(s) failed"* ]]
}

@test "lint: summarizes multiple failing rules" {
  write_config <<'EOF'
[settings]
quiet = true

[_.codebase]
lint = ["mise-settings", "gum-table"]

[_.codebase.scope]
gum-table = "scripts"
EOF
  write_bad_table_script scripts

  run codebase lint "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"repo: missing task_output"* ]]
  [[ "$output" == *"WARN"*"scripts:table"* ]]
  [[ "$output" == *"codebase: 2 lint rule(s) failed"* ]]
  [[ "$output" == *"lint:mise-settings"* ]]
  [[ "$output" == *"lint:gum-table"* ]]
}

@test "lint: fails when target does not exist" {
  run codebase lint "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}

@test "lint: fails when no mise.toml is present" {
  run codebase lint "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no mise.toml"* ]]
}

@test "lint: fails when no lint rules are configured" {
  write_config <<'EOF'
[tools]
bats = "1.13.0"
EOF

  run codebase lint "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no lint rules configured"* ]]
}

@test "lint: parses multiline lint arrays" {
  write_config <<'EOF'
[settings]
quiet = true
task_output = "interleave"

[_.codebase]
lint = [
  "mise-settings",
]
EOF

  run codebase lint "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codebase: lint:mise-settings"* ]]
}
