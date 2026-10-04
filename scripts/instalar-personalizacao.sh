#!/usr/bin/env bash
# Arch Lab: Plymouth Starlord, SDDM Pixel Sakura e bloqueio Field.
# Execute como usuário normal dentro da conta que usará o Hyprland.
set -Eeuo pipefail
umask 022

die() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -ne 0 ]] || die "Execute sem sudo; ele será solicitado."
[[ -f /etc/arch-release ]] || die "Este script atende ao Arch Linux."

for comando in git sudo awk sed mkinitcpio grub-mkconfig grub-script-check; do
    command -v "$comando" >/dev/null ||
        die "Comando obrigatório ausente: $comando"
done

[[ -s /etc/mkinitcpio.conf && -s /etc/default/grub ]] ||
    die "Configuração de boot não encontrada."
[[ -s /boot/grub/grub.cfg ]] || die "GRUB ainda não configurado."
[[ -f /usr/lib/systemd/system/sddm.service ]] ||
    die "Instale e configure o SDDM primeiro."

# Recusa configurações adicionais que poderiam sobrescrever HOOKS.
shopt -s nullglob
complementos=(/etc/mkinitcpio.conf.d/*.conf)
((${#complementos[@]} == 0)) ||
    die "Revise os arquivos complementares do mkinitcpio primeiro."

[[ "$(grep -c '^HOOKS=' /etc/mkinitcpio.conf)" == 1 ]] ||
    die "Esperada uma linha HOOKS=."
hooks="$(grep '^HOOKS=' /etc/mkinitcpio.conf)"

[[ "$hooks" =~ ^HOOKS=\([a-zA-Z0-9_\ -]+\)$ ]] ||
    die "Formato de HOOKS não atendido por este script."

[[ "$hooks" =~ (^|[[:space:](])udev([[:space:])]|$) ]] ||
    die "Este script exige o hook udev."
[[ ! "$hooks" =~ (^|[[:space:](])systemd([[:space:])]|$) ]] ||
    die "Initramfs com hook systemd não atendido nesta versão."

# /etc/sddm.conf tem precedência sobre sddm.conf.d.
if [[ -f /etc/sddm.conf ]] &&
   grep -Eq '^[[:space:]]*Current[[:space:]]*=' /etc/sddm.conf; then
    die "Há Current em /etc/sddm.conf; revise antes de usar o drop-in."
fi

plymouth_rev="2c2af3f688f55edffe55c35d551436cc6e0f33f9"
qylock_rev="f6561e2ceae33f26e5e660742a5df2f725cbe514"

tmp="$(mktemp -d)"
backup=""
backup_usuario=""

limpar() {
    codigo=$?
    trap - EXIT
    rm -rf -- "$tmp"
    if ((codigo != 0)); then
        printf '\nInstalação interrompida; sem desfazer automático.\n' >&2
        printf 'Backup do sistema: %s\n' "${backup:-não criado}" >&2
        printf 'Backup do usuário: %s\n' "${backup_usuario:-não criado}" >&2
    fi
    exit "$codigo"
}
trap limpar EXIT

baixar() {
    local url="$1" revisao="$2" destino="$3"
    local cache=""
    local candidato
    local -a candidatos=()

    case "$url" in
        */Plymouth-Themes.git)
            candidatos=("$HOME"/Downloads/plymouth-starlord.*/repositorio)
            ;;
        */qylock.git)
            candidatos=("$HOME"/Downloads/qylock.*/repositorio)
            ;;
    esac

    for candidato in "${candidatos[@]}"; do
        if git -C "$candidato" cat-file -e "$revisao^{commit}" 2>/dev/null; then
            cache="$candidato"
            break
        fi
    done

    if [[ -n "$cache" ]]; then
        printf 'Usando revisão local de: %s\n' "$cache"
        mkdir -p "$destino"
        git -C "$cache" archive "$revisao" |
            tar -x -C "$destino"
    else
        printf 'Baixando: %s\n' "$url"
        git init -q "$destino"
        git -C "$destino" remote add origin "$url"
        git -C "$destino" fetch --progress --depth 1 origin "$revisao"
        git -C "$destino" checkout --detach FETCH_HEAD

        [[ "$(git -C "$destino" rev-parse HEAD)" == "$revisao" ]] ||
            die "Revisão inesperada em $url"
    fi
}

baixar "https://github.com/MrVivekRajan/Plymouth-Themes.git" \
    "$plymouth_rev" "$tmp/plymouth"

baixar "https://github.com/Darkkal44/qylock.git" \
    "$qylock_rev" "$tmp/qylock"

test -s "$tmp/plymouth/Starlord/Starlord.plymouth"
test -s "$tmp/plymouth/Starlord/Starlord.script"
test -s "$tmp/qylock/themes/pixel-sakura/Main.qml"
test -s "$tmp/qylock/themes/field/Main.qml"
test -s "$tmp/qylock/quickshell-lockscreen/lock.sh"

# Prepara a nova configuração preservando os demais hooks.
awk '
    /^HOOKS=/ {
        linha = $0
        sub(/^HOOKS=\(/, "", linha)
        sub(/\)$/, "", linha)
        n = split(linha, itens, /[[:space:]]+/)
        printf "HOOKS=("
        sep = ""
        for (i = 1; i <= n; i++) {
            if (itens[i] == "" || itens[i] == "plymouth")
                continue
            printf "%s%s", sep, itens[i]
            sep = " "
            if (itens[i] == "udev")
                printf " plymouth"
        }
        print ")"
        next
    }
    { print }
