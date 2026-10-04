#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute sem sudo." >&2
    exit 1
}

sudo pacman -S --needed git base-devel

if ! command -v yay >/dev/null; then
    mkdir -p "$HOME/.cache/arch-lab"
    trabalho="$(mktemp -d "$HOME/.cache/arch-lab/yay.XXXXXXXX")"

    echo "Arquivos de construção: $trabalho"

    git clone --depth 1 --progress \
        https://aur.archlinux.org/yay.git "$trabalho/yay"

    cd "$trabalho/yay"

    echo
    echo "Receita de construção do Yay:"
    cat PKGBUILD

    echo
    read -r -p "Construir e instalar o Yay? [s/N] " resposta
    [[ "$resposta" =~ ^[sS]$ ]] || {
        echo "Instalação cancelada."
        exit 1
    }

    makepkg -si
fi

yay --version

if ! command -v paru >/dev/null; then
    yay -S --needed paru
fi

paru --version
echo "Yay e Paru disponíveis."
