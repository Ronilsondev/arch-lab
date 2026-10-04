#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute sem sudo." >&2
    exit 1
}

command -v paru >/dev/null || {
    echo "Instale o Paru primeiro." >&2
    exit 1
}

pacotes=(
    onlyoffice-bin
    yandex-browser
    brave-bin
    visual-studio-code-bin
)

# Confirma que os pacotes podem ser consultados antes da instalação.
for pacote in "${pacotes[@]}"; do
    paru -Si "$pacote"
done

paru -S --needed "${pacotes[@]}"

echo "Instalação concluída."
