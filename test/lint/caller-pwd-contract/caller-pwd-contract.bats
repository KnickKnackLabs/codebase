#!/usr/bin/env bats
# Tests for lint:caller-pwd-contract rule

load ../../test_helper

setup() {
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
}

make_pkg() {
  local dir="$1"
  mkdir -p "$dir/.mise/tasks"
  cat > "$dir/.mise/tasks/demo"
  chmod +x "$dir/.mise/tasks/demo"
}

@test "passes when package-specific caller var precedes legacy fallback" {
  target="$WORK/clean"
  make_pkg "$target" <<'BASH'
#!/usr/bin/env bash
TARGET="${CLEAN_CALLER_PWD:-${CALLER_PWD:-.}}"
printf "%s\n" "$TARGET"
BASH

  run codebase lint:caller-pwd-contract "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "dot target derives package name from physical repo directory" {
  target="$WORK/shimmer"
  make_pkg "$target" <<'BASH'
#!/usr/bin/env bash
TARGET="${SHIMMER_CALLER_PWD:-${CALLER_PWD:-.}}"
printf "%s\n" "$TARGET"
BASH

  CODEBASE_CALLER_PWD="$target" run codebase lint:caller-pwd-contract .
  [ "$status" -eq 0 ]
  [[ "$output" == *"expects SHIMMER_CALLER_PWD"* ]]
}

@test "configured codebase name survives a renamed checkout directory" {
  target="$WORK/notes-review"
  make_pkg "$target" <<'BASH'
#!/usr/bin/env bash
TARGET="${NOTES_CALLER_PWD:-${CALLER_PWD:-.}}"
printf "%s\n" "$TARGET"
BASH
  cat > "$target/mise.toml" <<'TOML'
[_.codebase]
name = "notes"
TOML

  run codebase lint:caller-pwd-contract "$target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"expects NOTES_CALLER_PWD"* ]]
}

@test "fails on SHIV_CALLER_PWD in a non-shiv package" {
  target="$WORK/shimmer"
  make_pkg "$target" <<'BASH'
#!/usr/bin/env bash
TARGET="${SHIV_CALLER_PWD:-${CALLER_PWD:-.}}"
printf "%s\n" "$TARGET"
BASH

  run codebase lint:caller-pwd-contract "$target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uses SHIV_CALLER_PWD instead of SHIMMER_CALLER_PWD"* ]]
  [[ "$output" == *"legacy CALLER_PWD fallback must come after SHIMMER_CALLER_PWD"* ]]
}

@test "fails on any non-package caller var, not just SHIV_CALLER_PWD" {
  target="$WORK/modules"
  make_pkg "$target" <<'BASH'
#!/usr/bin/env bash
TARGET="${THREADS_CALLER_PWD:-.}"
printf "%s\n" "$TARGET"
BASH

  run codebase lint:caller-pwd-contract "$target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uses THREADS_CALLER_PWD instead of MODULES_CALLER_PWD"* ]]
}

@test "fails when runtime exports legacy CALLER_PWD" {
  target="$WORK/bad-export"
  make_pkg "$target" <<'BASH'
#!/usr/bin/env bash
export CALLER_PWD="$PWD"
exec mise run "$@"
BASH

  run codebase lint:caller-pwd-contract "$target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exports legacy CALLER_PWD at runtime"* ]]
}

@test "fails when runtime assigns legacy CALLER_PWD" {
  target="$WORK/bad-assign"
  make_pkg "$target" <<'BASH'
#!/usr/bin/env bash
CALLER_PWD="$PWD" exec mise run "$@"
BASH

  run codebase lint:caller-pwd-contract "$target"
  [ "$status" -eq 1 ]
  [[ "$output" == *"assigns legacy CALLER_PWD at runtime"* ]]
}

@test "allows SHIV_CALLER_PWD inside the shiv package itself" {
  target="$WORK/shiv"
  make_pkg "$target" <<'BASH'
#!/usr/bin/env bash
TARGET="${SHIV_CALLER_PWD:-${CALLER_PWD:-.}}"
printf "%s\n" "$TARGET"
BASH

  run codebase lint:caller-pwd-contract "$target"
  [ "$status" -eq 0 ]
}
