#!/usr/bin/env bash
set -euo pipefail

release=4.7.2-stable
case "${RUNNER_OS:?}" in
  Linux)
    archive="Godot_v${release}_linux.x86_64.zip"
    checksum=cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
    executable="Godot_v${release}_linux.x86_64"
    ;;
  macOS)
    archive="Godot_v${release}_macos.universal.zip"
    checksum=c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e
    executable=Godot.app/Contents/MacOS/Godot
    ;;
  *)
    printf 'Unsupported Godot runner OS: %s\n' "$RUNNER_OS" >&2
    exit 1
    ;;
esac

install_dir=$(mktemp -d "${RUNNER_TEMP:?}/godot.XXXXXX")
cd "$install_dir"
curl --fail --location --silent --show-error --retry 3 \
  "https://github.com/godotengine/godot-builds/releases/download/$release/$archive" \
  --output "$archive"
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check
unzip -q "$archive"
chmod +x "$executable"
"$install_dir/$executable" --headless --version
printf 'GODOT_BIN=%s/%s\n' "$install_dir" "$executable" >> "${GITHUB_ENV:?}"
