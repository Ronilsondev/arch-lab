#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute como usuário normal, sem sudo." >&2
    exit 1
}

pacotes=(
    # Imagem, documentos e anotações
    inkscape gimp obsidian okular imv kate

    # Internet
    qbittorrent telegram-desktop torbrowser-launcher

    # Multimídia
    vlc vlc-plugins-all mpv
    mpd mpc ncmpcpp cava

    # Arquivos e monitoramento
    yazi ark btop htop

    # Sincronização e acesso remoto
    syncthing tailscale

    # Capturas de tela
    grim slurp swappy wl-clipboard otf-font-awesome

    # Editor e documentos LaTeX
    neovim texstudio
    texlive-latexrecommended texlive-latexextra
    texlive-fontsrecommended texlive-langportuguese
    biber
)

# Atualiza o sistema e instala os pacotes na mesma transação.
sudo pacman -Syu --needed "${pacotes[@]}"

echo
echo "Instalação dos pacotes oficiais concluída."
echo "Os serviços são configurados por configurar-servicos.sh"
echo "e configurar-musica.sh."
