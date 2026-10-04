#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute como usuário normal, sem sudo." >&2
    exit 1
}

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
dados="${XDG_DATA_HOME:-$HOME/.local/share}"

[[ "$config" == /* && "$dados" == /* ]] || {
    echo "Os diretórios XDG precisam usar caminhos absolutos." >&2
    exit 1
}

arquivos=(
    hypr/hyprland.lua
    waybar/config.jsonc
    waybar/style.css
)

# Verifica todas as fontes antes de alterar qualquer destino.
for arquivo in "${arquivos[@]}"; do
    [[ -f "$repo/dotfiles/$arquivo" ]] || {
        echo "Arquivo ausente: dotfiles/$arquivo" >&2
        exit 1
    }

    destino="$config/$arquivo"
    if [[ -d "$destino" ]]; then
        echo "Destino é um diretório; revise: $destino" >&2
        exit 1
    fi
done

umask 077
mkdir -p "$dados/arch-lab/backups"
backup="$(mktemp -d "$dados/arch-lab/backups/dotfiles.XXXXXXXX")"

trap 'printf "Falha. Backup preservado em: %s\n" "$backup" >&2' ERR

# Guarda todos os arquivos existentes antes de iniciar as cópias.
for arquivo in "${arquivos[@]}"; do
    destino="$config/$arquivo"
    if [[ -e "$destino" || -L "$destino" ]]; then
        mkdir -p "$backup/$(dirname "$arquivo")"
        cp -a -- "$destino" "$backup/$arquivo"
    else
        printf '%s\n' "$arquivo" >> "$backup/arquivos-antes-ausentes.txt"
    fi
done

for arquivo in "${arquivos[@]}"; do
    destino="$config/$arquivo"
    mkdir -p "$(dirname "$destino")"

    # Substitui o arquivo ou link, sem escrever no alvo de um link.
    cp --remove-destination -- \
        "$repo/dotfiles/$arquivo" "$destino"

    printf 'Aplicado: %s\n' "$destino"
done

printf '\nBackup: %s\n' "$backup"
printf 'Dotfiles aplicados. Nenhum serviço foi reiniciado.\n'
