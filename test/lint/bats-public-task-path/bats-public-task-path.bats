#!/usr/bin/env bats
# Public-path contract for detecting repository Mise dispatch in BATS bodies.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  TARGET="$BATS_TEST_TMPDIR/fixture repo"
  mkdir -p "$TARGET/test"
  cat > "$TARGET/mise.toml" <<'TOML'
[_.codebase]
name = "fixture"
TOML
}

write_bats() {
  local raw="$TARGET/test/example.bats.raw"
  cat > "$raw"
  awk '
    /^bats_test_function / { print "@test \"fixture\" {"; next }
    { print }
  ' "$raw" > "$TARGET/test/example.bats"
  rm "$raw"
}

@test "flags direct root dispatch with BATS run env and explicit root forms" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "direct" {
  mise run lock
  run mise --quiet run list
  run env CALLER_PWD="$PWD" mise run status
  run mise -C "$REPO_DIR" run verify
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  fixture repo: 4 raw repository Mise dispatch(es)"* ]]
  [[ "$output" == *"test/example.bats:3: mise run lock"* ]]
  [[ "$output" == *"test/example.bats:6: run mise -C"* ]]
}

@test "flags the original nested bash payload that bypasses a wrapper" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "stale caller" {
  run bash -c 'cd "$REPO_DIR" && CALLER_PWD="$1" mise run -q list --json' _ "$stale"
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"test/example.bats:3: run bash -c"* ]]
}

@test "does not flag wrapper definitions or Mise text used as data" {
  write_bats <<'BATS'
#!/usr/bin/env bats
mytool() {
  (cd "$REPO_DIR" && mise run -q "$@")
}
@test "search syntax" {
  run rg 'mise run task' "$REPO_DIR"
  printf '%s\n' 'mise run example'
  run mytool list
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    fixture"* ]]
}

@test "allows explicit alternate fixture workspaces" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "fixture dispatch" {
  run mise -C "$fixture" run test
  run env MODE=test mise --cd="$WORK_DIR" run verify
  run bash -c 'cd "$fixture" && env -u REPO_DIR mise run test'
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 0 ]
}

@test "does not mistake canonical root for an alternate workspace" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "root dispatch" {
  run mise --cd="${REPO_DIR}" run test
  run bash -c 'cd "$REPO_DIR" && env -u REPO_DIR mise run test'
  run bash -c 'cd "$fixture" && env -u REPO_DIR mise -C "$REPO_DIR" run test'
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"3 raw repository Mise dispatch(es)"* ]]
}

@test "inspects double-quoted static shell payloads" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "nested" {
  run bash -c "cd \"\$REPO_DIR\" && mise run list"
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
}

@test "does not claim to resolve dynamic shell payloads" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "dynamic internal unit" {
  script="${COMMON_SRC}; call_internal"
  run bash -c "$script"
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 0 ]
}

@test "supports function-comment BATS syntax" {
  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' 'dispatch() { # @''test'
    printf '%s\n' '  run mise run test' '}'
  } > "$TARGET/test/example.bats"

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"test/example.bats:3:"* ]]
}

@test "supports inline and repository-wide ignores" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "intentional" {
  run mise run test # codebase:ignore bats-public-task-path -- dispatch itself is under test
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"
  [ "$status" -eq 0 ]

  cat >> "$TARGET/mise.toml" <<'TOML'
# codebase:ignore bats-public-task-path -- this repository tests Mise itself
TOML
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "intentional" {
  run mise run test
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  fixture"* ]]
}

@test "fails closed when normalized BATS contains malformed Bash" {
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "broken" {
  if then
}
BATS

  run codebase lint:bats-public-task-path "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"BATS Bash syntax"* ]]
  [[ "$output" != *"OK    fixture"* ]]
}

@test "reports each target and returns the failing target count" {
  local clean="$BATS_TEST_TMPDIR/clean"
  mkdir -p "$clean/test"
  cp "$TARGET/mise.toml" "$clean/mise.toml"
  write_bats <<'BATS'
#!/usr/bin/env bats
@test "raw" {
  run mise run test
}
BATS
  cat > "$clean/test/example.bats" <<'BATS'
#!/usr/bin/env bats
@test "public" {
  run mytool test
}
BATS

  run codebase lint:bats-public-task-path "$clean" "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"OK    clean"* ]]
  [[ "$output" == *"FAIL  fixture"* ]]
}

@test "missing and nonexistent targets fail clearly" {
  run codebase lint:bats-public-task-path
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]

  run codebase lint:bats-public-task-path "$TARGET/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}