' /etc/mkinitcpio.conf > "$tmp/mkinitcpio.conf"

# Exige uma atribuição simples, entre aspas duplas.
# Recusa expressões de shell para não interpretá-las.
awk '
    /^GRUB_CMDLINE_LINUX_DEFAULT=/ {
        quantidade++
        if ($0 !~ /^GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"$/) {
            invalido = 1
            next
        }
        valor = $0
        sub(/^GRUB_CMDLINE_LINUX_DEFAULT="/, "", valor)
        sub(/"$/, "", valor)
        if (valor ~ /[$`\\]/) {
            invalido = 1
            next
        }
        n = split(valor, itens, /[[:space:]]+/)
        quiet = splash = 0
        for (i = 1; i <= n; i++) {
            if (itens[i] == "quiet") quiet = 1
            if (itens[i] == "splash") splash = 1
        }
        if (!quiet) valor = valor " quiet"
        if (!splash) valor = valor " splash"
        print "GRUB_CMDLINE_LINUX_DEFAULT=\"" valor "\""
        next
    }
    { print }
    END {
        if (quantidade != 1 || invalido)
            exit 1
    }
' /etc/default/grub > "$tmp/grub" ||
    die "Formato de GRUB_CMDLINE_LINUX_DEFAULT não atendido."

sudo -v
sudo mkdir -p /var/backups
backup="$(sudo mktemp -d /var/backups/arch-lab-visual.XXXXXXXX)"

for arquivo in \
    /etc/mkinitcpio.conf \
    /etc/default/grub \
    /etc/plymouth \
    /etc/sddm.conf.d/90-arch-lab-theme.conf \
    /usr/share/plymouth/themes/Starlord \
    /usr/share/sddm/themes/pixel-sakura \
    /boot/grub/grub.cfg \
    /boot/grub/grub-btrfs.cfg; do
    if sudo test -e "$arquivo"; then
        sudo cp -a --parents "$arquivo" "$backup/"
    fi
done

mkdir -p "$HOME/.local/share" "$HOME/.config/qylock"
backup_usuario="$(mktemp -d "$HOME/.local/share/arch-lab-visual-backup.XXXXXXXX")"

destino_field="$HOME/.local/share/quickshell-lockscreen"

if [[ -e "$destino_field" ]]; then
    cp -a "$destino_field" "$backup_usuario/quickshell-lockscreen"
fi
if [[ -f "$HOME/.config/qylock/theme" ]]; then
    cp -a "$HOME/.config/qylock/theme" "$backup_usuario/theme"
fi

printf 'Backup do sistema: %s\n' "$backup"
printf 'Backup do usuário: %s\n' "$backup_usuario"

sudo pacman -S --needed \
    plymouth quickshell qt6-declarative qt6-5compat qt6-svg \
    qt6-multimedia qt6-multimedia-ffmpeg

# Preserva diretórios anteriores antes de instalar cópias novas.
sudo mkdir -p /usr/share/plymouth/themes /usr/share/sddm/themes

if sudo test -e /usr/share/plymouth/themes/Starlord; then
    sudo mv /usr/share/plymouth/themes/Starlord "$backup/Starlord-anterior"
fi
if sudo test -e /usr/share/sddm/themes/pixel-sakura; then
    sudo mv /usr/share/sddm/themes/pixel-sakura "$backup/sakura-anterior"
fi

sudo cp -a "$tmp/plymouth/Starlord" /usr/share/plymouth/themes/
sudo cp -a "$tmp/qylock/themes/pixel-sakura" /usr/share/sddm/themes/

sudo chown -R root:root \
    /usr/share/plymouth/themes/Starlord \
    /usr/share/sddm/themes/pixel-sakura

sudo chmod -R u=rwX,go=rX \
    /usr/share/plymouth/themes/Starlord \
    /usr/share/sddm/themes/pixel-sakura

if [[ -e "$destino_field" ]]; then
    mv "$destino_field" "$backup_usuario/field-anterior"
fi

cp -a "$tmp/qylock/quickshell-lockscreen" "$destino_field"
mkdir -p "$destino_field/themes_link"
cp -a "$tmp/qylock/themes/field" "$destino_field/themes_link/field"

sed -i '/^killall -9 hyprlock swaylock wlogout /d' \
    "$destino_field/lock.sh"

sed -i 's/pam\.user = user;/pam.user = Quickshell.env("USER");/' \
    "$destino_field/shim/SddmShim.qml"

printf 'field\n' > "$HOME/.config/qylock/theme"
chmod +x "$destino_field/lock.sh"
bash -n "$destino_field/lock.sh"

sudo install -m 644 "$tmp/mkinitcpio.conf" /etc/mkinitcpio.conf
sudo install -m 644 "$tmp/grub" /etc/default/grub

sudo mkdir -p /etc/sddm.conf.d
printf '[Theme]\nCurrent=pixel-sakura\n' |
    sudo tee /etc/sddm.conf.d/90-arch-lab-theme.conf >/dev/null

sudo plymouth-set-default-theme Starlord
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub.cfg

printf '\nInstalação concluída. Nenhum serviço gráfico foi reiniciado.\n'
printf 'Bloqueio: %s/lock.sh field\n' "$destino_field"
printf 'O atalho deve estar na configuração do Hyprland.\n'
printf 'Confira login e bloqueio antes de considerar outra máquina validada.\n'
