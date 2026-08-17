#!/usr/bin/env bats
# Public-path behavior for the shiv backend configuration lint.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  FIXTURE="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIXTURE"
}

write_mise() {
  cat > "$FIXTURE/mise.toml"
}

@test "passes when shiv tools and canonical backend setup are present" {
  write_mise <<'TOML'
[tools]
"shiv:codebase" = "0.4"
[plugins]
shiv = "https://github.com/KnickKnackLabs/vfox-shiv"
[settings]
experimental = true
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo"* ]]
}

@test "accepts equivalent inline-table configuration" {
  write_mise <<'TOML'
settings = { experimental = true }
plugins = { shiv = "https://github.com/KnickKnackLabs/vfox-shiv" }
[tools]
"shiv:readme" = "0.3"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "enforces backend setup for table-form shiv tool declarations" {
  write_mise <<'TOML'
[tools."shiv:codebase"]
version = "0.4"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.experimental = true"* ]]
  [[ "$output" == *"plugins.shiv ="* ]]
}

@test "detects shiv tools in a large tools table under pipefail" {
  {
    printf '%s\n' '[tools]' '"shiv:codebase" = "0.4"'
    local i=1
    while [[ "$i" -le 12000 ]]; do
      printf '"tool-%05d" = "1"\n' "$i"
      i=$((i + 1))
    done
  } > "$FIXTURE/mise.toml"

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.experimental = true"* ]]
  [[ "$output" == *"plugins.shiv ="* ]]
  [[ "$output" != *"no shiv tools declared"* ]]
}

@test "accepts canonical plugin URL suffixes and refs" {
  local source

  for source in \
    "https://github.com/KnickKnackLabs/vfox-shiv.git" \
    "https://github.com/KnickKnackLabs/vfox-shiv#main" \
    "https://github.com/KnickKnackLabs/vfox-shiv.git#main"; do
    write_mise <<TOML
[settings]
experimental = true
[plugins]
shiv = "$source"
[tools]
"shiv:codebase" = "0.4"
TOML

    run codebase lint:mise-shiv-plugin "$FIXTURE"

    [ "$status" -eq 0 ]
  done
}

@test "passes without enforcing backend setup when no shiv tools are declared" {
  write_mise <<'TOML'
[tools]
bats = "1.13.0"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no shiv tools declared"* ]]
}

@test "fails when experimental mode is absent" {
  write_mise <<'TOML'
[tools]
"shiv:codebase" = "0.4"
[plugins]
shiv = "https://github.com/KnickKnackLabs/vfox-shiv"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.experimental = true"* ]]
  [[ "$output" != *"plugins.shiv ="* ]]
}

@test "fails when experimental mode is false" {
  write_mise <<'TOML'
[settings]
experimental = false
[plugins]
shiv = "https://github.com/KnickKnackLabs/vfox-shiv"
[tools]
"shiv:codebase" = "0.4"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.experimental = true"* ]]
}

@test "fails when the shiv plugin is absent" {
  write_mise <<'TOML'
[settings]
experimental = true
[tools]
"shiv:codebase" = "0.4"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"plugins.shiv ="* ]]
  [[ "$output" != *"settings.experimental = true"* ]]
}

@test "fails when the shiv plugin points at a different source" {
  write_mise <<'TOML'
[settings]
experimental = true
[plugins]
shiv = "https://example.invalid/vfox-shiv"
[tools]
"shiv:codebase" = "0.4"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"KnickKnackLabs/vfox-shiv"* ]]
}

@test "does not accept prerequisite-looking keys from the wrong sections" {
  write_mise <<'TOML'
[settings]
quiet = true
[plugins]
other = "https://example.invalid/plugin"
[tools]
"shiv:codebase" = "0.4"
[unrelated]
experimental = true
shiv = "https://github.com/KnickKnackLabs/vfox-shiv"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.experimental = true"* ]]
  [[ "$output" == *"plugins.shiv ="* ]]
}

@test "fails clearly when mise.toml is malformed" {
  printf '%s\n' '[tools' '"shiv:codebase" = "0.4"' > "$FIXTURE/mise.toml"

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"mise.toml could not be parsed"* ]]
}

@test "fails when the target has no mise.toml" {
  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"no mise.toml found"* ]]
}

@test "honors a reasoned repository ignore" {
  write_mise <<'TOML'
# codebase:ignore mise-shiv-plugin -- package exercises missing-backend diagnostics
[tools]
"shiv:codebase" = "0.4"
TOML

  run codebase lint:mise-shiv-plugin "$FIXTURE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  repo"* ]]
}

@test "preserves quoted target paths through the public task" {
  local spaced="$BATS_TEST_TMPDIR/repo with spaces"
  mkdir -p "$spaced"
  cat > "$spaced/mise.toml" <<'TOML'
[tools]
bats = "1.13.0"
TOML

  run codebase lint:mise-shiv-plugin "$spaced"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo with spaces"* ]]
}

@test "reports each target and returns the number of failing targets" {
  local other="$BATS_TEST_TMPDIR/other"
  mkdir -p "$other"
  write_mise <<'TOML'
[tools]
"shiv:codebase" = "0.4"
TOML
  cp "$FIXTURE/mise.toml" "$other/mise.toml"

  run codebase lint:mise-shiv-plugin "$FIXTURE" "$other"

  [ "$status" -eq 2 ]
  [[ "$output" == *"FAIL  repo"* ]]
  [[ "$output" == *"FAIL  other"* ]]
}

@test "missing and nonexistent targets fail through the public contract" {
  run codebase lint:mise-shiv-plugin
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]

  run codebase lint:mise-shiv-plugin "$FIXTURE/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}
