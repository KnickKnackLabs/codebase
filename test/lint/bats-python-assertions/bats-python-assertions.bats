#!/usr/bin/env bats
# Public-path behavior for inline Python assertion linting in BATS tests.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  TARGET="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TARGET/test"
}

write_bats() {
  local name="$1"
  cat > "$TARGET/test/$name.bats"
}

@test "flags direct python3 -c assertions" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  echo "$output" | python3 -c "import json, sys; data=json.load(sys.stdin); assert data == {}"
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"test/parse.bats:3"* ]]
  [[ "$output" == *"python3 -c"* ]]
  [[ "$output" == *"fold/notes/bats-tool-testing.md"* ]]
}

@test "flags BATS run python assertions" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  run python -c 'assert value' input.json
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"inline Python assertion"* ]]
}

@test "flags BATS run assertions after supported run options" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  run --separate-stderr python3 -c 'assert value'
  run ! python3 -c 'assert value'
  run -1 python3 -c 'assert value'
  run -1 --keep-empty-lines --separate-stderr -- python3 -c 'assert value'
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"4 inline Python assertion(s)"* ]]
}

@test "flags multiline inline Python commands" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  python3 \
    -c \
    'value = 1; assert value'
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"test/parse.bats:3"* ]]
}

@test "does not confuse assert text in Python strings or comments with statements" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  python3 -c 'print("assert value")'
  python3 -c "print(\"assert value\")"
  python3 -c 'print("x; assert value")'
  python3 -c 'value = 1  # assert value'
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 0 ]
}

@test "flags assertions after strings in shell double-quoted programs" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  python3 -c "print(\"harmless\"); assert value"
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"test/parse.bats:3"* ]]
}

@test "distinguishes escaped Python quotes from later assertions" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  python3 -c "value = \"a\\\"assert text\"; print(value)"
  python3 -c "value = \"a\\\"b\"; assert value"
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"1 inline Python assertion"* ]]
  [[ "$output" == *"test/parse.bats:4"* ]]
}

@test "allows harmless inline Python and readable Python heredocs" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  python3 -c 'print(1)'
  python3 - <<'PY'
value = 1
assert value
PY
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 0 ]
}

@test "AST selection ignores shell comments strings and quoted heredocs" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  # python3 -c 'assert value'
  printf '%s\n' "python3 -c 'assert value'"
  cat <<'EXAMPLE'
python3 -c 'assert value'
EXAMPLE
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 0 ]
}

@test "reasoned inline ignore suppresses only its command" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  python3 -c 'assert value' # codebase:ignore bats-python-assertions — compact upstream reproduction
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 0 ]
}

@test "bare and unrelated ignores do not suppress findings" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" {
  python3 -c 'assert value' # codebase:ignore
  python3 -c 'assert other' # codebase:ignore another-rule — unrelated
}
BATS

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"2 inline Python assertion"* ]]
}

@test "repository ignore skips the target" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" { python3 -c 'assert value'; }
BATS
  cat > "$TARGET/mise.toml" <<'TOML'
# codebase:ignore bats-python-assertions — generated compatibility tests preserve upstream syntax
TOML

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  repo"* ]]
}

@test "checks a BATS file target directly" {
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" { python3 -c 'assert value'; }
BATS

  run codebase lint:bats-python-assertions "$TARGET/test/parse.bats"

  [ "$status" -eq 1 ]
  [[ "$output" == *"parse.bats:2"* ]]
}

@test "checks quoted multi-target paths through the public Mise contract" {
  local clean="$BATS_TEST_TMPDIR/clean repo"
  mkdir -p "$clean/test"
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" { python3 -c 'assert value'; }
BATS
  cat > "$clean/test/clean.bats" <<'BATS'
#!/usr/bin/env bats
@test "parse" { python3 -c 'print(1)'; }
BATS

  run codebase lint:bats-python-assertions "$TARGET" "$clean"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo"* ]]
  [[ "$output" == *"OK    clean repo"* ]]
}

@test "reports each failing target in the exit status" {
  local other="$BATS_TEST_TMPDIR/other"
  mkdir -p "$other/test"
  write_bats parse <<'BATS'
#!/usr/bin/env bats
@test "parse" { python3 -c 'assert value'; }
BATS
  cp "$TARGET/test/parse.bats" "$other/test/parse.bats"

  run codebase lint:bats-python-assertions "$TARGET" "$other"

  [ "$status" -eq 2 ]
}

@test "passes a target without BATS files" {
  rm -rf "$TARGET/test"

  run codebase lint:bats-python-assertions "$TARGET"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no BATS files found"* ]]
}

@test "missing and nonexistent targets fail through the public contract" {
  run codebase lint:bats-python-assertions
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]

  run codebase lint:bats-python-assertions "$TARGET/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}
