#!/usr/bin/env bats
# Public-path behavior for the Mise usage-example lint.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/.mise/tasks"
}

write_task() {
  local relative="$1"
  local task="$REPO/.mise/tasks/$relative"

  mkdir -p "$(dirname "$task")"
  cat > "$task"
  chmod +x "$task"
}

@test "reports nested public tasks that declare arguments without examples" {
  write_task lint/check <<'BASH'
#!/usr/bin/env bash
#MISE description="Check a target"
#USAGE arg "<target>"
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo  .mise/tasks/lint/check"* ]]
  [[ "$output" == *"public task lint:check"* ]]
}

@test "reports boolean flag interfaces without examples" {
  write_task deploy <<'BASH'
#!/usr/bin/env bash
#MISE description="Deploy"
#USAGE flag "--verbose"
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"public task deploy declares arguments or flags"* ]]
}

@test "accepts one or several examples" {
  write_task greet <<'BASH'
#!/usr/bin/env bash
#MISE description="Greet someone"
#USAGE arg "<name>"
#USAGE example "mise run greet Ada"
#USAGE example "mise run greet Grace"
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    repo"* ]]
}

@test "rejects malformed examples without a command" {
  write_task greet <<'BASH'
#!/usr/bin/env bash
#MISE description="Greet someone"
#USAGE arg "<name>"
#USAGE example
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"public task greet"* ]]
}

@test "accepts public tasks without arguments or flags" {
  write_task doctor <<'BASH'
#!/usr/bin/env bash
#MISE description="Check health"
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 0 ]
}

@test "skips tasks hidden through Mise metadata" {
  write_task internal <<'BASH'
#!/usr/bin/env bash
#MISE description="Internal helper"
#MISE hide=true
#USAGE arg "<target>"
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" != *"internal"* ]]
}

@test "checks namespace default tasks under their public name" {
  write_task lint/_default <<'BASH'
#!/usr/bin/env bash
#MISE description="Run lints"
#USAGE arg "[target]"
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"public task lint"* ]]
  [[ "$output" == *".mise/tasks/lint/_default"* ]]
}

@test "ignores non-executable files even when they contain directives" {
  cat > "$REPO/.mise/tasks/helper.sh" <<'BASH'
#!/usr/bin/env bash
#USAGE arg "<target>"
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 0 ]
}

@test "does not count directive-looking body text as an example" {
  write_task render <<'BASH'
#!/usr/bin/env bash
#MISE description="Render text"
#USAGE arg "<target>"
printf '%s\n' '#USAGE example "text, not task metadata"'
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"public task render"* ]]
}

@test "does not treat directive-looking body text as an ignore" {
  write_task render <<'BASH'
#!/usr/bin/env bash
#MISE description="Render text"
#USAGE arg "<target>"
cat <<'TEXT'
# codebase:ignore mise-usage-examples -- this is rendered output, not task metadata
TEXT
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"public task render"* ]]
}

@test "honors a reasoned inline rule ignore" {
  write_task legacy <<'BASH'
#!/usr/bin/env bash
#MISE description="Legacy interface"
#USAGE arg "<target>"
# codebase:ignore mise-usage-examples -- compatibility task is not user-invoked directly
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 0 ]
}

@test "does not honor an unreasoned inline ignore" {
  write_task legacy <<'BASH'
#!/usr/bin/env bash
#MISE description="Legacy interface"
#USAGE arg "<target>"
# codebase:ignore mise-usage-examples
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 1 ]
}

@test "honors a reasoned repository rule ignore" {
  cat > "$REPO/mise.toml" <<'TOML'
# codebase:ignore mise-usage-examples -- generated task documentation is tested upstream
[settings]
quiet = true
TOML
  write_task generated <<'BASH'
#!/usr/bin/env bash
#MISE description="Generated interface"
#USAGE flag "--format <format>"
true
BASH

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  repo"* ]]
}

@test "preserves spaced paths and returns the number of findings across targets" {
  local spaced="$BATS_TEST_TMPDIR/repo with spaces"
  mkdir -p "$spaced/.mise/tasks"
  write_task first <<'BASH'
#!/usr/bin/env bash
#MISE description="First"
#USAGE arg "<target>"
true
BASH
  cat > "$spaced/.mise/tasks/second" <<'BASH'
#!/usr/bin/env bash
#MISE description="Second"
#USAGE flag "--force"
true
BASH
  chmod +x "$spaced/.mise/tasks/second"

  run codebase lint:mise-usage-examples "$REPO" "$spaced"

  [ "$status" -eq 2 ]
  [[ "$output" == *"FAIL  repo "* ]]
  [[ "$output" == *"FAIL  repo with spaces "* ]]
}

@test "accepts a repository without a file-task directory" {
  rm -rf "$REPO/.mise/tasks"

  run codebase lint:mise-usage-examples "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no .mise/tasks"* ]]
}

@test "missing and nonexistent targets fail through the public contract" {
  run codebase lint:mise-usage-examples
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]

  run codebase lint:mise-usage-examples "$REPO/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}
