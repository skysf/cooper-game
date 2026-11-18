#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cache="$project/.cache/blender-lab"
export BLENDER_USER_RESOURCES="$cache/profile"
blender="$cache/Blender/Blender.app/Contents/MacOS/Blender"
if [ ! -x "$blender" ]; then
    echo "Run scripts/setup-blender-mcp.sh to install the signed Blender app." >&2
    exit 1
fi
exec "$blender" --disable-autoexec --online-mode "$@"
