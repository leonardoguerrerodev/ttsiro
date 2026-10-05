#!/bin/bash
# TTSiro: deja el lector listo en este Linux (dependencias, piper, voz, enlaces, atajos KDE).
# Uso: ./instalar.sh [--dry-run] [--solo-enlaces]   (idempotente; se puede repetir)
set -u
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; SOLO_ENLACES=0
for a in "$@"; do
  case "$a" in --dry-run) DRY=1 ;; --solo-enlaces) SOLO_ENLACES=1 ;; *) echo "Opción desconocida: $a" >&2; exit 2 ;; esac
done
run() { if ((DRY)); then echo "  [dry-run] $*"; else "$@"; fi; }

# ---------- 1. Dependencias ----------
instalar_paquetes() {
  . /etc/os-release 2>/dev/null
  local fam="${ID:-}${ID_LIKE:+ $ID_LIKE}" gestor pk
  case " $fam " in
    *" fedora "*|*" rhel "*|*" nobara "*) gestor=dnf; pk=(mpv rubberband wl-clipboard speech-dispatcher pipx python3); inst=(sudo dnf install -y) ;;
    *" debian "*|*" ubuntu "*)            gestor=apt; pk=(mpv rubberband-cli wl-clipboard speech-dispatcher pipx python3); inst=(sudo apt install -y) ;;
    *" arch "*)                           gestor=pacman; pk=(mpv rubberband wl-clipboard speech-dispatcher python-pipx python); inst=(sudo pacman -S --needed --noconfirm) ;;
    *" suse "*|*" opensuse "*)            gestor=zypper; pk=(mpv rubberband wl-clipboard speech-dispatcher python3-pipx python3); inst=(sudo zypper install -y) ;;
    *) echo "Distro no reconocida (${PRETTY_NAME:-?}). Instala a mano: mpv, rubberband (CLI), wl-clipboard, speech-dispatcher, pipx, python3."; return ;;
  esac
  echo "Distro: ${PRETTY_NAME:-$ID} → $gestor"
  # un paquete por binario que falte (mismo orden que pk)
  local bins=(mpv rubberband wl-paste spd-say pipx python3) falta=() i
  for i in "${!bins[@]}"; do command -v "${bins[$i]}" >/dev/null || falta+=("${pk[$i]}"); done
  # ponytail: no vuelve a revisar el paquete concreto de rubberband/sd_generic por distro; el resumen final avisa si falta algo.
  ((${#falta[@]})) && run "${inst[@]}" "${falta[@]}"
  command -v piper >/dev/null || run pipx install piper-tts
}

# ---------- 2. Enlaces (lo que antes se hacía a mano) ----------
enlazar() {  # enlazar ORIGEN DESTINO
  if [[ -e "$2" && ! -L "$2" ]]; then run mv -- "$2" "$2.bak.$(date +%s)"; echo "  (existía $2: respaldado)"; fi
  run mkdir -p "$(dirname -- "$2")"
  run ln -sfn "$1" "$2"
}
hacer_enlaces() {
  local f
  for f in "$RAIZ"/bin/*; do enlazar "$f" "$HOME/.local/bin/$(basename "$f")"; done
  for f in "$RAIZ"/applications/*.desktop; do enlazar "$f" "$HOME/.local/share/applications/$(basename "$f")"; done
  enlazar "$RAIZ/speech-dispatcher" "$HOME/.config/speech-dispatcher"
  enlazar "$RAIZ/voces" "$HOME/.local/share/piper"
}

# ---------- 3. Voz ----------
# Si no hay ninguna voz, baja es_MX-claude-high (pública, calidad alta); más voces se descargan desde la UI.
voz_por_defecto() {
  compgen -G "$RAIZ/voces/*.onnx" >/dev/null && return
  local v=es_MX-claude-high u=https://huggingface.co/rhasspy/piper-voices/resolve/main/es/es_MX/claude/high
  echo "No hay voces en voces/. Descargando $v…  (otras voces: desde la UI de TTSiro)"
  run mkdir -p "$RAIZ/voces"
  run curl -fL --retry 3 -o "$RAIZ/voces/$v.onnx" "$u/$v.onnx" && run curl -fL --retry 3 -o "$RAIZ/voces/$v.onnx.json" "$u/$v.onnx.json"
}

# ---------- 4. Perfil inicial ----------
perfil_inicial() {
  [[ -f "$RAIZ/activo.env" && -f "$RAIZ/perfiles.json" ]] && return
  run python3 -c "
import json, sys; sys.path.insert(0, '$RAIZ/ui'); import servidor as s
e = s.leer_estado(); s.escribir(s.PERFILES, json.dumps(e, indent=2, ensure_ascii=False)); s.escribir_env(e['perfiles'][e['activo']])"
}

# ---------- 5. Atajos de KDE (viven fuera del repo) ----------
atajos_kde() {
  local kw; kw="$(command -v kwriteconfig6 || command -v kwriteconfig5 || true)"
  if [[ -z "$kw" ]]; then echo "No hay KDE: asigna a mano Meta+R → leer-laura.sh y Meta+Ctrl+Shift+R → detener."; return; fi
  [[ -n "$(kreadconfig6 --file kglobalshortcutsrc --group services --group net.local.leer-laura.sh.desktop --key _launch 2>/dev/null)" ]] && return
  run "$kw" --file kglobalshortcutsrc --group services --group net.local.leer-laura.sh.desktop --key _launch "Meta+R"
  run "$kw" --file kglobalshortcutsrc --group services --group net.local.detener-laura.desktop --key _launch "Meta+Ctrl+Shift+R"
  echo "Atajos registrados; si no responden, cierra sesión y vuelve a entrar."
}

((SOLO_ENLACES)) || instalar_paquetes
hacer_enlaces
((SOLO_ENLACES)) || { voz_por_defecto; perfil_inicial; atajos_kde; }

# ---------- Resumen ----------
echo; echo "Resumen:"
for b in piper rubberband mpv wl-paste spd-say python3; do
  command -v "$b" >/dev/null && echo "  ✔ $b" || echo "  ✘ $b (falta)"
done
compgen -G "$RAIZ/voces/*.onnx" >/dev/null && echo "  ✔ voces: $(ls "$RAIZ"/voces/*.onnx | wc -l)" || echo "  ✘ voces"
[[ "$(readlink -f "$HOME/.local/bin/leer-laura.sh")" == "$RAIZ/bin/leer-laura.sh" ]] && echo "  ✔ enlaces" || echo "  ✘ enlaces"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "  ⚠ ~/.local/bin no está en PATH" ;; esac
echo; echo "Configurar voces/perfiles: python3 $RAIZ/ui/servidor.py  (o ./ui/onoff.sh)"
