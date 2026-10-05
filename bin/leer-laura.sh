#!/bin/bash
# Meta+R: lee el texto seleccionado con el perfil activo de TTSiro y abre mpv para controlarlo.

set -u

DIR="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
RAIZ="$(cd -- "$DIR/.." && pwd)"
ENV="$RAIZ/activo.env"
PIPER="$(command -v piper || true)"
RUBBERBAND="$(command -v rubberband || true)"

[[ -f "$ENV" ]] || { echo "ERROR: no se encontró $ENV" >&2; exit 1; }
[[ -n "$PIPER" ]] || { echo "ERROR: piper no está en PATH" >&2; exit 1; }
[[ -n "$RUBBERBAND" ]] || { echo "ERROR: rubberband no está en PATH" >&2; exit 1; }

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
T="$XDG_RUNTIME_DIR/ttsiro"
mkdir -p "$T"

source "$ENV"
pkill -f laura-pitch.wav 2>/dev/null || true
wl-paste --primary --no-newline > "$T/laura-texto.txt"
[ -s "$T/laura-texto.txt" ] || exit 0
"$PIPER" --model "$MODELO" \
  --length-scale "$VELOCIDAD" --noise-scale "$EXPRESIVIDAD" --noise-w "$RITMO" \
  --volume "$VOLUMEN" --sentence-silence "$PAUSA" \
  --input-file "$T/laura-texto.txt" --output-file "$T/laura.wav"
"$RUBBERBAND" --pitch "$TONO" "$T/laura.wav" "$T/laura-pitch.wav"
exec mpv --force-window=yes --geometry=420x110 --ontop --keep-open=yes --title=Laura --no-terminal \
  --script-opts=osc-layout=box,osc-visibility=always,osc-vidscale=no,osc-title=Laura "$T/laura-pitch.wav"
