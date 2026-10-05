# TTSiro

Lector en voz alta local para Linux/KDE con [piper](https://github.com/OHF-Voice/piper1-gpl): **Meta+R** lee la selección, **Okular** lee por speech-dispatcher, y una UI web local (`ui/servidor.py`) configura perfiles de voz.

La carpeta no tiene rutas absolutas: se puede mover o clonar donde sea.

## Instalar (otro PC)

```bash
git clone <este repo> && cd TTSiro
./instalar.sh              # --dry-run para ver qué haría; --solo-enlaces para saltarse paquetes
```

`instalar.sh` detecta la distro (dnf, apt, pacman, zypper), instala `mpv`, `rubberband`, `wl-clipboard`, `speech-dispatcher`, `pipx` y piper, crea los symlinks (`~/.local/bin`, `~/.local/share/applications`, `~/.config/speech-dispatcher`, `~/.local/share/piper`), registra los atajos de KDE (Meta+R leer, Meta+Ctrl+Shift+R detener) y deja un perfil inicial. Es idempotente. Si ya hay una carpeta real en un destino, la respalda como `.bak.<timestamp>`.

## Configurar voz

```bash
python3 ui/servidor.py        # abre http://127.0.0.1:8765  (o ./ui/onoff.sh para menú de terminal)
```

Desde la UI: perfiles (voz, velocidad, tono, volumen, expresividad, variación, pausa), **Probar**, **Guardar** y **Activar** (el perfil activo se escribe en `activo.env`, que releen Meta+R y Okular en cada lectura). El desplegable **Descargar** baja voces en español del catálogo público de piper (Hugging Face), así que los modelos `.onnx` no van en el repo (`voces/` está en `.gitignore`).

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

## Estructura

| Ruta | Rol |
|---|---|
| `bin/leer-laura.sh` | Meta+R: lee la selección (`wl-paste --primary`) → piper → rubberband → mpv |
| `bin/piper-tts-wrapper.sh` | Okular / speech-dispatcher: lee stdin con el perfil activo |
| `bin/hablar` | lee el portapapeles con `spd-say` |
| `ui/servidor.py`, `ui/index.html` | UI local y API (`--menu`, `--sin-navegador`) |
| `speech-dispatcher/` | módulo `piper` para speechd |
| `applications/` | `.desktop` de los atajos y de la UI |
| `activo.env`, `perfiles.json` | estado generado (no versionado) |
