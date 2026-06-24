#!/usr/bin/env bats
# Tests for lint:exec-stderr-silence rule

load ../../test_helper

setup() {
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

# Detection — basic

@test "exec-stderr-silence: passes on a clean codebase" {
  run codebase lint:exec-stderr-silence "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

@test "exec-stderr-silence: flags 'exec 3<>path 2>/dev/null'" {
  run codebase lint:exec-stderr-silence "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"dirty"* ]]
  [[ "$output" == *"exec 3<>"* ]]
  [[ "$output" == *"2>/dev/null"* ]]
}

@test "exec-stderr-silence: flags 'exec 2>/dev/null' standalone" {
  run codebase lint:exec-stderr-silence "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exec 2>/dev/null"* ]]
}

@test "exec-stderr-silence: flags 'exec ... 2>&-' (close stderr)" {
  run codebase lint:exec-stderr-silence "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"2>&-"* ]]
}

@test "exec-stderr-silence: flags 'exec ... 2>!' (noclobber override)" {
  run codebase lint:exec-stderr-silence "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"2>!"* ]]
}

@test "exec-stderr-silence: flags exec inside a function body" {
  run codebase lint:exec-stderr-silence "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exec 3<>\"\$tty\" 2>/dev/null"* ]]
}

# Safe patterns — no false positives

@test "exec-stderr-silence: does NOT flag 'exec 3<>path' without stderr redirect" {
  run codebase lint:exec-stderr-silence "$FIXTURES/clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"clean"* ]]
}

# Counting

@test "exec-stderr-silence: fail output names exec suppressions in dirty fixture" {
  run codebase lint:exec-stderr-silence "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  # The dirty fixture has these violations (excluding the annotated line 19):
  #   Line 5:  exec 3<>"$tty_path" 2>/dev/null
  #   Line 10: exec 2>/dev/null cat /tmp/nope
  #   Line 13: exec 2>/dev/null
  #   Line 16: exec 3<>"$path" 2>&-
  #   Line 25: exec 3<>"$path" 2>!"$tty_path"
  #   Line 30: exec 3<>"$tty" 2>/dev/null
  # = 6 violations
  [[ "$output" == *"6 exec stderr suppression"* ]]
}

# Diagnostic content

@test "exec-stderr-silence: fail output includes the violating file path" {
  run codebase lint:exec-stderr-silence "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"probe"* ]]
}

@test "exec-stderr-silence: fail output includes the grouping hint" {
  run codebase lint:exec-stderr-silence "$FIXTURES/dirty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"grouping construct"* ]] || [[ "$output" == *"{ exec ...; }"* ]]
}

# Ignore directives

@test "exec-stderr-silence: inline '# codebase:ignore exec-stderr-silence — reason' skips the line" {
  run codebase lint:exec-stderr-silence "$FIXTURES/ignored-inline"
  [ "$status" -ne 0 ]
  # The annotated lines are skipped, but the unannotated line 13 should still be flagged
  [[ "$output" == *"FAIL"*"ignored-inline"* ]]
  [[ "$output" != *"intentional exec fd setup"* ]]
}

@test "exec-stderr-silence: 'codebase:ignore exec-stderr-silence' in mise.toml skips the whole target" {
  run codebase lint:exec-stderr-silence "$FIXTURES/ignored-file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"*"ignored-file"* ]]
}

# Scope / discovery

@test "exec-stderr-silence: walks the whole target — finds hits outside .mise/tasks/" {
  run codebase lint:exec-stderr-silence "$FIXTURES/broad-walk"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/deploy.sh"* ]]
  [[ "$output" == *"bin/tool"* ]]
}

@test "exec-stderr-silence: works on a codebase with no mise.toml" {
  run codebase lint:exec-stderr-silence "$FIXTURES/no-toml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"no-toml"* ]]
}

@test "exec-stderr-silence: handles empty directory (no shell files)" {
  run codebase lint:exec-stderr-silence "$FIXTURES/empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"empty"* ]]
}

# Codebase: ignore mechanism — inline ignore without reason is not enough

@test "exec-stderr-silence: generic inline ignore without rule and reason does not suppress" {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.mise/tasks"
  cat > "$tmp/.mise/tasks/probe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec 3<>"$path" 2>/dev/null  # codebase:ignore
EOF

  run codebase lint:exec-stderr-silence "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exec 3<>"* ]]
  rm -rf "$tmp"
}

# Help output

@test "exec-stderr-silence: help output describes the rule" {
  run bash -c 'cd "$REPO_DIR" && mise tasks info lint:exec-stderr-silence'
  [ "$status" -eq 0 ]
  [[ "$output" == *"exec"* ]]
  [[ "$output" == *"persists"* ]]
}