#!/bin/bash
# Meta+R: lee el texto seleccionado con el perfil activo de TTSiro y abre mpv para controlarlo.
# Los atajos de KDE no tienen terminal: los errores van a notify-send y a $XDG_RUNTIME_DIR/ttsiro/leer.log.

set -u
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"   # un atajo de KDE puede no heredar ~/.local/bin (ahí vive piper)

DIR="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
RAIZ="$(cd -- "$DIR/.." && pwd)"
ENV="$RAIZ/activo.env"
TTS="$RAIZ/bin/ttsiro-piper"   # igual que piper, pero con la voz cargada en memoria (daemon ttsirod)

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
T="$XDG_RUNTIME_DIR/ttsiro"
mkdir -p "$T"
LOG="$T/leer.log"
: > "$LOG"

avisar() {  # avisar ICONO MENSAJE
  echo "$2" | tee -a "$LOG" >&2
  command -v notify-send >/dev/null && notify-send -a TTSiro -i "$1" "TTSiro" "$2"
  return 0
}

[[ -f "$ENV" ]] || { avisar dialog-error "Falta $ENV: guarda un perfil desde la UI (ui/servidor.py) o ejecuta ./instalar.sh"; exit 1; }
command -v piper >/dev/null || { avisar dialog-error "piper no está instalado: ejecuta ./instalar.sh"; exit 1; }
command -v mpv >/dev/null || { avisar dialog-error "mpv no está instalado: ejecuta ./instalar.sh"; exit 1; }

# shellcheck source=/dev/null
source "$ENV"
[[ -f "$MODELO" ]] || { avisar dialog-error "No existe la voz $MODELO: ejecuta ./instalar.sh o elige otra en la UI"; exit 1; }

pkill -f '[l]aura-pitch\.wav' 2>/dev/null || true
rm -f "$T/laura.wav" "$T/laura-pitch.wav"   # que un fallo no reproduzca el audio de la lectura anterior

wl-paste --primary --no-newline > "$T/laura-texto.txt" 2>>"$LOG"
[[ -s "$T/laura-texto.txt" ]] || { avisar dialog-information "No hay texto seleccionado"; exit 0; }

"$TTS" --model "$MODELO" \
  --length-scale "$VELOCIDAD" --noise-scale "$EXPRESIVIDAD" --noise-w "$RITMO" \
  --volume "$VOLUMEN" --sentence-silence "$PAUSA" \
  --input-file "$T/laura-texto.txt" --output-file "$T/laura.wav" 2>>"$LOG"
[[ -s "$T/laura.wav" ]] || { avisar dialog-error "No se pudo sintetizar: $(tail -n 1 "$LOG")  (log: $LOG)"; exit 1; }

# Tono 0 = sin tratamiento (se salta rubberband); si rubberband falla o no está, se lee sin cambiar el tono.
if awk -v t="${TONO:-0}" 'BEGIN { exit !(t + 0 != 0) }' && command -v rubberband >/dev/null; then
  rubberband --pitch "$TONO" "$T/laura.wav" "$T/laura-pitch.wav" 2>>"$LOG" || mv -f "$T/laura.wav" "$T/laura-pitch.wav"
else
  mv -f "$T/laura.wav" "$T/laura-pitch.wav"
fi

exec mpv --force-window=yes --geometry=420x110 --ontop --keep-open=yes --title=Laura --no-terminal \
  --log-file="$T/mpv.log" \
  --script-opts=osc-layout=box,osc-visibility=always,osc-vidscale=no,osc-title=Laura "$T/laura-pitch.wav"
