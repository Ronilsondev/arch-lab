#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute como usuário normal, sem sudo." >&2
    exit 1
}

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
config="${YAZI_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/yazi}"

[[ "$config" == /* ]] || {
    echo "O caminho de configuração precisa ser absoluto." >&2
    exit 1
}

arquivos=(yazi.toml theme.toml package.toml)

for arquivo in "${arquivos[@]}"; do
    test -s "$repo/dotfiles/yazi/$arquivo" || {
        echo "Arquivo ausente: dotfiles/yazi/$arquivo" >&2
        exit 1
    }
done

sudo pacman -S --needed \
    yazi git imv mpv ark okular neovim xdg-utils \
    ffmpeg 7zip jq poppler fd ripgrep fzf \
    imagemagick wl-clipboard ttf-jetbrains-mono-nerd

mkdir -p "$HOME/.local/share/arch-lab/backups"
backup="$(mktemp -d "$HOME/.local/share/arch-lab/backups/yazi.XXXXXXXX")"

if [[ -d "$config" ]]; then
    cp -a "$config/." "$backup/"
fi

echo "Backup: $backup"

mkdir -p "$config"

for arquivo in "${arquivos[@]}"; do
    cp --remove-destination -- \
        "$repo/dotfiles/yazi/$arquivo" "$config/$arquivo"
done

YAZI_CONFIG_HOME="$config" ya pkg install

echo "Configuração e tema do Yazi instalados."
echo "Abra o Yazi dentro do Kitty para conferir."
