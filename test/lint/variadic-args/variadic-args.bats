#!/usr/bin/env bats
# Public-path behavior for variadic Usage consumer linting.

load ../../test_helper
bats_require_minimum_version 1.5.0

setup() {
  TARGET="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TARGET/.mise/tasks"
}

write_task() {
  local name="$1"
  mkdir -p "$(dirname "$TARGET/.mise/tasks/$name")"
  cat > "$TARGET/.mise/tasks/$name"
  chmod +x "$TARGET/.mise/tasks/$name"
}

@test "flags eval of a declared variadic argument" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
set -euo pipefail
LC_ALL=C eval "ARGS=(${usage_args:-})"
eval '$usage_args'
eval \$usage_args
eval true <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"3 unsafe variadic Usage consumer"* ]]
  [[ "$output" == *"ERROR: eval of usage_args"* ]]
  [[ "$output" == *".mise/tasks/search:4"* ]]
  [[ "$output" != *"eval true"* ]]
}

@test "flags read -a of a declared variadic long flag" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE flag "-q --query <query>" var=#true help="Do not confuse this with --other"
read -ra QUERIES <<< "$usage_query"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN: read -a loses Mise's quoting"* ]]
  [[ "$output" == *"usage_query"* ]]
}

@test "recognizes separated read options and hyphenated flag names" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE flag "--query-term <query>" var=#true
read -r -a QUERIES <<< "${usage_query_term:-}"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"usage_query_term"* ]]
}

@test "recognizes read options across line continuations" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read \
  -r \
  -a ARGS <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN: read -a loses Mise's quoting"* ]]
  [[ "$output" == *".mise/tasks/search:3: read \\"* ]]
}

@test "recognizes ANSI-C-quoted read array options and fragments" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read $'-a' ARGS <<< "$usage_args"
read $'\x2d\x61' MORE <<< "$usage_args"
read -$'a' FRAGMENTS <<< "$usage_args"
read $'-'$'a' SPLIT <<< "$usage_args"
read -a "$array_name" <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"5 unsafe variadic Usage consumer"* ]]
  [[ "$output" == *"WARN: read -a loses Mise's quoting"* ]]
}

@test "preserves expansion context for read array names" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -a STATIC <<< "$usage_args"
read -a 'QUOTED_STATIC' <<< "$usage_args"
read -a "$array_name" <<< "$usage_args"
read -a "${array_name:-DEFAULT}" <<< "$usage_args"
read -a '$array_name' <<< "$usage_args"
read -a \$array_name <<< "$usage_args"
read -a "\$array_name" <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"4 unsafe variadic Usage consumer"* ]]
}

@test "cross-references only real variadic value expansions for read" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -a FIRST <<< "$usage_args"
read -a SECOND <<< "${usage_args:-}"
read -a LITERAL_SINGLE <<< '$usage_args'
read -a LITERAL_BARE <<< \$usage_args
read -a LITERAL_DOUBLE <<< "\$usage_args"
usage_args=literal read -a ASSIGNMENT <<< "$other"
read -a ORDINARY_ARGUMENT "$usage_args" </dev/null
read -n "$usage_args" -a OPTION_ARGUMENT </dev/null
read -a "$usage_args" </dev/null
read -a ARG_PROCESS "$(printf '%s' "$usage_args")" </dev/null
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"2 unsafe variadic Usage consumer"* ]]
}

@test "cross-references real expansions in unquoted read heredocs only" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -r -a EXPANDED <<EOF
$usage_args
EOF
read -r -a LITERAL <<'EOF'
$usage_args
EOF
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"1 unsafe variadic Usage consumer"* ]]
  [[ "$output" == *".mise/tasks/search:3: read -r -a EXPANDED"* ]]
}

