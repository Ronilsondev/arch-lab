#!/usr/bin/env bash
# Recuperação pela ISO oficial do Arch — layout específico do Arch Lab.
set -Eeuo pipefail
export LC_ALL=C
umask 077

die() {
    printf 'ERRO: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "Execute como root na ISO do Arch."
[[ $# == 2 ]] || die "Uso: $0 NUMERO --check|--apply"

numero="$1"
modo="$2"
[[ "$numero" =~ ^[1-9][0-9]*$ ]] || die "Número inválido."
[[ "$modo" == "--check" || "$modo" == "--apply" ]] ||
    die "Modo inválido."

[[ -d /run/archiso ]] ||
    die "Execute pela ISO do Arch, não pelo sistema instalado."

for comando in btrfs blkid findmnt mount umount arch-chroot \
               readlink mktemp grep awk; do
    command -v "$comando" >/dev/null ||
        die "Comando ausente: $comando"
done

# UUID do Btrfs deste laboratório. Não aponta para qualquer disco.
uuid="25050944-777b-408a-80e5-8ad029adc536"
dispositivo="$(readlink -f "/dev/disk/by-uuid/$uuid")"
[[ -b "$dispositivo" ]] || die "Disco do laboratório não encontrado."
[[ "$(blkid -s TYPE -o value "$dispositivo")" == btrfs ]] ||
    die "O dispositivo não é Btrfs."

montados="$(findmnt -rn -t btrfs -o UUID || true)"
if grep -Fxq "$uuid" <<< "$montados"; then
    die "O Btrfs já está montado. Desmonte suas montagens antes."
fi

trabalho="$(mktemp -d /mnt/arch-lab-restauracao.XXXXXXXX)"
topo="$trabalho/btrfs"
sistema="$trabalho/sistema"
mkdir "$topo" "$sistema"

alterando=0
concluido=0
fase="verificação"

ao_sair() {
    codigo=$?
    trap - EXIT
    if ((alterando == 1 && concluido == 0)); then
        printf '\nRESTAURAÇÃO INTERROMPIDA: %s\n' "$fase" >&2
        printf 'Não reinicie nem execute novamente o script.\n' >&2
        printf 'Montagens e arquivos preservados em %s\n' "$trabalho" >&2
        printf 'Raiz anterior planejada: %s\n' "$anterior" >&2
        printf 'Raiz temporária planejada: %s\n' "$nova" >&2
    else
        if mountpoint -q "$sistema"; then
            umount -R "$sistema" || codigo=1
        fi
        if mountpoint -q "$topo"; then
            umount "$topo" || codigo=1
        fi
        if ((codigo != 0)); then
            printf 'Confira o erro acima antes de continuar.\n' >&2
        fi
    fi
    exit "$codigo"
}
trap ao_sair EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Conferência sem escrita nem replay do log Btrfs.
mount -o ro,nologreplay,subvolid=5 "$dispositivo" "$topo"

raiz="$topo/@"
snapshot="$raiz/.snapshots/$numero/snapshot"
aninhados=(.snapshots var/lib/portables var/lib/machines)

# Recusa caminhos com symlinks para evitar atingir outra localização.
caminho_real() {
    [[ "$(readlink -f -- "$1")" == "$1" ]] ||
        die "Caminho inesperado ou com link simbólico: $1"
}

for subvolume in @ @home @log @pkg; do
    caminho_real "$topo/$subvolume"
    btrfs subvolume show "$topo/$subvolume" >/dev/null
done

caminho_real "$snapshot"
btrfs subvolume show "$snapshot" >/dev/null
[[ "$(btrfs property get "$snapshot" ro)" == "ro=true" ]] ||
    die "O snapshot escolhido precisa ser somente leitura."

shopt -s nullglob
pendentes=("$topo"/@restaurando-*)
((${#pendentes[@]} == 0)) ||
    die "Existe uma restauração temporária pendente; revise primeiro."

for relativo in "${aninhados[@]}"; do
    caminho_real "$raiz/$relativo"
    btrfs subvolume show "$raiz/$relativo" >/dev/null

    destino="$snapshot/$relativo"
    caminho_real "$destino"
    [[ -d "$destino" ]] || die "Diretório ausente: $relativo"
    [[ -z "$(find "$destino" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
        die "O snapshot contém dados inesperados em $relativo."
done

# Recusa novos subvolumes aninhados não previstos nesta versão.
lista="$(btrfs subvolume list -o "$raiz")"
while IFS= read -r linha; do
    [[ -n "$linha" ]] || continue
    relativo="${linha#* path }"
    case "$relativo" in
        @/.snapshots|@/.snapshots/*|\
        @/var/lib/portables|@/var/lib/machines) ;;
        *) die "Subvolume aninhado não previsto: $relativo" ;;
    esac
done <<< "$lista"

for diretorio in boot boot/grub etc home var/log var/cache/pacman/pkg; do
    caminho_real "$snapshot/$diretorio"
    [[ -d "$snapshot/$diretorio" ]] ||
        die "Diretório ausente no snapshot: $diretorio"
done

# Esta versão exige os dois kernels usados no laboratório.
for arquivo in vmlinuz-linux vmlinuz-linux-lts \
               initramfs-linux.img initramfs-linux-lts.img; do
    [[ -s "$snapshot/boot/$arquivo" ]] ||
        die "Arquivo de boot ausente: $arquivo"
done

# Exige montagem da raiz por nome @, sem subvolid fixo.
awk -v esperado="UUID=$uuid" '
    $1 !~ /^#/ && $2 == "/" {
        quantidade++
        n = split($4, opcoes, ",")
        subvolume = 0
        idfixo = 0
        for (i = 1; i <= n; i++) {
            if (opcoes[i] == "subvol=/@" || opcoes[i] == "subvol=@")
                subvolume = 1
            if (opcoes[i] ~ /^subvolid=/)
                idfixo = 1
        }
        if ($1 == esperado && $3 == "btrfs" && subvolume && !idfixo)
            valido++
    }
    END { exit !(quantidade == 1 && valido == 1) }
' "$snapshot/etc/fstab" ||
    die "O fstab do snapshot não corresponde ao layout esperado."

printf '\nDispositivo: %s\nSnapshot: %s\n' "$dispositivo" "$numero"
printf 'Layout e arquivos necessários conferidos.\n'

if [[ "$modo" == "--check" ]]; then
    printf 'Conferência concluída. Nenhuma restauração realizada.\n'
    exit 0
fi

identificador="$(date +%Y%m%d-%H%M%S)-$$"
anterior="$topo/@antes-restauracao-$identificador"
nova="$topo/@restaurando-$identificador"
[[ ! -e "$anterior" && ! -e "$nova" ]] ||
    die "Nome de destino já existe."

printf '\nSerá restaurado o snapshot %s.\n' "$numero"
printf 'A raiz atual será preservada como %s\n' "${anterior##*/}"
printf 'Digite RESTAURAR %s para continuar: ' "$numero"
read -r resposta
[[ "$resposta" == "RESTAURAR $numero" ]] || die "Cancelado."

umount "$topo"
mount -o rw,subvolid=5 "$dispositivo" "$topo"

alterando=1
fase="criação da raiz restaurada"
btrfs subvolume snapshot "$snapshot" "$nova"

# Remove somente os diretórios vazios da cópia recém-criada.
fase="preparação dos pontos dos subvolumes aninhados"
for relativo in "${aninhados[@]}"; do
    rmdir "$nova/$relativo"
done

fase="transferência dos subvolumes aninhados"
for relativo in "${aninhados[@]}"; do
    mv -T "$raiz/$relativo" "$nova/$relativo"
done

fase="preservação da raiz anterior"
mv -T "$raiz" "$anterior"

fase="ativação da raiz restaurada"
mv -T "$nova" "$raiz"
sync

fase="montagem da raiz restaurada"
mount -o subvol=@ "$dispositivo" "$sistema"
mount -o subvol=@home "$dispositivo" "$sistema/home"
mount -o subvol=@log "$dispositivo" "$sistema/var/log"
mount -o subvol=@pkg "$dispositivo" "$sistema/var/cache/pacman/pkg"

# /boot está dentro de @. Não reinstala o GRUB nem altera /efi.
fase="regeneração do menu do GRUB"
arch-chroot "$sistema" grub-mkconfig -o /boot/grub/grub.cfg
arch-chroot "$sistema" grub-script-check /boot/grub/grub.cfg
sync

fase="desmontagem"
umount -R "$sistema"
umount "$topo"
concluido=1

printf '\nRestauração concluída a partir do snapshot %s.\n' "$numero"
printf 'Raiz anterior preservada: %s\n' "${anterior##*/}"
printf 'Desligue a VM e inicie pelo disco para validar.\n'
