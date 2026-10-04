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

config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
dados="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
estado="${XDG_STATE_HOME:-$HOME/.local/state}/nvim"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"

# Evita substituir uma configuração personalizada em outra execução.
if [[ -e "$config" || -L "$config" ]]; then
    echo "Já existe uma configuração em: $config"
    echo "Nenhuma alteração feita. Revise antes de reinstalar."
    exit 1
fi

sudo pacman -S --needed \
    neovim git base-devel curl unzip \
    tree-sitter-cli ripgrep fd fzf lazygit \
    wl-clipboard ttf-jetbrains-mono-nerd

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

git clone --depth 1 --progress \
    https://github.com/LazyVim/starter.git "$tmp/starter"

revisao="$(git -C "$tmp/starter" rev-parse HEAD)"
test -s "$tmp/starter/init.lua"

mkdir -p "$HOME/.local/share/arch-lab/backups"
backup="$(mktemp -d "$HOME/.local/share/arch-lab/backups/lazyvim.XXXXXXXX")"

printf '%s\n' "$revisao" > "$backup/starter-revision.txt"

for tipo in dados estado cache; do
    caminho="${!tipo}"
    if [[ -e "$caminho" || -L "$caminho" ]]; then
        mv -- "$caminho" "$backup/$tipo"
    fi
done

mkdir -p "$(dirname "$config")"
mkdir "$config"

# Exporta apenas arquivos versionados, sem o histórico Git do starter.
git -C "$tmp/starter" archive HEAD | tar -x -C "$config"

echo "LazyVim preparado."
echo "Revisão do starter: $revisao"
echo "Backup: $backup"
echo "Abra nvim para baixar os plugins."
