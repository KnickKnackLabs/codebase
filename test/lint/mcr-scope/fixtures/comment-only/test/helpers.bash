#!/usr/bin/env bash
# Historical reference: we used to do source "$MISE_CONFIG_ROOT/lib/foo.sh"
# but now self-locate. The comment mentioning $MISE_CONFIG_ROOT should NOT
# be flagged — full-line comments are stripped by the lint.
#
# Full-line comment with $MISE_CONFIG_ROOT and ${MISE_CONFIG_ROOT:-default}.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
