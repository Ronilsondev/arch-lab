#!/usr/bin/env bash
# Instala a revisão do SekiroShadow validada no Arch Lab.
set -Eeuo pipefail
umask 022

die() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -ne 0 ]] ||
    die "Execute como usuário normal. O script solicitará sudo."

for comando in git sudo grub-mkconfig grub-script-check; do
    command -v "$comando" >/dev/null ||
        die "Comando necessário ausente: $comando"
done

[[ -f /etc/default/grub && -s /boot/grub/grub.cfg ]] ||
    die "Esperado GRUB já configurado em /boot/grub."

# GRUB_TERMINAL pode sobrescrever GRUB_TERMINAL_OUTPUT.
if grep -Eq '^[[:space:]]*GRUB_TERMINAL=' /etc/default/grub; then
    die "Há uma configuração GRUB_TERMINAL ativa; revise antes."
fi

repositorio="https://github.com/MrVivekRajan/Grub-Themes.git"
revisao="cefbbf6a13b9bb3405c66219a5b4ead5d4f31fca"
tmp="$(mktemp -d)"
backup=""

limpar() {
    codigo=$?
    trap - EXIT
    rm -rf -- "$tmp"
    if ((codigo != 0)); then
        printf 'Instalação interrompida.\n' >&2
        if [[ -n "$backup" ]]; then
            printf 'Backup preservado em: %s\n' "$backup" >&2
            printf 'Confira o erro antes de reiniciar.\n' >&2
        fi
    fi
    exit "$codigo"
}
trap limpar EXIT

git init -q "$tmp/repositorio"
git -C "$tmp/repositorio" remote add origin "$repositorio"
git -C "$tmp/repositorio" fetch --depth 1 origin "$revisao"
git -C "$tmp/repositorio" checkout --detach FETCH_HEAD

[[ "$(git -C "$tmp/repositorio" rev-parse HEAD)" == "$revisao" ]] ||
    die "A revisão baixada não corresponde à esperada."

origem="$tmp/repositorio/SekiroShadow"
[[ -d "$origem" && ! -L "$origem" ]] ||
    die "Pasta do tema ausente ou inválida."

[[ -z "$(find "$origem" -type l -print -quit)" ]] ||
    die "O tema contém links simbólicos; revise antes."

mapfile -d '' -t temas < <(
    find "$origem" -type f -name theme.txt -print0
)
[[ ${#temas[@]} -eq 1 ]] ||
    die "Esperado exatamente um theme.txt."

relativo="${temas[0]#"$origem"/}"
[[ "$relativo" =~ ^[a-zA-Z0-9._/-]+$ ]] ||
    die "Caminho do theme.txt não previsto."

sudo -v
sudo install -d -m 755 /var/backups /boot/grub/themes

backup="$(sudo mktemp -d /var/backups/grub-theme.XXXXXXXX)"
sudo cp -a /etc/default/grub "$backup/default-grub"
sudo cp -a /boot/grub/grub.cfg "$backup/grub.cfg"

if sudo test -f /boot/grub/grub-btrfs.cfg; then
    sudo cp -a /boot/grub/grub-btrfs.cfg "$backup/"
fi

printf 'Backup: %s\n' "$backup"

# Pasta exclusiva: preserva temas de instalações anteriores.
destino="$(sudo mktemp -d /boot/grub/themes/SekiroShadow.XXXXXXXX)"
sudo cp -a "$origem/." "$destino/"
sudo chown -R root:root "$destino"
sudo chmod -R u=rwX,go=rX "$destino"

# Preserva as outras opções, inclusive timeout e resolução.
sudo sed -i \
    '/^[[:space:]]*GRUB_THEME=/d;
     /^[[:space:]]*GRUB_TERMINAL_OUTPUT=/d' \
    /etc/default/grub

printf '\nGRUB_THEME="%s"\nGRUB_TERMINAL_OUTPUT=gfxterm\n' \
    "$destino/$relativo" |
    sudo tee -a /etc/default/grub >/dev/null

sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub.cfg

printf '\nSekiroShadow instalado.\n'
printf 'Revisão: %s\nBackup: %s\n' "$revisao" "$backup"
printf 'A aparência deve ser conferida no próximo boot.\n'
