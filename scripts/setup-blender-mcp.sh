#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python="$project/.cache/blender-lab/server/mcp/.venv/bin/python"
if [ ! -x "$python" ]; then
    cat >&2 <<'EOF'
The Blender Lab MCP environment is missing from .cache/blender-lab/server/mcp/.venv.
Get the official Blender app and add-on from https://www.blender.org/lab/mcp-server/.
Follow the official MCP server setup at https://projects.blender.org/lab/blender_mcp/wiki/Setup.
EOF
    exit 1
fi
exec "$python" "$project/scripts/setup-blender-mcp.py" "$@"
