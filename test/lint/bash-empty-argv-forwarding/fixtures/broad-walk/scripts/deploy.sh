#!/usr/bin/env bash
set -euo pipefail
rsync "$@" deploy@example.com:/srv/app/
