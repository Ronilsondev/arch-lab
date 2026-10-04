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

# Preparação dos modelos Rosé Pine
preparar_modelos() {
    local revisao="4cdd7af493141454f3047160f67bc15b277573d4"
    local origem="$HOME/Downloads/dotfiles-rosepine"
    local temporario
    local relativo
    local faltando=0

    for relativo in mpd/mpd.conf ncmpcpp/config cava/config \
                    kitty/kitty.conf mako/config; do
        [[ -f "$repo/dotfiles/$relativo" ]] || faltando=1
    done

    ((faltando == 1)) || return 0

    command -v git >/dev/null || {
        echo "Instale git antes de continuar." >&2
        return 1
    }

    temporario="$(mktemp -d)"
    trap 'rm -rf -- "$temporario"' RETURN

    if git -C "$origem" cat-file -e "$revisao^{commit}" 2>/dev/null; then
        echo "Preparando Rosé Pine a partir da revisão local."
        git -C "$origem" archive "$revisao" | tar -x -C "$temporario"
    else
        echo "Baixando a revisão validada do Rosé Pine."
        git init -q "$temporario"
        git -C "$temporario" remote add origin \
            https://github.com/micrus/dotfiles-rosepine.git
        git -C "$temporario" fetch --progress --depth 1 origin "$revisao"
        git -C "$temporario" checkout --detach FETCH_HEAD
        [[ "$(git -C "$temporario" rev-parse HEAD)" == "$revisao" ]]
    fi

    python - "$temporario" "$repo" <<'PREPARAR'
from pathlib import Path
import sys

origem, repo = map(Path, sys.argv[1:])
modelos = {
    "mpd/mpd.conf": "mpd/.config/mpd/mpd.conf",
    "ncmpcpp/config": "ncmpcpp/.config/ncmpcpp/config",
    "cava/config": "cava/.config/cava/config",
    "kitty/kitty.conf": "kitty/.config/kitty/kitty.conf",
    "mako/config": "mako/.config/mako/config",
}

preparados = {}
for relativo, fonte in modelos.items():
    destino = repo / "dotfiles" / relativo
    if destino.exists():
        continue

    texto = (origem / fonte).read_text()

    if relativo == "mpd/mpd.conf":
        texto = texto.replace("/home/micrus/Music", "@HOME@/Música")
        texto = texto.replace(
            "/home/micrus/.config/mpd", "@HOME@/.local/share/mpd"
        )
        texto = texto.replace(
            "/tmp/mpd.fifo", "@HOME@/.local/share/mpd/ncmpcpp.fifo"
        )
        texto = texto.replace('"localhost"', '"127.0.0.1"')
        texto = "\n".join(
            linha for linha in texto.splitlines()
            if not linha.lstrip().startswith("pid_file")
        ) + '\nauto_update "yes"\n'
        texto += 'sticker_file "@HOME@/.local/share/mpd/sticker.sql"\n'

    elif relativo == "ncmpcpp/config":
        texto = texto.replace(
            "/tmp/mpd.fifo", "@HOME@/.local/share/mpd/ncmpcpp.fifo"
        )
        texto = texto.replace("= localhost", "= 127.0.0.1")

    elif relativo == "cava/config":
        linhas = []
        secao = ""
        for linha in texto.splitlines():
            limpa = linha.strip()
            if limpa.startswith("[") and limpa.endswith("]"):
                secao = limpa
            chave = limpa.split("=", 1)[0].strip()
            if secao == "[input]":
                if chave == "method":
                    linha = "method = pulse"
                elif chave == "source":
                    linha = "source = auto"
                elif chave in {"sample_rate", "sample_bits", "channels"}:
                    continue
            linhas.append(linha)
        texto = "\n".join(linhas) + "\n"

    elif relativo == "mako/config":
        texto = "\n".join(
            linha for linha in texto.splitlines()
            if not linha.lstrip().startswith("on-button-left=")
        ) + "\n"
        texto = "on-button-left=invoke-default-action\n" + texto

    preparados[destino] = texto

for destino, texto in preparados.items():
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text(texto)
    print(f"Modelo preparado: {destino}")
PREPARAR

    rm -rf -- "$temporario"
    trap - RETURN
}

preparar_modelos

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
