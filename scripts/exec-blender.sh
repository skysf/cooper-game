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

# Help and version requests exit before Blender initializes the GPU.
for argument in "$@"; do
    case "$argument" in
        --disable-autoexec|--online-mode) continue ;;
        -h|--help|'/?'|-v|--version) exec "$blender" "$@" ;;
        *) break ;;
    esac
done

# Blender 5.2.4 can crash if the default Metal device is missing at startup.
if ! metal_device=$(/usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import("Metal");
const device = $.MTLCreateSystemDefaultDevice();
const name = device.isNil() ? "" : ObjC.unwrap(device.name);
typeof name === "string" ? name : "";
JXA
) || [ -z "$metal_device" ]; then
    cat >&2 <<'EOF'
Blender Metal preflight failed because this session could not report a usable default Metal device.
Run ./scripts/start-blender.sh with the same arguments from a regular macOS Terminal.
In Codex, request sandbox_permissions=require_escalated for the Blender launch.
EOF
    exit 1
fi

exec "$blender" "$@"