@test "keeps redirected ranges scoped to actual read input" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -a HERE_STRING <<< "$usage_args"
read -a PROCESS < <(printf '%s' "$usage_args")
< <(printf '%s' "$usage_args") read -a LEADING_PROCESS
<<< "$usage_args" read -a LEADING_HERE
read -a WINNING_HERE < <(printf '%s' "$other") <<< "$usage_args"
read -a OVERRIDDEN_PROCESS < <(printf '%s' "$usage_args") <<< "$other"
read -a OVERRIDDEN_PROCESS_PATH < <(printf '%s' "$usage_args") < /dev/null
read -a INPUT_PATH < "$usage_args"
read -a OUTPUT_PATH </dev/null > "$usage_args"
read -a FD_PATH 3> "$usage_args" </dev/null
read -a OUTPUT_PROCESS </dev/null > >(printf '%s' "$usage_args")
read -a PROCESS_INPUT_PATH < <(cat < "$usage_args")
read -a PROCESS_OUTPUT_PATH < <(printf literal > "$usage_args")
read -a PROCESS_FD_PATH < <(printf literal 3> "$usage_args")
read -a HEREDOC_OUTPUT <<EOF > "$usage_args"
literal
EOF
read -a FD_HEREDOC 3<<EOF </dev/null
$usage_args
EOF
read -a OVERRIDDEN_HEREDOC <<EOF <<< "$other"
$usage_args
EOF
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"5 unsafe variadic Usage consumer"* ]]
  [[ "$output" == *"HERE_STRING"* ]]
  [[ "$output" == *"PROCESS"* ]]
  [[ "$output" == *"LEADING_PROCESS"* ]]
  [[ "$output" == *"LEADING_HERE"* ]]
  [[ "$output" == *"WINNING_HERE"* ]]
  [[ "$output" != *"OVERRIDDEN_PROCESS"* ]]
  [[ "$output" != *"OVERRIDDEN_PROCESS_PATH"* ]]
  [[ "$output" != *"INPUT_PATH"* ]]
  [[ "$output" != *"OUTPUT_PATH"* ]]
  [[ "$output" != *"FD_PATH"* ]]
  [[ "$output" != *"OUTPUT_PROCESS"* ]]
  [[ "$output" != *"PROCESS_INPUT_PATH"* ]]
  [[ "$output" != *"PROCESS_OUTPUT_PATH"* ]]
  [[ "$output" != *"PROCESS_FD_PATH"* ]]
  [[ "$output" != *"HEREDOC_OUTPUT"* ]]
  [[ "$output" != *"FD_HEREDOC"* ]]
  [[ "$output" != *"OVERRIDDEN_HEREDOC"* ]]
}

@test "attributes nested read expansions to the innermost consumer" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -a OUTER <<< "$(
  read -a INNER <<< "$usage_args"
  printf '%s' "$other"
)"
cat <<EOF
$(read -a HEREDOC_NESTED <<< "$usage_args")
EOF
read -a EVAL_OUTER <<EOF
$(eval 'printf %s "$usage_args"')
EOF
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"3 unsafe variadic Usage consumer"* ]]
  [[ "$output" == *".mise/tasks/search:4: read -a INNER"* ]]
  [[ "$output" == *"eval 'printf %s \"\$usage_args\"'"* ]]
}

@test "does not normalize literal or invalid read words into array options" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read '-\
a' VALUE <<< "$usage_args"
read $'-a\n' VALUE <<< "$usage_args"
read -a$'\n' VALUE <<< "$usage_args"
read $'-a\cA' VALUE <<< "$usage_args"
read "$'-a'" VALUE <<< "$usage_args"
read \$'-a' VALUE <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
}

@test "recognizes assignment-prefixed commands without matching assignment values" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
DESCRIPTION='read -ra DECOY' printf '%s\n' "$usage_args"
MODE+=strict IFS=' ' read -ra ARGS <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"1 unsafe variadic Usage consumer"* ]]
  [[ "$output" == *"MODE+=strict IFS=' ' read -ra ARGS"* ]]
}

