#!/usr/bin/env bats
# Public-path contract for the intentionally narrow variadic Usage consumer lint.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  FIXTURE="$BATS_TEST_TMPDIR/repo"
  TASK="$FIXTURE/.mise/tasks/check"
  mkdir -p "$(dirname "$TASK")"
}

write_task() {
  cat > "$TASK"
  chmod +x "$TASK"
}

@test "flags direct declared expansions beneath static eval arguments" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
#USAGE flag "--to <to>" default="" var=#true
prefix=ok eval "${usage_args}" pre "$usage_to"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"2 known unsafe"* ]]
  [[ "$output" == *'eval "${usage_args}"'* ]]
}

@test "flags the current legacy read idiom with an assignment prefix" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[names...]" help="Names"
IFS=' ' read -ra NAMES <<< "$usage_names"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"read -ra NAMES"* ]]
  [[ "$output" == *"xargs printf"* ]]
}

@test "accepts the complete finite read option grammar" {
  local options

  for options in "-a" "-ra" "-ar" "-r -a" "-a -r" "-r -r -a"; do
    write_task <<BASH
#!/usr/bin/env bash
#USAGE flag "--as <alias>" default="" var=#true
IFS=' ' read $options ALIASES <<< "\$usage_as"
BASH

    run codebase lint:variadic-args "$FIXTURE"

    [ "$status" -eq 1 ]
  done
}

@test "flags an unquoted expansion that is itself an eval argument" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
eval $usage_args
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *'eval $usage_args'* ]]
}

@test "does not treat assignment prefixes or redirected eval as supported arguments" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
prefix="$usage_args" eval safe
eval "$usage_args" >output
<input eval "$usage_args"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "does not attribute a nested producer expansion to outer eval" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
eval "$(printf '%s' "$usage_args")"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "does not let a nested redirect hide a direct eval argument" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
eval "$usage_args" "$(cat <input)"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *'eval "$usage_args"'* ]]
}

@test "scans a nested static eval as its own consumer" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
printf '%s\n' "$(eval "$usage_args")"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"eval"* ]]
}

@test "does not flag dynamic and semantically indirect eval forms" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
command eval "$usage_args"
runner=eval
"$runner" "$usage_args"
program="$usage_args"
eval "$program"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "does not flag unsupported read shapes" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[names]" default="" var=#true
read -r NAMES <<< "$usage_names"
read -a -a NAMES <<< "$usage_names"
read -d : -a NAMES <<< "$usage_names"
read -ra NAMES extra <<< "$usage_names"
read "$options" NAMES <<< "$usage_names"
read -ra "$usage_names" <<< "$usage_names"
read -ra NAMES "$usage_names"
<input read -ra NAMES <<< "$usage_names"
read -ra NAMES <<< "$usage_names" >output
read -ra NAMES < <(printf '%s' "$usage_names")
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "requires the final here-string payload to be exactly the declaration" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[names]" default="" var=#true
read -ra NAMES <<< "prefix:$usage_names"
read -ra NAMES <<< "$usage_other"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "ignores nonvariadic and mismatched Usage values" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[name]" default=""
#USAGE flag "--to <to>" default=""
eval "$usage_name"
read -ra VALUES <<< "$usage_to"
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "ignores comments strings and quoted heredoc bodies" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
# eval "$usage_args"
printf '%s\n' 'eval "$usage_args"'
cat <<'TEXT'
eval "$usage_args"
read -ra ARGS <<< "$usage_args"
TEXT
BASH

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 0 ]
}

@test "honors only a reasoned file suppression" {
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
# codebase:ignore variadic-args -- fixture deliberately exercises eval

eval "$usage_args"
BASH

  run codebase lint:variadic-args "$FIXTURE"
  [ "$status" -eq 0 ]

  sed -i.bak 's/ -- fixture deliberately exercises eval//' "$TASK"
  rm "$TASK.bak"
  run codebase lint:variadic-args "$FIXTURE"
  [ "$status" -eq 1 ]
}

@test "checks only executable Bash tasks beneath .mise/tasks" {
  write_task <<'BASH'
#!/usr/bin/env sh
#USAGE arg "[args]" default="" var=#true
eval "$usage_args"
BASH
  cat > "$FIXTURE/.mise/tasks/not-executable" <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
eval "$usage_args"
BASH
  mkdir -p "$FIXTURE/scripts"
  cat > "$FIXTURE/scripts/other" <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
eval "$usage_args"
BASH
  chmod +x "$FIXTURE/scripts/other"

  run codebase lint:variadic-args "$FIXTURE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"0 executable Bash task(s) clean"* ]]
}

@test "preserves quoted targets and returns failing-target count" {
  local other="$BATS_TEST_TMPDIR/other repo"
  write_task <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" default="" var=#true
eval "$usage_args"
BASH
  mkdir -p "$other/.mise/tasks"
  cp "$TASK" "$other/.mise/tasks/check"

  run codebase lint:variadic-args "$FIXTURE" "$other"

  [ "$status" -eq 2 ]
  [[ "$output" == *"FAIL  repo"* ]]
  [[ "$output" == *"FAIL  other repo"* ]]
}

@test "missing and nonexistent targets fail clearly" {
  run codebase lint:variadic-args
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]

  run codebase lint:variadic-args "$FIXTURE/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}
