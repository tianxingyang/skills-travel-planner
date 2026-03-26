#!/usr/bin/env bash
set -euo pipefail

REPO="tianxingyang/skills-travel-planner"
BRANCH="main"
TMP=$(mktemp -d)

trap 'rm -rf "$TMP"' EXIT

printf "\n  Downloading travel-planner skill...\n"
curl -fsSL "https://github.com/${REPO}/archive/${BRANCH}.tar.gz" | tar xz -C "$TMP" --strip-components=1

bash "$TMP/install.sh" "$@"