@test "preserves primary ranges for quoted multiline assignment-prefixed commands" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
DESCRIPTION=('read -ra DECOY' "$usage_args")
IFS=$'\'' \
read -d $'\'' -a ARGS <<< "$usage_args"
MODE=$'eval \' DECOY' \
eval "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"2 unsafe variadic Usage consumer"* ]]
  [[ "$output" == *".mise/tasks/search:4: IFS="* ]]
  [[ "$output" == *".mise/tasks/search:6: MODE="* ]]
  [[ "$output" != *"DESCRIPTION="* ]]
}

@test "recognizes read -a after an option argument" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -n 1 -a ARGS <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN: read -a loses Mise's quoting"* ]]
}

@test "does not treat an attached read option argument as -a" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -da VALUE <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
}

@test "recognizes read -a after the flag-only uppercase E option" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -E -a ARGS <<< "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"WARN: read -a loses Mise's quoting"* ]]
}

@test "stops read option recognition at the terminator" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
read -- -a "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
}

@test "does not flag safe xargs parsing" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
ARGS=()
while IFS= read -r arg; do
  ARGS+=("$arg")
done < <(printf '%s' "$usage_args" | xargs printf '%s\n')
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
}

@test "only cross-references variables declared variadic in the same task" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[files]" var=#true
#USAGE flag "--query <query>"
eval "QUERY=(${usage_query:-})"
read -ra OTHER <<< "$usage_other"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
}

@test "parses custom argument names and old ellipsis spelling" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[input_files]..." var=#true
eval "FILES=(${usage_input_files:-})"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"usage_input_files"* ]]
}

@test "AST selection ignores comments strings and quoted heredocs" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
# eval "ARGS=(${usage_args:-})"
printf '%s\n' 'read -ra ARGS <<< "$usage_args"'
cat <<'EXAMPLE'
eval "ARGS=(${usage_args:-})"
EXAMPLE
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
}

@test "AST byte ranges preserve multiline eval commands" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
eval \
  "ARGS=(${usage_args:-})"
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: eval of usage_args"* ]]
}

@test "reasoned inline ignore suppresses only its command" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
eval "ARGS=(${usage_args:-})" # codebase:ignore variadic-args — trusted generated input
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
}

@test "bare or unrelated inline ignore does not suppress" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
eval "ARGS=(${usage_args:-})" # codebase:ignore
eval "MORE=(${usage_args:-})" # codebase:ignore other-rule — unrelated
BASH

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 1 ]
  [[ "$output" == *"2 unsafe variadic Usage consumer"* ]]
}

@test "repository ignore skips the target" {
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
eval "ARGS=(${usage_args:-})"
BASH
  cat > "$TARGET/mise.toml" <<'TOML'
# codebase:ignore variadic-args — generated task syntax is trusted
TOML

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  repo"* ]]
}

@test "checks quoted multi-target paths through the public Mise contract" {
  local clean="$BATS_TEST_TMPDIR/clean repo"
  mkdir -p "$clean/.mise/tasks"
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
eval "ARGS=(${usage_args:-})"
BASH
  cat > "$clean/.mise/tasks/search" <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
printf '%s\n' "$usage_args"
BASH

  run codebase lint:variadic-args "$TARGET" "$clean"

  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  repo"* ]]
  [[ "$output" == *"OK    clean repo"* ]]
}

@test "reports each failing target in the exit status" {
  local other="$BATS_TEST_TMPDIR/other"
  mkdir -p "$other/.mise/tasks"
  write_task search <<'BASH'
#!/usr/bin/env bash
#USAGE arg "[args]" var=#true
eval "ARGS=(${usage_args:-})"
BASH
  cp "$TARGET/.mise/tasks/search" "$other/.mise/tasks/search"

  run codebase lint:variadic-args "$TARGET" "$other"

  [ "$status" -eq 2 ]
}

@test "passes a target with no Mise tasks" {
  rm -rf "$TARGET/.mise/tasks"

  run codebase lint:variadic-args "$TARGET"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no Mise tasks found"* ]]
}

@test "missing and nonexistent targets fail through the public contract" {
  run codebase lint:variadic-args
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required arg"* ]]

  run codebase lint:variadic-args "$TARGET/missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"target does not exist"* ]]
}
