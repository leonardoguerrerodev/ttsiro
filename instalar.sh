#!/bin/bash
# TTSiro: deja el lector listo (y lo repara) en este Linux: dependencias, piper, voz, enlaces, lanzadores y atajos KDE.
# Uso: ./instalar.sh [--dry-run] [--solo-enlaces]   (idempotente; repetirlo repara lo que esté roto)
set -u
shopt -u patsub_replacement 2>/dev/null   # bash 5.2: que "&" en un reemplazo sea literal
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATH_ORIGINAL="$PATH"
export PATH="$HOME/.local/bin:$PATH"      # pipx deja piper ahí; puede no estar aún en el PATH de la sesión
case "$RAIZ" in
  *[\"\`\$\\]*) echo "La ruta $RAIZ tiene caracteres no soportados (comillas, \`, \$, \\): mueve la carpeta." >&2; exit 2 ;;
esac
DRY=0; SOLO_ENLACES=0; FALLOS=0; DESKTOP_CAMBIO=0
for a in "$@"; do
  case "$a" in --dry-run) DRY=1 ;; --solo-enlaces) SOLO_ENLACES=1 ;; *) echo "Opción desconocida: $a" >&2; exit 2 ;; esac
done
run() { if ((DRY)); then echo "  [dry-run] $*"; else "$@"; fi; }
ok()    { echo "  ✔ $*"; }
mal()   { echo "  ✘ $*"; FALLOS=$((FALLOS + 1)); }
aviso() { echo "  ⚠ $*"; }

ATAJO_IDS=(net.local.leer-laura.sh.desktop net.local.detener-laura.desktop)
ATAJO_VAL=("Meta+R,none,Laura" "Meta+Ctrl+Shift+R,none,Detener Laura")
RC_ATAJOS="kglobalshortcutsrc"

# ---------- 1. Dependencias ----------
instalar_paquetes() {
  . /etc/os-release 2>/dev/null
  local fam="${ID:-}${ID_LIKE:+ $ID_LIKE}" gestor pk inst
  case " $fam " in
    *" fedora "*|*" rhel "*|*" nobara "*) gestor=dnf; pk=(mpv rubberband wl-clipboard speech-dispatcher pipx python3 libnotify); inst=(sudo dnf install -y) ;;
    *" debian "*|*" ubuntu "*)            gestor=apt; pk=(mpv rubberband-cli wl-clipboard speech-dispatcher pipx python3 libnotify-bin); inst=(sudo apt install -y) ;;
    *" arch "*)                           gestor=pacman; pk=(mpv rubberband wl-clipboard speech-dispatcher python-pipx python libnotify); inst=(sudo pacman -S --needed --noconfirm) ;;
    *" suse "*|*" opensuse "*)            gestor=zypper; pk=(mpv rubberband wl-clipboard speech-dispatcher python3-pipx python3 libnotify-tools); inst=(sudo zypper install -y) ;;
    *) echo "Distro no reconocida (${PRETTY_NAME:-?}). Instala a mano: mpv, rubberband (CLI), wl-clipboard, speech-dispatcher, pipx, python3, notify-send."; return ;;
  esac
  echo "Distro: ${PRETTY_NAME:-$ID} → $gestor"
  # un paquete por binario que falte (mismo orden que pk)
  local bins=(mpv rubberband wl-paste spd-say pipx python3 notify-send) falta=() i
  for i in "${!bins[@]}"; do command -v "${bins[$i]}" >/dev/null || falta+=("${pk[$i]}"); done
  ((${#falta[@]})) && run "${inst[@]}" "${falta[@]}"
}

# ---------- 2. piper (se repara si el venv de pipx quedó roto, p. ej. tras cambiar la versión de Python) ----------
piper_py() {  # el python donde vive piper (lo dice su shebang); vacío si no se puede saber
  local p sb a b
  p="$(command -v piper)" || return 1
  sb="$(head -n 1 -- "$p" 2>/dev/null)" || return 1
  [[ "$sb" == '#!'* ]] || return 1
  read -r a b _ <<< "${sb#\#!}"
  [[ "$a" == */env ]] && a="$(command -v "$b")"
  [[ -x "$a" ]] && echo "$a"
}
piper_sano() {  # lo mismo que importa ttsirod
  local py; py="$(piper_py)" || return 1
  "$py" -c 'from piper import PiperVoice, SynthesisConfig' 2>/dev/null
}
instalar_piper() {
  piper_sano && return
  if command -v piper >/dev/null; then echo "piper no arranca (¿cambió la versión de Python?): reinstalando…"; else echo "Instalando piper…"; fi
  command -v pipx >/dev/null || { echo "  Falta pipx: instálalo y vuelve a ejecutar ./instalar.sh."; return; }
  run pipx install --force piper-tts
}

# ---------- 3. Enlaces y lanzadores ----------
enlazar() {  # enlazar ORIGEN DESTINO
  if [[ -e "$2" && ! -L "$2" ]]; then run mv -- "$2" "$2.bak.$(date +%s)"; echo "  (existía $2: respaldado)"; fi
  run mkdir -p "$(dirname -- "$2")"
  run ln -sfn "$1" "$2"
}
render() {  # render PLANTILLA DESTINO: las .desktop con Exec necesitan ruta absoluta, así que se generan con @RAIZ@ resuelto
  local plantilla="$1" dest="$2" linea nuevo
  nuevo="$(while IFS= read -r linea || [[ -n "$linea" ]]; do printf '%s\n' "${linea//@RAIZ@/$RAIZ}"; done < "$plantilla")"
  if [[ -f "$dest" && ! -L "$dest" && "$(<"$dest")" == "$nuevo" ]]; then return; fi
  DESKTOP_CAMBIO=1
  if ((DRY)); then echo "  [dry-run] generar $dest"; return; fi
  mkdir -p "$(dirname -- "$dest")"
  if [[ -e "$dest" && ! -L "$dest" ]]; then mv -- "$dest" "$dest.bak.$(date +%s)"; echo "  (existía $dest: respaldado)"; fi
  rm -f -- "$dest"   # si era un symlink al repo, no escribir a través de él
  printf '%s\n' "$nuevo" > "$dest" && chmod 644 "$dest"
}
hacer_enlaces() {
  local f
  run mkdir -p "$RAIZ/voces"
  for f in "$RAIZ"/bin/*; do enlazar "$f" "$HOME/.local/bin/$(basename "$f")"; done
  enlazar "$RAIZ/speech-dispatcher" "$HOME/.config/speech-dispatcher"
  enlazar "$RAIZ/voces" "$HOME/.local/share/piper"
  enlazar "$RAIZ/plasmoid" "$HOME/.local/share/plasma/plasmoids/net.local.ttsiro.estado"  # icono de la barra: ¿voz precargada?
  for f in "$RAIZ"/applications/*.desktop; do render "$f" "$HOME/.local/share/applications/$(basename "$f")"; done
  render "$RAIZ/autostart/ttsiro-daemon.desktop" "$HOME/.config/autostart/ttsiro-daemon.desktop"  # precarga la voz al iniciar sesión
  if ((DESKTOP_CAMBIO && !DRY)) && command -v kbuildsycoca6 >/dev/null; then kbuildsycoca6 --noincremental >/dev/null 2>&1; fi
}

# ---------- 4. Voz ----------
# Si no hay ninguna voz, baja es_MX-claude-high (pública, calidad alta); más voces se descargan desde la UI.
voz_por_defecto() {
  compgen -G "$RAIZ/voces/*.onnx" >/dev/null && return
  local v=es_MX-claude-high u=https://huggingface.co/rhasspy/piper-voices/resolve/main/es/es_MX/claude/high f
  echo "No hay voces en voces/. Descargando $v…  (otras voces: desde la UI de TTSiro)"
  run mkdir -p "$RAIZ/voces"
  for f in "$v.onnx.json" "$v.onnx"; do  # el .onnx al final: la voz "existe" solo cuando está completa
    if run curl -fL --retry 3 -o "$RAIZ/voces/$f.part" "$u/$f"; then run mv -f "$RAIZ/voces/$f.part" "$RAIZ/voces/$f"
    else echo "  Falló la descarga de $f."; rm -f "$RAIZ/voces/$f.part"; return; fi
  done
}

# ---------- 5. Perfil: perfiles.json y activo.env coherentes y apuntando a una voz que exista ----------
perfil_reparar() {
  if ((DRY)); then echo "  [dry-run] reparar perfiles.json / activo.env"; return; fi
  python3 - "$RAIZ" <<'PY'
import copy, json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1] + "/ui")
import servidor as s

disp = s.voces()
if not disp:
    print("  Sin voces en voces/: no se puede crear el perfil.")
    sys.exit(0)
try:
    e = s.leer_estado()
    perfiles, activo = e["perfiles"], e["activo"]
except Exception as ex:  # noqa: BLE001
    print(f"  perfiles.json ilegible ({ex}): se rehace.")
    perfiles, activo = {}, None
perfiles = {n: p for n, p in perfiles.items() if isinstance(p, dict)}
antes = copy.deepcopy(perfiles)
bueno = lambda n: n in perfiles and perfiles[n].get("voz") in disp
if not bueno(activo):
    alt = next((n for n in perfiles if bueno(n)), None)
    if alt is None:
        voz = "es_MX-laura-high" if "es_MX-laura-high" in disp else disp[0]
        alt = "Predeterminado"
        perfiles[alt] = {"voz": voz}
    print(f"  Perfil activo '{activo}' → '{alt}' (la voz del anterior no está en voces/).")
    activo = alt
perfiles[activo] = s.limpiar(perfiles[activo])
try:
    if perfiles != antes or not s.PERFILES.exists():
        s.escribir(s.PERFILES, json.dumps({"activo": activo, "perfiles": perfiles}, indent=2, ensure_ascii=False))
    s.escribir_env(perfiles[activo])
except Exception as ex:  # noqa: BLE001
    print(f"  No se pudo escribir el perfil: {ex}")
PY
}

# ---------- 6. Atajos de KDE (viven fuera del repo) ----------
kga() {  # kga ACCION: para/arranca el demonio de atajos globales (no hay forma fiable de que relea el archivo en caliente)
  if ((DRY)); then echo "  [dry-run] systemctl --user $1 plasma-kglobalaccel.service"; return; fi
  systemctl --user "$1" plasma-kglobalaccel.service 2>/dev/null
}
atajos_kde() {
  local kw kr i act clave pend=() rc="${XDG_CONFIG_HOME:-$HOME/.config}/$RC_ATAJOS"
  kw="$(command -v kwriteconfig6 || command -v kwriteconfig5 || true)"
  kr="$(command -v kreadconfig6 || command -v kreadconfig5 || true)"
  if [[ -z "$kw" || -z "$kr" ]]; then echo "No hay KDE: asigna a mano Meta+R → leer-laura.sh y Meta+Ctrl+Shift+R → detener-laura.sh."; return; fi
  for i in "${!ATAJO_IDS[@]}"; do  # solo se asigna lo que esté vacío: un atajo que cambiaste a mano se respeta
    act="$("$kr" --file "$RC_ATAJOS" --group services --group "${ATAJO_IDS[$i]}" --key _launch 2>/dev/null)"
    act="${act%%,*}"
    [[ -z "$act" || "$act" == none ]] && pend+=("$i")
  done
  if ((${#pend[@]} || DESKTOP_CAMBIO)); then
    kga stop   # parado, para que no pise el archivo al cerrarse
    for i in "${pend[@]}"; do
      run "$kw" --file "$RC_ATAJOS" --group services --group "${ATAJO_IDS[$i]}" --key _launch "${ATAJO_VAL[$i]}"
    done
    kga start
    ((${#pend[@]} && !DRY)) && echo "Atajos registrados (Meta+R leer, Meta+Ctrl+Shift+R detener)."
  fi
  ((DRY)) && return
  for i in "${!ATAJO_IDS[@]}"; do  # aviso si la tecla ya la usa otra acción
    act="$("$kr" --file "$RC_ATAJOS" --group services --group "${ATAJO_IDS[$i]}" --key _launch 2>/dev/null)"
    clave="${act%%,*}"; clave="${clave%%$'\t'*}"; clave="${clave%%\\t*}"
    [[ -n "$clave" && "$clave" != none && -f "$rc" ]] || continue
    awk -v id="${ATAJO_IDS[$i]}" -v clave="$clave" '
      /^\[/ { grp = $0; next }
      index(grp, "[" id "]") { next }
      { p = index($0, "="); if (!p) next
        split(substr($0, p + 1), f, ",")
        n = split(f[1], ks, /\\t|\t/)
        for (j = 1; j <= n; j++) if (ks[j] == clave) { print "  ⚠ " clave " también lo usa " grp " " substr($0, 1, p - 1) " (Preferencias del sistema → Atajos)"; break } }
    ' "$rc"
  done
}

# ---------- Ejecución ----------
((SOLO_ENLACES)) || instalar_paquetes
((SOLO_ENLACES)) || instalar_piper
hacer_enlaces
((SOLO_ENLACES)) || { voz_por_defecto; perfil_reparar; atajos_kde; }

# ---------- Resumen ----------
resumen() {
  local b n f d py modelo nv kr act wav
  echo; echo "Resumen:"
  if ((DRY)); then echo "  (dry-run: no se verificó nada)"; return; fi
  for b in rubberband mpv wl-paste python3; do command -v "$b" >/dev/null && ok "$b" || mal "$b (falta)"; done
  for b in spd-say notify-send; do command -v "$b" >/dev/null && ok "$b" || aviso "$b (falta; solo Okular / avisos de error)"; done
  if piper_sano; then
    py="$(piper_py)"; ok "piper $("$py" -c 'import importlib.metadata as m; print(m.version("piper-tts"))' 2>/dev/null)"
  else mal "piper (falta o no arranca; revisa: pipx install --force piper-tts)"; fi

  nv="$(compgen -G "$RAIZ/voces/*.onnx" | wc -l)"
  if ((nv)); then ok "voces: $nv"; else mal "voces (ninguna en $RAIZ/voces)"; fi
  modelo="$( . "$RAIZ/activo.env" 2>/dev/null && echo "${MODELO:-}" )"
  if [[ -n "$modelo" && -f "$modelo" && -f "$modelo.json" ]]; then ok "voz activa: $(basename "$modelo" .onnx)"
  else mal "activo.env no apunta a una voz existente (abre la UI y pulsa Activar)"; fi

  local malos=()
  for f in "$RAIZ"/bin/*; do n="$(basename "$f")"; [[ "$(readlink -f "$HOME/.local/bin/$n")" == "$(readlink -f "$f")" ]] || malos+=("$n"); done
  if ((${#malos[@]})); then mal "enlaces rotos en ~/.local/bin: ${malos[*]}"; else ok "enlaces (~/.local/bin)"; fi

  local ds=("$HOME"/.local/share/applications/net.local.{leer-laura.sh,detener-laura,ttsiro}.desktop "$HOME/.config/autostart/ttsiro-daemon.desktop") rotos=()
  for d in "${ds[@]}"; do
    if [[ ! -f "$d" || -L "$d" ]] || grep -q '@RAIZ@' "$d" || ! grep -qF "$RAIZ" "$d"; then rotos+=("$(basename "$d")")
    elif command -v desktop-file-validate >/dev/null && ! desktop-file-validate "$d" >/dev/null 2>&1; then rotos+=("$(basename "$d") (inválido)"); fi
  done
  if ((${#rotos[@]})); then mal "lanzadores: ${rotos[*]}"; else ok "lanzadores .desktop (rutas absolutas)"; fi

  kr="$(command -v kreadconfig6 || command -v kreadconfig5 || true)"
  if [[ -n "$kr" ]]; then
    for n in "${!ATAJO_IDS[@]}"; do
      act="$("$kr" --file "$RC_ATAJOS" --group services --group "${ATAJO_IDS[$n]}" --key _launch 2>/dev/null)"; act="${act%%,*}"
      if [[ -n "$act" && "$act" != none ]]; then ok "atajo ${act//$'\t'/ , } → ${ATAJO_VAL[$n]##*,}"; else mal "atajo sin asignar: ${ATAJO_VAL[$n]##*,}"; fi
    done
  fi
  if [[ -f "$HOME/.local/share/plasma/plasmoids/net.local.ttsiro.estado/metadata.json" ]]; then ok "plasmoide enlazado"; else mal "plasmoide"; fi

  if ((nv)) && [[ -n "$modelo" ]] && piper_sano; then  # prueba real: texto → daemon → audio (no se reproduce)
    wav="$(mktemp --suffix=.wav)"
    ( . "$RAIZ/activo.env"
      printf 'Prueba de la voz de TTSiro.' | "$RAIZ/bin/ttsiro-piper" --model "$MODELO" --length-scale "$VELOCIDAD" \
        --noise-scale "$EXPRESIVIDAD" --noise-w "$RITMO" --volume "$VOLUMEN" --sentence-silence "$PAUSA" -f "$wav" ) 2>"$wav.err"
    if (($(stat -c %s "$wav") > 1000)); then ok "síntesis de prueba ($(($(stat -c %s "$wav") / 1024)) KB de audio)"
    else mal "la síntesis de prueba falló: $(tail -n 2 "$wav.err" | tr '\n' ' ')"; fi
    rm -f "$wav" "$wav.err"
    echo "    daemon: $("$RAIZ/bin/ttsiro-piper" --estado 2>/dev/null)"
  fi
  case ":$PATH_ORIGINAL:" in *":$HOME/.local/bin:"*) ;; *) aviso "El PATH de esta shell no incluye ~/.local/bin (los atajos ya lo añaden solos; para la terminal: pipx ensurepath)" ;; esac
}
resumen

echo
echo "Logs: ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ttsiro/{leer,daemon,mpv}.log"
echo "Si Meta+R no responde justo tras instalar: cierra sesión y vuelve a entrar (una sola vez)."
echo "Plasmoide: clic derecho en el panel → Añadir widgets → TTSiro (si no aparece: systemctl --user restart plasma-plasmashell)."
echo "Configurar voces/perfiles: python3 $RAIZ/ui/servidor.py  (o ./ui/onoff.sh)"
((FALLOS == 0))
