#!/usr/bin/env bash
set -euo pipefail

opcao="$(printf 'Bloquear\nReiniciar\nDesligar\n' |
    fuzzel --dmenu --prompt 'Energia: ')" || exit 0

case "$opcao" in
    Bloquear)
        exec "$HOME/.local/share/quickshell-lockscreen/lock.sh" field
        ;;
    Reiniciar|Desligar)
        resposta="$(printf 'Cancelar\nConfirmar\n' |
            fuzzel --dmenu --prompt "$opcao? ")" || exit 0
        [[ "$resposta" == "Confirmar" ]] || exit 0

        if [[ "$opcao" == "Reiniciar" ]]; then
            systemctl reboot
        else
            systemctl poweroff
        fi
        ;;
esac
