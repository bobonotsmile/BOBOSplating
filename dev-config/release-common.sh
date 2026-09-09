#!/usr/bin/env bash
# Sourced by scripts at the release root, after they cd to their own directory.
set -euo pipefail
export COMPOSE_DISABLE_ENV_FILE=0
unset COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_ENV_FILES
[[ -f .env && -f compose.yml ]] || { echo 'Missing .env or compose.yml' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'python3 is required' >&2; exit 1; }
docker compose config -q
cfg() { python3 publish-config/release-config.py "$1"; }
cfg --validate
