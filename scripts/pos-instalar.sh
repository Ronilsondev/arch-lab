#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute como usuário normal, sem sudo." >&2
    exit 1
}

modo="${1:---check}"
[[ $# -le 1 && "$modo" =~ ^--(check|apply)$ ]] || {
    echo "Uso: $0 [--check|--apply]" >&2
    exit 1
}

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}"

etapas=(
    scripts/apps/instalar-oficiais.sh
    scripts/apps/instalar-aur-helpers.sh
    scripts/apps/instalar-apps-aur.sh
    scripts/apps/configurar-servicos.sh
    scripts/apps/configurar-musica.sh
    scripts/apps/configurar-yazi.sh
    scripts/apps/instalar-lazyvim.sh
    scripts/aplicar-dotfiles.sh
)

for etapa in "${etapas[@]}"; do
    [[ -f "$repo/$etapa" ]] || {
        echo "Script ausente: $etapa" >&2
        exit 1
    }
    bash -n "$repo/$etapa"
done

echo "Scripts encontrados e sintaxe Bash conferida."
echo "Isso não valida downloads, dependências ou execução em outra máquina."

if [[ "$modo" == "--check" ]]; then
    printf '\nOrdem de execução:\n'
    printf '  %s\n' "${etapas[@]}"
    echo
    echo "Nenhuma alteração feita. Para executar, use --apply."
    exit 0
fi

[[ -z "${NVIM_APPNAME:-}" ]] || {
    echo "Remova NVIM_APPNAME antes de executar." >&2
    exit 1
}

systemctl --user show-environment >/dev/null

etapa="inicialização"
trap 'printf "\nFalha na etapa: %s\nCorrija o erro antes de continuar.\n" "$etapa" >&2' ERR

for etapa in "${etapas[@]}"; do
    if [[ "$etapa" == scripts/apps/instalar-lazyvim.sh &&
          ( -e "$config/nvim" || -L "$config/nvim" ) ]]; then
        echo "Neovim já configurado; instalação preservada."
        continue
    fi

    printf '\n========== %s ==========\n' "$etapa"
    bash "$repo/$etapa"
done

echo
echo "Pós-instalação concluída."
echo "Tailscale: autentique com sudo tailscale up, se necessário."
echo "Syncthing: configure os dispositivos e as pastas na interface."
echo "Confira o desktop e os aplicativos na sessão gráfica."
