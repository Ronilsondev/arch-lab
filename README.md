# Arch Lab

Laboratório pessoal para estudar infraestrutura Linux, personalizar o
Arch Linux e desenvolver uma instalação reproduzível.

## Ambiente

- Máquina virtual com disco de 60 GiB.
- Arch Linux com kernels linux e linux-lts.
- Inicialização UEFI com GRUB.
- Hyprland com UWSM.
- Waybar, Mako e Fuzzel.
- NetworkManager e acesso remoto por SSH.
- Swap em Zram de aproximadamente 4 GiB.

## Armazenamento

| Partição | Tamanho | Formato | Montagem |
|---|---:|---|---|
| /dev/vda1 | 1 GiB | FAT32 | /efi |
| /dev/vda2 | 59 GiB | Btrfs | / e subvolumes |

O Btrfs utiliza compressão Zstd nível 3.

| Subvolume | Montagem |
|---|---|
| @ | / |
| @home | /home |
| @log | /var/log |
| @pkg | /var/cache/pacman/pkg |

O diretório /boot está dentro do subvolume raiz.
A partição EFI é separada.

## Snapshots e recuperação

- Snapper com configurações independentes para / e /home.
- Snapshots periódicos e limpeza automática habilitados.
- snap-pac cria snapshots antes e depois de transações do Pacman.
- grub-btrfs disponibiliza snapshots no menu do GRUB.
- O hook grub-btrfs-overlayfs permite iniciar snapshots somente leitura
  com uma camada temporária de escrita.

Iniciar um snapshot pelo GRUB não restaura permanentemente o sistema.
As alterações na camada temporária não persistem após reiniciar.
Subvolumes montados separadamente, como /home, não são revertidos
pelo snapshot da raiz e podem continuar recebendo alterações persistentes.

### Restauração permanente validada

O teste foi realizado a partir da ISO do Arch:

1. Montagem do nível superior do Btrfs.
2. Criação de um snapshot gravável a partir do snapshot escolhido.
3. Transferência dos subvolumes aninhados .snapshots,
   var/lib/portables e var/lib/machines para a raiz restaurada.
4. Preservação da raiz anterior como @antes-restauracao.
5. Renomeação da raiz restaurada para @.
6. Montagem do sistema e regeneração da configuração do GRUB via chroot.
7. Reinicialização e confirmação da restauração.

Esse procedimento corresponde ao layout deste laboratório.
O fstab monta explicitamente subvol=/@.

Snapshots no mesmo disco não substituem um backup externo.

## Arquivos versionados

- dotfiles/hypr/hyprland.lua: configuração do Hyprland.
- dotfiles/waybar/config.jsonc: módulos da Waybar.
- dotfiles/waybar/style.css: aparência da Waybar.
- packages-repo.txt: pacotes explícitos dos repositórios oficiais.
- packages-aur-ou-locais.txt: pacotes explícitos externos aos repositórios.

As listas registram nomes de pacotes, sem fixar versões.

## Estado validado

- [x] Ambiente gráfico e atalhos.
- [x] Barra e notificações.
- [x] Acesso por SSH.
- [x] Snapshots antes e depois de instalações.
- [x] Inicialização de snapshot pelo GRUB.
- [x] Restauração permanente.
- [x] Repositório enviado ao GitHub.
- [ ] Script de aplicação dos dotfiles.
- [ ] Script de instalação do sistema.

## Atualização das listas

```bash
pacman -Qqen > packages-repo.txt
pacman -Qqem > packages-aur-ou-locais.txt
