#!/usr/bin/env bash
# Clean lib — self-locates via BASH_SOURCE.
_FOO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_FOO_DIR/bar.sh"
