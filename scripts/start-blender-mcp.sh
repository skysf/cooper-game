#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cache="$project/.cache/blender-lab"
export BLENDER_PATH="$project/scripts/exec-blender.sh"
exec "$cache/server/mcp/.venv/bin/blender-mcp" "$@"
