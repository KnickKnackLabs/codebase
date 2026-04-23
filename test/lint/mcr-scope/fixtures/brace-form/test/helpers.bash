#!/usr/bin/env bash
# Brace-form references must also be flagged.
: "${MISE_CONFIG_ROOT:-default}"
echo "${MISE_CONFIG_ROOT}"
FOO="${MISE_CONFIG_ROOT:+set}"
