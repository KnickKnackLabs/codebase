#!/usr/bin/env bash
# Brace-form references must also be flagged — all bash parameter-expansion
# operators, not just ':-' and ':+'.
: "${MISE_CONFIG_ROOT:-default}"
echo "${MISE_CONFIG_ROOT}"
FOO="${MISE_CONFIG_ROOT:+set}"
DIR="${MISE_CONFIG_ROOT%/*}"         # suffix removal (dirname trick)
PFX="${MISE_CONFIG_ROOT#/Users/}"    # prefix removal
SUB="${MISE_CONFIG_ROOT/old/new}"    # substitution
