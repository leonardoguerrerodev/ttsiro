#!/bin/bash
# Lee en voz alta el portapapeles (Wayland o X11) con speech-dispatcher.
if command -v wl-paste >/dev/null; then TEXT=$(wl-paste 2>/dev/null)
else TEXT=$(xclip -selection clipboard -o 2>/dev/null); fi

if [ -n "$TEXT" ]; then
    echo "$TEXT" | fold -s -w 200 | while read -r line; do
        spd-say --wait "$line"
    done
fi
