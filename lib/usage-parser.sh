#!/usr/bin/env bash
# Shared helpers for parsing #USAGE directives in .mise/tasks files.
#
# Source from .mise/tasks/lint/* (task context):
#   # shellcheck source=../../lib/usage-parser.sh
#   source "$MISE_CONFIG_ROOT/lib/usage-parser.sh"
#
# MISE_CONFIG_ROOT is the right primitive here — mise dispatched the task, so
# it's set correctly. Do NOT source this file from test helpers or other lib
# files using $MISE_CONFIG_ROOT; see fold/notes/mise-gotchas.md.

# usage_flag_name <directive_text>
#
# Given a #USAGE flag directive like '#USAGE flag "-e --exclude <pattern>"',
# extract the long flag name with -- prefix. Returns empty if no long flag.
#
# Examples:
#   '#USAGE flag "--verbose"'         → "--verbose"
#   '#USAGE flag "--model <model>"'   → "--model"
#   '#USAGE flag "-e --exclude <x>"'  → "--exclude"
#   '#USAGE flag "-e"'                → ""
usage_flag_name() {
  local directive="$1"
  # Match a '--' word. The long flag appears before any placeholder.
  if [[ "$directive" =~ --([a-zA-Z0-9_-]+) ]]; then
    printf '%s\n' "--${BASH_REMATCH[1]}"
  fi
}

# usage_placeholder <directive_text>
#
# Given a #USAGE flag directive, extract the arg placeholder <...> text
# (without angle brackets). Returns empty if no placeholder.
#
# Examples:
#   '#USAGE flag "--model <model>"'   → "model"
#   '#USAGE flag "--exclude <x>"'     → "x"
#   '#USAGE flag "--verbose"'         → ""
usage_placeholder() {
  local directive="$1"
  if [[ "$directive" =~ '<'([a-zA-Z0-9_-]+)'>' ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

# usage_env_name <flag_or_placeholder_name>
#
# Convert a flag name (with --) or placeholder name to the mise usage_* env var
# name: strip leading --, replace hyphens with underscores.
#
# Examples:
#   "--exclude"     → "usage_exclude"
#   "excludes"      → "usage_excludes"
#   "file-path"     → "usage_file_path"
usage_env_name() {
  local name="$1"
  # Strip leading -- if present
  name="${name#--}"
  # Replace hyphens with underscores (mise normalises hyphens to underscores)
  name="${name//-/_}"
  printf 'usage_%s\n' "$name"
}

# parse_usage_flags <task_file>
#
# Read a task file and emit tab-separated lines of the form:
#   <line_number>\t<flag_name>\t<placeholder>
# for each #USAGE flag directive found.
#
# - Empty placeholder means boolean flag (no arg).
# - Empty flag_name means short-only flag (e.g. -v, no --long form).
# - Lines with codebase:ignore are skipped (respect inline opt-out).
#
# Output is tab-separated for reliable parsing with IFS=$'\t' read -r.
parse_usage_flags() {
  local file="$1"
  local lineno=0
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))

    # Non-directive lines are skipped
    [[ "$line" != *"#USAGE flag"* ]] && continue

    # Inline opt-out
    [[ "$line" == *"codebase:ignore"* ]] && continue

    local flag_name
    local placeholder

    flag_name=$(usage_flag_name "$line")
    placeholder=$(usage_placeholder "$line")

    # Skip short-only flags (no long name) — nothing to compare
    [[ -z "$flag_name" ]] && continue

    printf '%s\t%s\t%s\n' "$lineno" "$flag_name" "$placeholder"
  done < "$file"
}

# discover_task_files <target>
#
# Emit paths of task files under <target>/.mise/tasks/, one per line.
# Excludes subdirectories named fixtures/ (lint-rule fixtures intentionally
# contain synthetic patterns that should not trigger self-flagging during
# self-hosting scans).
discover_task_files() {
  local target="$1"
  local tasks_dir="$target/.mise/tasks"

  if [[ ! -d "$tasks_dir" ]]; then
    return
  fi

  fd --type f --exclude fixtures . "$tasks_dir" 2>/dev/null || true
}
