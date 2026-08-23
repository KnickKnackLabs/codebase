#!/usr/bin/env bats
# Public-path contract for detecting repository Mise dispatch in BATS bodies.

load ../../test_helper
load test_helper
bats_require_minimum_version 1.5.0

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
