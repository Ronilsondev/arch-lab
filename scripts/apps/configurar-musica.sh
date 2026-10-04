#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -ne 0 ]] || {
    echo "Execute sem sudo." >&2
    exit 1
}

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

for comando in python mpd mpc ncmpcpp cava; do
    command -v "$comando" >/dev/null || {
        echo "Comando ausente: $comando" >&2
        exit 1
    }
done

if systemctl is-active --quiet mpd.service ||
   systemctl is-active --quiet mpd.socket; then
    echo "Existe um MPD do sistema ativo. Revise antes de continuar." >&2
    exit 1
fi

python - "$repo" <<'PY'
from pathlib import Path
from datetime import datetime
import os
import shutil
import sys
import tempfile

repo = Path(sys.argv[1])
home = Path.home()
config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")

arquivos = [
    "mpd/mpd.conf",
    "ncmpcpp/config",
    "cava/config",
    "kitty/kitty.conf",
    "mako/config",
]

conteudos = {}
for relativo in arquivos:
    origem = repo / "dotfiles" / relativo
    if not origem.is_file():
        raise SystemExit(f"Arquivo necessário ausente: {origem}")
    destino = config / relativo
    if destino.is_dir():
        raise SystemExit(f"Destino é um diretório: {destino}")
    conteudos[relativo] = origem.read_text().replace("@HOME@", str(home))

backup = (
    home / ".local/share/arch-lab/backups" /
    datetime.now().strftime("musica-%Y%m%d-%H%M%S-%f")
)
backup.mkdir(parents=True, mode=0o700)

for relativo in arquivos:
    destino = config / relativo
    if destino.exists() or destino.is_symlink():
        copia = backup / relativo
        copia.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(destino, copia, follow_symlinks=False)

(home / "Música").mkdir(exist_ok=True)
dados = home / ".local/share/mpd"
dados.mkdir(parents=True, exist_ok=True)
dados.chmod(0o700)
(dados / "playlists").mkdir(exist_ok=True)

for relativo, texto in conteudos.items():
    destino = config / relativo
    destino.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", dir=destino.parent, delete=False
    ) as arquivo:
        temporario = Path(arquivo.name)
        arquivo.write(texto)
    temporario.replace(destino)
    print(f"Aplicado: {destino}")

print(f"Backup: {backup}")
PY

systemctl --user enable mpd.service
systemctl --user restart mpd.service
systemctl --user is-active --quiet mpd.service
mpc -h 127.0.0.1 update

echo "Configurações aplicadas e MPD ativo."
echo "Dentro do Hyprland, execute: makoctl reload"
