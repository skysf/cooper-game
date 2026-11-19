#!/bin/sh
set -eu
scripts=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$scripts/exec-blender.sh" --disable-autoexec --online-mode "$@"
