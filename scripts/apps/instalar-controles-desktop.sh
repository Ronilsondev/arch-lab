#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute como usuário normal, sem sudo." >&2
    exit 1
}

command -v paru >/dev/null || {
    echo "Instale o Paru usando instalar-aur-helpers.sh." >&2
    exit 1
}

sudo pacman -S --needed pavucontrol network-manager-applet swaybg

paru -S --needed hyprfm-git hyprmod waypaper

echo
echo "Instalação concluída."
echo "Abra no Hyprland:"
echo "  hyprfm               — arquivos"
echo "  hyprmod              — configurações e monitores"
echo "  pavucontrol          — áudio"
echo "  nm-connection-editor — conexões de rede"
