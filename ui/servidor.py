#!/usr/bin/env python3
"""TTSiro: UI local para configurar y probar el lector (piper).

Sirve ui/index.html en http://127.0.0.1:8765, sintetiza pruebas y guarda perfiles.
El perfil activo se escribe en activo.env, que leen leer-laura.sh (Meta+R) y
piper-tts-wrapper.sh (Okular) en cada lectura.
Con --menu muestra un menú de terminal y cierra el servidor al pulsar ENTER.
"""
import json, math, os, shutil, subprocess, sys, tempfile, threading, urllib.request, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PUERTO = 8765
RAIZ = Path(__file__).resolve().parent.parent
VOCES = RAIZ / "voces"
PERFILES = RAIZ / "perfiles.json"
ACTIVO_ENV = RAIZ / "activo.env"
HF = "https://huggingface.co/rhasspy/piper-voices/resolve/main/"
IDIOMA = "es"  # familia de idioma que ofrece el catálogo
PIPER = shutil.which("piper") or shutil.which("piper", path=str(Path.home() / ".local" / "bin"))  # un lanzador de KDE puede no tener ~/.local/bin en PATH
RUBBERBAND = shutil.which("rubberband")

# campo: (mínimo, máximo, por defecto)
RANGOS = {
    "velocidad": (50, 150, 85),       # % de la velocidad normal
    "tono": (-6, 6, 1),               # semitonos (rubberband)
    "volumen": (10, 200, 100),        # %
    "expresividad": (0, 1.5, 1.0),    # piper noise_scale
    "ritmo": (0, 1.5, 0.9),           # piper noise_w
    "pausa": (0, 2, 0),               # segundos de silencio entre oraciones
}


def escribir(ruta, texto):
    tmp = ruta.with_name(ruta.name + ".tmp")
    tmp.write_text(texto)
    os.replace(tmp, ruta)


_catalogo = None


def catalogo():
    """Voces públicas de piper en el idioma configurado: {clave: {calidad, mb, archivos}} (se baja una vez)."""
    global _catalogo
    if _catalogo is None:
        with urllib.request.urlopen(HF + "voices.json", timeout=20) as r:
            todo = json.load(r)
        _catalogo = {k: {"calidad": v["quality"], "archivos": sorted((f for f in v["files"] if f.endswith((".onnx", ".onnx.json"))), reverse=True),
                         "mb": round(sum(x["size_bytes"] for x in v["files"].values()) / 1e6)}
                     for k, v in todo.items() if v["language"]["family"] == IDIOMA}
    return _catalogo


def descargar(clave):
    voz = catalogo().get(clave)
    if not voz:
        raise ValueError(f"voz fuera del catálogo: {clave}")
    VOCES.mkdir(exist_ok=True)
    for ruta in voz["archivos"]:
        destino = VOCES / Path(ruta).name
        tmp = destino.with_name(destino.name + ".part")
        with urllib.request.urlopen(HF + ruta, timeout=30) as r, open(tmp, "wb") as f:
            shutil.copyfileobj(r, f)
        os.replace(tmp, destino)  # el .json va primero (orden inverso): la voz aparece en la lista solo cuando ya está completa


def voces():
    return sorted(p.name[:-5] for p in VOCES.glob("*.onnx"))


def limpiar(perfil):
    """Valida un perfil que viene del navegador: voz conocida y números acotados."""
    voz = perfil.get("voz")
    if voz not in voces():
        raise ValueError(f"voz desconocida: {voz}")
    limpio = {"voz": voz}
    for campo, (lo, hi, defecto) in RANGOS.items():
        valor = float(perfil.get(campo, defecto))
        if not math.isfinite(valor):
            raise ValueError(f"{campo} inválido")
        limpio[campo] = min(hi, max(lo, valor))
    return limpio


def args_piper(p):
    if not PIPER:
        raise RuntimeError("No se encontró piper en PATH")
    return [str(RAIZ / "bin" / "ttsiro-piper"), "-m", str(VOCES / f"{p['voz']}.onnx"),
            "--length-scale", f"{100 / p['velocidad']:.3f}",
            "--noise-scale", str(p["expresividad"]), "--noise-w", str(p["ritmo"]),
            "--volume", f"{p['volumen'] / 100:.2f}", "--sentence-silence", str(p["pausa"])]


def sintetizar(p, texto):
    with tempfile.TemporaryDirectory() as tmp:
        crudo, final = Path(tmp, "a.wav"), Path(tmp, "b.wav")
        subprocess.run(args_piper(p) + ["-f", str(crudo)], input=texto.encode(),
                       check=True, capture_output=True, timeout=120)
        if p["tono"]:
            if not RUBBERBAND:
                raise RuntimeError("No se encontró rubberband en PATH")
            subprocess.run([RUBBERBAND, "--pitch", str(p["tono"]), str(crudo), str(final)],
                           check=True, capture_output=True, timeout=120)
            return final.read_bytes()
        return crudo.read_bytes()


