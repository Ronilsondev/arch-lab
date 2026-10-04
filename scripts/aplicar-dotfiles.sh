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

fontes=(
    "dotfiles/hypr/hyprland.lua"
    "dotfiles/waybar/config.jsonc"
    "dotfiles/waybar/style.css"
    "dotfiles/fuzzel/fuzzel.ini"
    "scripts/desktop/capturar-tela.sh"
)

destinos=(
    "$config/hypr/hyprland.lua"
    "$config/waybar/config.jsonc"
    "$config/waybar/style.css"
    "$config/fuzzel/fuzzel.ini"
    "$HOME/.local/bin/capturar-tela"
)

modos=(600 600 600 600 755)

# Confere todas as fontes e destinos antes de fazer alterações.
for i in "${!fontes[@]}"; do
    [[ -f "$repo/${fontes[$i]}" ]] || {
        echo "Arquivo ausente: ${fontes[$i]}" >&2
        exit 1
    }

    [[ ! -d "${destinos[$i]}" ]] || {
        echo "Destino é um diretório: ${destinos[$i]}" >&2
        exit 1
    }
done

bash -n "$repo/scripts/desktop/capturar-tela.sh"

# As dependências precisam existir para o atalho funcionar.
faltantes=()
for comando in grim slurp swappy wl-copy; do
    command -v "$comando" >/dev/null || faltantes+=("$comando")
done

if ((${#faltantes[@]})); then
    printf 'Comandos ausentes: %s\n' "${faltantes[*]}" >&2
    echo "Instale: sudo pacman -S --needed grim slurp swappy wl-clipboard otf-font-awesome" >&2
    exit 1
fi

umask 077
mkdir -p "$dados/arch-lab/backups"
backup="$(mktemp -d "$dados/arch-lab/backups/dotfiles.XXXXXXXX")"

trap 'printf "Falha. Backup preservado em: %s\n" "$backup" >&2' ERR

# Preserva todos os destinos antes de iniciar a aplicação.
for i in "${!destinos[@]}"; do
    destino="${destinos[$i]}"
    printf '%s\t%s\n' "$i" "$destino" >> "$backup/destinos.tsv"

    if [[ -e "$destino" || -L "$destino" ]]; then
        cp -a -- "$destino" "$backup/arquivo-$i"
    else
        printf '%s\n' "$destino" >> "$backup/arquivos-antes-ausentes.txt"
    fi
done

for i in "${!fontes[@]}"; do
    destino="${destinos[$i]}"
    mkdir -p "$(dirname -- "$destino")"

    # Substitui links sem escrever no arquivo apontado por eles.
    cp --remove-destination -- "$repo/${fontes[$i]}" "$destino"
    chmod "${modos[$i]}" "$destino"

    printf 'Aplicado: %s\n' "$destino"
done

printf '\nBackup: %s\n' "$backup"
printf 'Dotfiles e comando de captura aplicados.\n'
printf 'Nenhum serviço foi reiniciado.\n'
