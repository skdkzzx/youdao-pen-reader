#!/bin/sh

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if command -v python3 >/dev/null 2>&1; then
    exec python3 "$PLUGIN_DIR/uploader.py"
fi

if command -v node >/dev/null 2>&1; then
    exec node "$PLUGIN_DIR/uploader.js"
fi

# built-in shell server — no python3/node needed
exec /bin/sh "$PLUGIN_DIR/uploader.sh"
