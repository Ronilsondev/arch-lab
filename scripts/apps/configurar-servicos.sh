#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute como usuário normal, sem sudo." >&2
    exit 1
}

# Confere o acesso ao systemd do usuário antes de instalar.
systemctl --user show-environment >/dev/null

sudo pacman -S --needed syncthing tailscale

systemctl --user daemon-reload
systemctl --user enable --now syncthing.service

sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled.service

echo
echo "Syncthing:"
systemctl --user is-active syncthing.service

echo "Tailscale:"
systemctl is-active tailscaled.service

echo
echo "Serviços ativados."
echo "Syncthing: http://127.0.0.1:8384 no navegador da VM."
echo "Para conectar o Tailscale à sua conta: sudo tailscale up"
