#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute como usuário normal, sem sudo." >&2
    exit 1
}

[[ -z "${NVIM_APPNAME:-}" ]] || {
    echo "Remova NVIM_APPNAME do ambiente antes de executar." >&2
    exit 1
}

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
origem="$repo/dotfiles/nvim"

config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
dados="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
estado="${XDG_STATE_HOME:-$HOME/.local/state}/nvim"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"

for arquivo in init.lua lazy-lock.json lua/plugins/colorscheme.lua; do
    [[ -s "$origem/$arquivo" ]] || {
        echo "Arquivo necessário ausente: $origem/$arquivo" >&2
        exit 1
    }
done

if [[ -e "$config" || -L "$config" ]]; then
    echo "Já existe uma configuração em: $config"
    echo "Nenhuma alteração feita."
    exit 1
fi

sudo pacman -S --needed \
    neovim git base-devel curl unzip \
    tree-sitter-cli ripgrep fd fzf lazygit \
    wl-clipboard ttf-jetbrains-mono-nerd

mkdir -p "$HOME/.local/share/arch-lab/backups"
backup="$(mktemp -d "$HOME/.local/share/arch-lab/backups/lazyvim.XXXXXXXX")"

trap 'printf "Falha na linha %s. Backup preservado: %s\n" "$LINENO" "$backup" >&2' ERR

for tipo in dados estado cache; do
    caminho="${!tipo}"
    if [[ -e "$caminho" || -L "$caminho" ]]; then
        mv -- "$caminho" "$backup/$tipo"
    fi
done

mkdir -p "$(dirname -- "$config")"
mkdir -- "$config"
cp -a -- "$origem/." "$config/"

echo "LazyVim com Rosé Pine preparado."
echo "Configuração: $config"
echo "Backup: $backup"
echo "Abra nvim e aguarde a instalação dos plugins."
echo "Depois execute :Lazy restore para aplicar as revisões do lazy-lock.json."
