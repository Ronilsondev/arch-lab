#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

die() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

modo="${1:---check}"
[[ $# -le 1 ]] || die "Use: $0 [--check|--apply]"
[[ "$modo" == "--check" || "$modo" == "--apply" ]] ||
    die "Use: $0 [--check|--apply]"
[[ $EUID -eq 0 ]] || die "Execute com sudo."

backup=""
trap 'printf "Falha na linha %s. Backup: %s\n" \
    "$LINENO" "${backup:-nenhum; aplicação não iniciada}" >&2' ERR

# Este script atende ao layout já validado do Arch Lab.
for pacote in btrfs-progs snapper snap-pac grub grub-btrfs \
              mkinitcpio inotify-tools; do
    pacman -Q "$pacote" >/dev/null ||
        die "Pacote obrigatório ausente: $pacote"
done

[[ "$(findmnt -nro FSTYPE /)" == "btrfs" ]] ||
    die "A raiz precisa estar em Btrfs, fora do boot por OverlayFS."

[[ "$(findmnt -nro FSROOT /)" == "/@" ]] ||
    die "A raiz precisa usar o subvolume @."

[[ "$(findmnt -nro FSTYPE --mountpoint /home)" == "btrfs" ]] ||
    die "/home precisa ser uma montagem Btrfs."

[[ "$(findmnt -nro FSROOT --mountpoint /home)" == "/@home" ]] ||
    die "/home precisa usar o subvolume @home."

[[ "$(findmnt -nro TARGET -T /boot)" == "/" ]] ||
    die "/boot precisa estar dentro da raiz."

[[ -s /boot/grub/grub.cfg ]] || die "Configuração do GRUB ausente."

findmnt --verify >/dev/null

# Recusa configurações complementares para não ignorar sobrescritas.
shopt -s nullglob
complementos=(/etc/mkinitcpio.conf.d/*.conf)
((${#complementos[@]} == 0)) ||
    die "Há arquivos complementares do mkinitcpio; revise antes."

[[ "$(grep -c '^HOOKS=' /etc/mkinitcpio.conf)" == 1 ]] ||
    die "Esperada uma única linha HOOKS=."

hooks="$(grep '^HOOKS=' /etc/mkinitcpio.conf)"
[[ "$hooks" == *")" ]] || die "HOOKS precisa estar em uma única linha."
[[ "$hooks" =~ (^|[[:space:](])udev([[:space:])]|$) ]] ||
    die "Esta versão exige o hook udev."
[[ ! "$hooks" =~ (^|[[:space:](])systemd([[:space:])]|$) ]] ||
    die "Esta versão não atende ao initramfs com hook systemd."

[[ -f /usr/lib/initcpio/install/grub-btrfs-overlayfs ||
   -f /etc/initcpio/install/grub-btrfs-overlayfs ]] ||
    die "Hook grub-btrfs-overlayfs ausente."

for config in root home; do
    arquivo="/etc/snapper/configs/$config"
    [[ -f "$arquivo" ]] || die "Configuração Snapper ausente: $config"
    snapper -c "$config" get-config >/dev/null
done

grep -qx 'SUBVOLUME="/"' /etc/snapper/configs/root ||
    die "A configuração root não aponta para /."
grep -qx 'SUBVOLUME="/home"' /etc/snapper/configs/home ||
    die "A configuração home não aponta para /home."

btrfs subvolume show /.snapshots >/dev/null
btrfs subvolume show /home/.snapshots >/dev/null

printf 'Verificações aprovadas.\n'
printf 'Será aplicada a retenção do Arch Lab e a integração com GRUB.\n'

if [[ "$modo" == "--check" ]]; then
    printf 'Nenhuma alteração feita. Para aplicar, use --apply.\n'
    exit 0
fi

# Backup dos arquivos que o script modifica ou regenera.
mkdir -p /var/backups
backup="$(mktemp -d /var/backups/arch-lab-snapshots.XXXXXXXX)"
arquivos=(
    /etc/mkinitcpio.conf
    /etc/snapper/configs/root
    /etc/snapper/configs/home
    /etc/default/grub-btrfs/config
    /boot/grub/grub.cfg
)

for opcional in \
    /boot/grub/grub-btrfs.cfg \
    /etc/systemd/system/grub-btrfsd.service.d; do
    [[ ! -e "$opcional" ]] || arquivos+=("$opcional")
done

cp -a --parents "${arquivos[@]}" "$backup/"
printf 'Backup de configurações: %s\n' "$backup"

# Usa a interface do Snapper para preservar as demais opções.
for config in root home; do
    snapper -c "$config" set-config \
        NUMBER_CLEANUP=yes \
        EMPTY_PRE_POST_CLEANUP=yes \
        TIMELINE_CREATE=yes \
        TIMELINE_CLEANUP=yes \
        TIMELINE_LIMIT_HOURLY=6 \
        TIMELINE_LIMIT_DAILY=7 \
        TIMELINE_LIMIT_WEEKLY=2 \
        TIMELINE_LIMIT_MONTHLY=0 \
        TIMELINE_LIMIT_QUARTERLY=0 \
        TIMELINE_LIMIT_YEARLY=0
done

snapper -c root set-config NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
snapper -c home set-config NUMBER_LIMIT=5 NUMBER_LIMIT_IMPORTANT=2

# Adiciona o hook somente se ele ainda não estiver presente.
if [[ ! "$hooks" =~ (^|[[:space:](])grub-btrfs-overlayfs([[:space:])]|$) ]]; then
    sed -i '/^HOOKS=/s/)[[:space:]]*$/ grub-btrfs-overlayfs)/' \
        /etc/mkinitcpio.conf
fi

install -d -m 755 /etc/systemd/system/grub-btrfsd.service.d
cat > /etc/systemd/system/grub-btrfsd.service.d/override.conf <<'UNIT'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots
UNIT

# Reconstrói os arquivos de inicialização antes de ativar os serviços.
mkinitcpio -P
grub-mkconfig -o /boot/grub/grub.cfg
grub-script-check /boot/grub/grub.cfg

systemctl daemon-reload
systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
systemctl enable grub-btrfsd.service
systemctl restart grub-btrfsd.service

systemctl is-active --quiet \
    grub-btrfsd.service \
    snapper-timeline.timer \
    snapper-cleanup.timer

printf '\nConfiguração concluída.\n'
printf 'Backup de configurações: %s\n' "$backup"
printf 'A restauração permanente continua sendo um procedimento separado.\n'
