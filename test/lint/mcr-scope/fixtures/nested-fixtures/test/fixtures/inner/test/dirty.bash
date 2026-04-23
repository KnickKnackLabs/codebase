#!/usr/bin/env bash
# Intentional MCR reference — this is a negative-case fixture for some
# hypothetical nested lint rule. It should NOT trigger mcr-scope when we
# scan the outer repo.
source "$MISE_CONFIG_ROOT/lib/other.sh"
