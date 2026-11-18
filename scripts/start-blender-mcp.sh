#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cache="$project/.cache/blender-lab"
export BLENDER_USER_RESOURCES="$cache/profile"
export BLENDER_PATH="$cache/Blender/Blender.app/Contents/MacOS/Blender"
exec "$cache/server/mcp/.venv/bin/blender-mcp" "$@"
