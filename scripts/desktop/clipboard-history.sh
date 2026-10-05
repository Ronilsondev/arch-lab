#!/usr/bin/env bash
set -euo pipefail

item="$(cliphist list | fuzzel --dmenu)" || exit 0
[[ -n "$item" ]] || exit 0

printf '%s\n' "$item" | cliphist decode | wl-copy
