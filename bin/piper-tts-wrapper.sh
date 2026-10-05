#!/bin/bash
# Okular (speech-dispatcher): lee stdin usando el perfil activo de TTSiro.

set -u
DIR="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
RAIZ="$(cd -- "$DIR/.." && pwd)"
ENV="$RAIZ/activo.env"
PIPER="$(command -v piper || true)"

[[ -f "$ENV" ]] || { echo "ERROR: no se encontró $ENV" >&2; exit 1; }
[[ -n "$PIPER" ]] || { echo "ERROR: piper no está en PATH" >&2; exit 1; }

source "$ENV"
"$PIPER" --model "$MODELO" \
  --length-scale "$VELOCIDAD" --noise-scale "$EXPRESIVIDAD" --noise-w "$RITMO" \
  --volume "$VOLUMEN" --sentence-silence "$PAUSA" --output_raw |
  mpv --no-video --no-terminal --demuxer=rawaudio --demuxer-rawaudio-format=s16le \
    --demuxer-rawaudio-channels=1 --demuxer-rawaudio-rate="$TASA" --af=rubberband=pitch-scale="$TONO_ESCALA" -
