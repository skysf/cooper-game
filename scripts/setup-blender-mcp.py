import argparse
import asyncio
from hashlib import file_digest
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


PROJECT = Path(__file__).resolve().parents[1]
CACHE = PROJECT / ".cache/blender-lab"
APP = CACHE / "Blender/Blender.app"
DMG = CACHE / "downloads/blender-5.2.4-macos-arm64.dmg"
DMG_SHA256 = "e73d564f97061b2496ccc5a0bd738937d2d3d0acae23621a00bbc7534dfd135f"
ADDON = CACHE / "downloads/mcp-1.0.3.zip"
BLENDER = PROJECT / "scripts/exec-blender.sh"
LAUNCHER = PROJECT / "scripts/start-blender-mcp.sh"
SCENE_NAME = "Blender Lab MCP Smoke Test"
LOCALHOST = "127.0.0.1"


def install_blender():
    """Install the verified Apple Silicon release using macOS bundle copy tools."""
    requirement = (
        '=identifier "org.blenderfoundation.blender" and anchor apple generic '
        'and certificate leaf[subject.OU] = "68UA947AUU"'
    )
    verify = ["/usr/bin/codesign", "--verify", "--deep", "--strict"]
    check_signer = ["/usr/bin/codesign", "--verify", "-R", requirement]
    if APP.is_dir():
        subprocess.run([*verify, APP], check=True)
        subprocess.run([*check_signer, APP], check=True)
        print("Blender app signature verified.", flush=True)
        return

    if not DMG.is_file():
        raise FileNotFoundError(
            f"Download {DMG.name} from https://download.blender.org/release/Blender5.2/ "
            f"and place it at {DMG}."
        )
    with DMG.open("rb") as image:
        if file_digest(image, "sha256").hexdigest() != DMG_SHA256:
            raise RuntimeError("Official Blender 5.2.4 disk image failed SHA-256 verification.")
    print("Blender 5.2.4 disk image SHA-256 verified.", flush=True)

    APP.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="install-", dir=APP.parent) as directory:
        staged_app = Path(directory) / APP.name
        mountpoint = Path(tempfile.mkdtemp(prefix="image-", dir=CACHE))
        try:
            subprocess.run(
                ["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                 "-mountpoint", mountpoint, DMG],
                check=True,
            )
            try:
                subprocess.run(
                    ["/usr/bin/ditto", "--rsrc", "--extattr", "--acl", mountpoint / APP.name, staged_app],
                    check=True,
                )
            finally:
                subprocess.run(["/usr/bin/hdiutil", "detach", mountpoint], check=True)
        finally:
            if not os.path.ismount(mountpoint):
                mountpoint.rmdir()

        subprocess.run([*verify, staged_app], check=True)
        subprocess.run([*check_signer, staged_app], check=True)
        staged_app.rename(APP)
        print("Blender app installed and signature verified.", flush=True)


def validate_smoke_scene(data):
    if not isinstance(data, dict) or data.get("status") != "ok":
        raise RuntimeError(f"Blender scene request failed: {data}")
    scene = data.get("result", data)
    if not isinstance(scene, dict) or scene.get("status") != "ok" or scene.get("scene_name") != SCENE_NAME:
        raise RuntimeError(f"Unexpected Blender smoke scene: {data}")


async def check_mcp(port=None):
    """Check the official MCP process and, optionally, the isolated Blender scene."""
    env = {}
    if port is not None:
        env.update(BLENDER_MCP_HOST=LOCALHOST, BLENDER_MCP_PORT=str(port))

    params = StdioServerParameters(command=str(LAUNCHER), env=env)
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            hello = await session.initialize()
            if hello.serverInfo.name != "blender-mcp":
                raise RuntimeError(f"Unexpected MCP server {hello.serverInfo.name!r}")
            tools = await session.list_tools()
            docs = await session.call_tool("search_api_docs", {"query": "bpy.types.Object", "max_results": 1})
            if docs.isError or not docs.content:
                raise RuntimeError(f"Blender API documentation tool failed: {docs.content}")
            print(f"MCP stdio OK. Protocol {hello.protocolVersion}, {len(tools.tools)} tools, API search OK.", flush=True)
            if port is None:
                return

            summary = await session.call_tool("get_objects_summary", {})
            if summary.isError:
                raise RuntimeError(f"Blender scene read failed: {summary.content}")
            data = summary.structuredContent
            if data is None:
                data = json.loads(summary.content[0].text)
            validate_smoke_scene(data)
            print(f"Blender scene read OK. Read-only summary returned {SCENE_NAME!r}.", flush=True)


def run_blender_smoke():
    profile = CACHE / "profile"
    scratch = CACHE / "smoke"
    profile.mkdir(exist_ok=True)
    scratch.mkdir(exist_ok=True)
    subprocess.run(
        [BLENDER, "--command", "extension", "install-file", "-r", "user_default", "-e", ADDON],
        check=True,
    )
    with tempfile.TemporaryDirectory(prefix="scene-", dir=scratch) as directory:
        scene_file = Path(directory) / "empty.blend"
        script = (
            "import bpy; bpy.ops.wm.read_factory_settings(use_empty=True); "
            f"bpy.context.scene.name = {SCENE_NAME!r}; "
            f"bpy.ops.wm.save_as_mainfile(filepath={str(scene_file)!r})"
        )
        subprocess.run(
            [BLENDER, "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1",
             "--python-expr", script],
            check=True,
        )

        with socket.socket() as reservation:
            reservation.bind((LOCALHOST, 0))
            port = reservation.getsockname()[1]

        with tempfile.TemporaryFile(mode="w+", dir=directory) as log:
            process = subprocess.Popen(
                [BLENDER, "--background", "--disable-autoexec", "--online-mode", scene_file,
                 "--command", "blender_mcp", "--host", LOCALHOST, "--port", str(port)],
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            try:
                deadline = time.monotonic() + 30
                while process.poll() is None and time.monotonic() < deadline:
                    try:
                        with socket.create_connection((LOCALHOST, port), timeout=0.5):
                            break
                    except OSError:
                        time.sleep(0.2)
                else:
                    raise RuntimeError("Blender did not start its loopback MCP bridge")
                asyncio.run(asyncio.wait_for(check_mcp(port), timeout=30))
            except Exception:
                log.seek(0)
                print(log.read(), flush=True)
                raise
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


def configure_codex(codex):
    config = json.loads(subprocess.check_output([codex, "mcp", "list", "--json"], text=True))
    existing = next((server for server in config if server["name"] == "blender"), None)
    if existing is None:
        subprocess.run([codex, "mcp", "add", "blender", "--", LAUNCHER], check=True)
    elif existing["transport"].get("command") != str(LAUNCHER) or not existing["enabled"]:
        raise RuntimeError("A different or disabled 'blender' MCP entry already exists in Codex.")

    registered = json.loads(
        subprocess.check_output([codex, "mcp", "get", "blender", "--json"], text=True)
    )
    if registered["transport"].get("command") != str(LAUNCHER) or not registered["enabled"]:
        raise RuntimeError("Codex did not retain the Blender MCP entry.")
    print("Codex MCP 'blender' is registered. Open a new Codex session to load the entry.", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Install and verify the project-local Blender Lab MCP.")
    parser.add_argument("--stdio-only", action="store_true", help="Verify the local MCP process without starting Blender.")
    parser.add_argument("--check-live", action="store_true", help="Verify an already-running isolated smoke-scene bridge.")
    parser.add_argument("--port", type=int, default=9876)
    args = parser.parse_args()

    if args.stdio_only or args.check_live:
        port = args.port if args.check_live else None
        asyncio.run(asyncio.wait_for(check_mcp(port), timeout=30))
        return

    codex = shutil.which("codex") or (Path.home() / ".local/bin/codex")
    if not Path(codex).is_file():
        parser.exit(1, "Codex CLI was not found. Install the Codex CLI before completing setup.\n")
    try:
        if not ADDON.is_file():
            raise FileNotFoundError(
                f"Download {ADDON.name} from https://projects.blender.org/lab/blender_mcp/releases/tag/v1.0.3 "
                f"and place it at {ADDON}."
            )
        install_blender()
        run_blender_smoke()
        configure_codex(codex)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Blender MCP setup stopped: {error}\n")


if __name__ == "__main__":
    main()
