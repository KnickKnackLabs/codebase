#!/usr/bin/env bash
# Bad: uses MCR directly in a test helper.
if [ -z "${MISE_CONFIG_ROOT:-}" ]; then
  echo "run via mise" >&2
  exit 1
fi
source "$MISE_CONFIG_ROOT/lib/foo.sh"
