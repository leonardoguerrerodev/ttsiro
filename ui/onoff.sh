#!/bin/bash
# TTSiro: inicia el servidor local con menú de terminal (ENTER lo cierra).
exec python3 "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/servidor.py" --menu "$@"
