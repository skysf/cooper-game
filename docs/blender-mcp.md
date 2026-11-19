# Blender 与 Codex

本机美术工具采用 Blender 5.2.4 LTS（Apple Silicon）和 Blender Lab MCP 1.0.3。Blender 及其独立用户配置位于项目的 `.cache/blender-lab/`。运行游戏只需营地服务。[官方 Blender Lab MCP](https://www.blender.org/lab/mcp-server/)

## 日常使用

在项目根目录执行 `./scripts/start-blender.sh` 打开带扩展的 Blender。扩展默认在本机回环端口 9876 接收连接。Codex 注册的 stdio 名称为 `blender`，启动命令指向本项目的 [start-blender-mcp.sh](../scripts/start-blender-mcp.sh)。注册完成后新建 Codex 会话可加载工具。其他 MCP 客户端也可以把该脚本的绝对路径配置为 stdio 命令。

## 后台启动与 Metal

后台脚本、安装验收及 MCP 后台工具共用项目启动器。以下命令可检查本机 Blender 能否完整启动并执行 Python。

```sh
./scripts/start-blender.sh --background --factory-startup --python-expr \
  'import bpy; print(bpy.app.version_string)'
```

随项目配置的 Blender 5.2.4 在启动时查询默认 Metal 设备。该构建的 `--gpu-backend` 只支持 `metal`，后台模式和 Cycles CPU 渲染也会经过启动检测。设备不可用时，Blender 可能在执行 Python 前崩溃，堆栈指向 `supports_barycentric_whitelist`。[Blender 上游问题 #163272](https://projects.blender.org/blender/blender/issues/163272)

启动器先检查当前会话能否访问默认 Metal 设备。如果出现 `Blender Metal preflight failed`，从普通 macOS Terminal 用原参数重试。Codex 可为这次 Blender 命令请求 `sandbox_permissions=require_escalated`。单独执行 `./scripts/start-blender.sh --version` 或 `--help` 仍可在受限会话查看版本和帮助。

2026-11-19，在 Apple M1、macOS 26.5.2 上实测。默认 Codex 沙箱的 Metal 探针返回空设备，三次后台启动均在预检时退出并返回状态码 1，MCP 后台工具也返回预检提示。Blender 崩溃日志未更新。放行后，探针读到 `Apple M1`，三次后台启动通过。另存并复开临时 `.blend` 后，Cycles CPU 完成 64 × 64 PNG 渲染并成功读回。MCP 后台文件读取和独立回环桥接也通过。

## 安装与核对

在普通 macOS Terminal 的项目目录运行 `./scripts/setup-blender-mcp.sh`。脚本使用预备的本地依赖，验签、启用扩展、在独立空场景进行只读测试，并注册到 Codex。运行 `codex mcp get blender --json` 可核对注册路径和 `enabled` 状态。单独运行 `./scripts/setup-blender-mcp.sh --stdio-only` 可检查协议握手、工具目录和 API 文档查询。[安装入口](../scripts/setup-blender-mcp.sh) · [安装与验收逻辑](../scripts/setup-blender-mcp.py)

2026-11-18，用户终端已验证官方安装盘 SHA-256 与应用签名、安装扩展并启动 Blender。MCP 枚举出 26 个工具，实际读回独立空场景 `Blender Lab MCP Smoke Test`。官方扩展将场景放在响应的 `result` 层，项目验收脚本已适配该结构。随后使用 Codex CLI 完成注册并读回 `enabled: true`。空场景测试进程在验收后退出；在普通 macOS Terminal 启动日常 Blender 会话后，保持窗口打开即可继续连接。
