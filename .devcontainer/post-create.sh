#!/usr/bin/env bash
set -euo pipefail

# Project venv at <workspace>/.venv, matches containerEnv VIRTUAL_ENV in devcontainer.json.
python3 -m venv "${PWD}/.venv"
"${PWD}/.venv/bin/pip" install --upgrade pip
"${PWD}/.venv/bin/pip" install pre-commit

# Cache pre-commit hook envs upfront so first commit isn't slow.
"${PWD}/.venv/bin/pre-commit" install --install-hooks || true

# Install pi-coding-agent.
# npm install -g --ignore-scripts @earendil-works/pi-coding-agent