def escribir_env(p):
    tasa = json.loads((VOCES / f"{p['voz']}.onnx.json").read_text())["audio"]["sample_rate"]
    # $RAIZ lo define cada script antes de hacer source: así la carpeta se puede mover.
    escribir(ACTIVO_ENV,
        "# Generado por TTSiro (ui/servidor.py). No editar a mano.\n"
        f"MODELO=\"$RAIZ/voces/{p['voz']}.onnx\"\nTASA={tasa}\n"
        f"VELOCIDAD={100 / p['velocidad']:.3f}\nEXPRESIVIDAD={p['expresividad']}\n"
        f"RITMO={p['ritmo']}\nVOLUMEN={p['volumen'] / 100:.2f}\nPAUSA={p['pausa']}\n"
        f"TONO={p['tono']}\nTONO_ESCALA={2 ** (p['tono'] / 12):.4f}\n")


def leer_estado():
    if PERFILES.exists():
        return json.loads(PERFILES.read_text())
    todas = voces()
    voz = "es_MX-laura-high" if "es_MX-laura-high" in todas else todas[0]
    return {"activo": "Predeterminado", "perfiles": {"Predeterminado": limpiar({"voz": voz})}}


class Handler(BaseHTTPRequestHandler):
    def _responder(self, codigo, cuerpo, tipo="application/json"):
        if isinstance(cuerpo, (dict, list)):
            cuerpo = json.dumps(cuerpo).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def _host_valido(self):
        # Contra DNS rebinding: solo se atiende a quien llama a este host exacto.
        return self.headers.get("Host") in (f"127.0.0.1:{PUERTO}", f"localhost:{PUERTO}")

    def do_GET(self):
        if not self._host_valido():
            return self._responder(403, {"error": "host"})
        if self.path == "/":
            return self._responder(200, (Path(__file__).parent / "index.html").read_bytes(),
                                   "text/html; charset=utf-8")
        if self.path == "/api/estado":
            return self._responder(200, {"voces": voces(), "rangos": RANGOS, **leer_estado()})
        if self.path == "/api/catalogo":
            try:
                instaladas = set(voces())
                return self._responder(200, [{"clave": k, "calidad": v["calidad"], "mb": v["mb"]}
                                             for k, v in sorted(catalogo().items()) if k not in instaladas])
            except OSError as e:
                return self._responder(502, {"error": f"sin acceso al catálogo: {e}"})
        self._responder(404, {"error": "no existe"})

    def do_POST(self):
        # Exigir JSON obliga a un preflight CORS que este servidor no responde:
        # ninguna web externa puede mandar POST aquí.
        if not self._host_valido() or self.headers.get("Content-Type") != "application/json":
            return self._responder(403, {"error": "origen"})
        try:
            largo = int(self.headers.get("Content-Length", 0))
            if not 0 < largo <= 65536:
                raise ValueError("cuerpo inválido")
            datos = json.loads(self.rfile.read(largo))
            if self.path == "/api/probar":
                texto = str(datos.get("texto", "")).strip()[:3000]
                if not texto:
                    raise ValueError("texto vacío")
                return self._responder(200, sintetizar(limpiar(datos["perfil"]), texto), "audio/wav")
            if self.path == "/api/descargar":
                descargar(str(datos.get("voz")))
                return self._responder(200, {"ok": True})
            if self.path == "/api/guardar":
                perfiles = {str(n)[:40]: limpiar(p) for n, p in datos["perfiles"].items() if str(n).strip()}
                activo = datos.get("activo")
                if activo not in perfiles:
                    raise ValueError("el perfil activo no existe")
                escribir(PERFILES, json.dumps({"activo": activo, "perfiles": perfiles},
                                              indent=2, ensure_ascii=False))
                escribir_env(perfiles[activo])
                return self._responder(200, {"ok": True})
            self._responder(404, {"error": "no existe"})
        except (ValueError, KeyError, TypeError, AttributeError, json.JSONDecodeError) as e:
            self._responder(400, {"error": str(e)})
        except OSError as e:
            self._responder(502, {"error": f"falló la descarga: {e}"})
        except (subprocess.SubprocessError, RuntimeError) as e:
            self._responder(500, {"error": f"falló la síntesis: {e}"})

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    url = f"http://127.0.0.1:{PUERTO}/"
    try:
        servidor = ThreadingHTTPServer(("127.0.0.1", PUERTO), Handler)
    except OSError:  # ya está corriendo: solo abrir la página
        webbrowser.open(url)
        sys.exit(0)
    if "--sin-navegador" not in sys.argv:
        webbrowser.open(url)
    if "--menu" not in sys.argv:
        servidor.serve_forever()
    print(f"\n{'=' * 55}\n  TTSiro - SERVIDOR LOCAL ACTIVO\n{'=' * 55}\n  URL: {url}\n"
          f"\n  Presiona ENTER para terminar el localhost.\n{'=' * 55}\n")
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
    try:
        input()
    except (KeyboardInterrupt, EOFError):
        pass
    print("Cerrando localhost...")
    servidor.shutdown()
    servidor.server_close()
