# TTSiro

Lector en voz alta local para Linux/KDE con [piper](https://github.com/OHF-Voice/piper1-gpl): **Meta+R** lee la selección, **Okular** lee por speech-dispatcher, y una UI web local (`ui/servidor.py`) configura perfiles de voz.

El repo no tiene rutas absolutas: `instalar.sh` genera los `.desktop` (atajos, autostart) con la ruta real de la carpeta. Si la mueves, vuelve a ejecutar `./instalar.sh`.

## Instalar (otro PC)

```bash
git clone <este repo> && cd TTSiro
./instalar.sh              # --dry-run para ver qué haría; --solo-enlaces para saltarse paquetes
```

`instalar.sh` también **repara**: es idempotente y se puede repetir cuando algo falle. Detecta la distro (dnf, apt, pacman, zypper) e instala `mpv`, `rubberband`, `wl-clipboard`, `speech-dispatcher`, `pipx` y `notify-send`; instala piper con pipx y lo **reinstala si su venv quedó roto** (por ejemplo tras cambiar la versión de Python de la distro); crea los symlinks (`~/.local/bin`, `~/.config/speech-dispatcher`, `~/.local/share/piper`, plasmoide); genera los `.desktop` con rutas absolutas; registra los atajos de KDE solo si están vacíos (Meta+R leer, Meta+Ctrl+Shift+R detener; un atajo que hayas cambiado a mano se respeta y avisa si la tecla ya la usa otra acción); rehace `perfiles.json` / `activo.env` si apuntan a una voz que no existe; y termina con un resumen ✔/✘ que incluye una síntesis de prueba real. Si ya hay una carpeta real en un destino, la respalda como `.bak.<timestamp>`.

## Configurar voz

```bash
python3 ui/servidor.py        # abre http://127.0.0.1:8765  (o ./ui/onoff.sh para menú de terminal)
```

Desde la UI: perfiles (voz, velocidad, tono, volumen, expresividad, variación, pausa), **Probar**, **Guardar** y **Activar** (el perfil activo se escribe en `activo.env`, que releen Meta+R y Okular en cada lectura). El desplegable **Descargar** baja voces en español del catálogo público de piper (Hugging Face), así que los modelos `.onnx` no van en el repo (`voces/` está en `.gitignore`).

## Voz precargada (daemon) y plasmoide

`bin/ttsirod` mantiene las voces de piper cargadas en memoria; `bin/ttsiro-piper` es un reemplazo directo de `piper` que le habla al daemon (y lo arranca solo si no está). Si algo falla, cae a `piper` normal. `autostart/ttsiro-daemon.desktop` precarga la voz del perfil activo al iniciar sesión.

`plasmoid/` es un widget de Plasma 6 para la barra (se enlaza solo con `instalar.sh`): punto verde = voz precargada, ámbar = cargando, rojo = no precargada; el popup tiene **Precargar ahora** y **Liberar memoria**. Si no aparece en *Añadir widgets*: `systemctl --user restart plasma-plasmashell`.

```bash
ttsiro-piper --estado     # JSON con el estado (lo que lee el plasmoide)
ttsiro-piper --precargar  # carga la voz activa
ttsiro-piper --salir      # apaga el daemon y libera la memoria
```

## Voz Laura (`es_MX-laura-high`)

Es el modelo que se usa por defecto en los perfiles de Leo. Ya no está en el catálogo público de piper (upstream ofrece `es_MX-claude-high`, mismo tamaño pero bytes distintos), por eso hay respaldo en Google Drive con enlace público:

- Carpeta: https://drive.google.com/drive/folders/1188Cx_68TAR24uIZ47jrEvtBeDFxR63X
- Modelo (`.onnx`, 63 MB): https://drive.google.com/uc?export=download&id=13UN5UNZ-0DvLCn3SV9pevV5gRtZ2dIVJ&confirm=t
- Config (`.onnx.json`): https://drive.google.com/uc?export=download&id=14ZeSiVzckUSqFQYJBywIoGAhDaPRZHai

```bash
cd voces
curl -L -o es_MX-laura-high.onnx      "https://drive.google.com/uc?export=download&id=13UN5UNZ-0DvLCn3SV9pevV5gRtZ2dIVJ&confirm=t"
curl -L -o es_MX-laura-high.onnx.json "https://drive.google.com/uc?export=download&id=14ZeSiVzckUSqFQYJBywIoGAhDaPRZHai"
```

Tamaño esperado del `.onnx`: 63 122 309 bytes.

## Si algo no funciona

```bash
./instalar.sh                                  # repara y muestra qué falla (✘)
ttsiro-piper --estado                          # estado del daemon (lo que lee el plasmoide)
cat $XDG_RUNTIME_DIR/ttsiro/leer.log           # último Meta+R: errores de wl-paste / piper / rubberband
cat $XDG_RUNTIME_DIR/ttsiro/daemon.log         # arranque del daemon
cat $XDG_RUNTIME_DIR/ttsiro/mpv.log            # ventana de mpv
```

Meta+R también avisa los errores con una notificación. Tras instalar por primera vez, si el atajo no responde, cierra sesión y vuelve a entrar. Los atajos y los scripts añaden `~/.local/bin` al `PATH` por su cuenta (una sesión de KDE puede no tenerlo, y ahí vive piper). El daemon se lanza en un scope propio de systemd (`systemd-run --user --scope`), así sobrevive al autostart, al atajo y a reinicios de plasmashell.

## Estructura

| Ruta | Rol |
|---|---|
| `bin/ttsirod`, `bin/ttsiro-piper` | daemon que precarga la voz y su cliente (reemplazo de `piper`) |
| `plasmoid/` | widget de la barra de Plasma: ¿voz precargada? |
| `autostart/` | precarga la voz al iniciar sesión |
| `bin/leer-laura.sh` | Meta+R: lee la selección (`wl-paste --primary`) → piper → rubberband (solo si el tono ≠ 0) → mpv |
| `bin/detener-laura.sh` | Meta+Ctrl+Shift+R: cierra el mpv de la lectura |
| `bin/piper-tts-wrapper.sh` | Okular / speech-dispatcher: lee stdin con el perfil activo |
| `bin/hablar` | lee el portapapeles con `spd-say` |
| `ui/servidor.py`, `ui/index.html` | UI local y API (`--menu`, `--sin-navegador`) |
| `speech-dispatcher/` | módulo `piper` para speechd |
| `applications/`, `autostart/` | plantillas `.desktop` con `@RAIZ@`; `instalar.sh` las genera con la ruta real |
| `activo.env`, `perfiles.json` | estado generado (no versionado) |
