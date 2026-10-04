#!/usr/bin/env bash
set -euo pipefail

# Escape cancela a seleção sem abrir o editor.
area="$(slurp)" || exit 0
[[ -n "$area" ]] || exit 0

grim -g "$area" - | swappy -f -
