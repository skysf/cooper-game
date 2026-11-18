# 雨线营地 · 项目入口

当前主线是 Godot 4.7.2 / GDScript 的第一人称合作生存样片，优先桌面浏览器，兼容 Mac 原生版。下列路径均相对项目根目录。按当前任务选读对应文档。

| 任务 | 详细文档 | 代码或数据 |
|---|---|---|
| 试玩、构建、运行测试 | [运行手册](docs/play.md) | `package.json`、`scripts/` |
| 联机、存档、分块、树木成长与实测 | [合作样片](docs/coop.md) | `coop/`、`shared/coop-grove.json`、`evidence/` |
| 昼夜、湖岸水面、可拾取与投掷的石块 | [昼夜、鹿鸣湖与石块](docs/coop.md#昼夜鹿鸣湖与石块) | `coop/atmosphere.gd`、`coop/lake.gd`、`coop/stones.gd` |
| 木桌刻字、桌上食物、背包和角色状态 | [木屋里的桌子与补给](docs/coop.md#木屋里的桌子与补给) | `art/camp_table.blend`、`coop/provision_scene.gd`、`coop/survival.gd` |
| 制作或替换树种、林地材质 | [白桦与云杉](docs/tree-species.md) · [松树模型](docs/pine-tree.md) · [材质与许可](docs/woodland-assets.md) | `coop/trees/`、`coop/pines/`、`shared/textures/` |
| 接手现成素材的 Blender 改造与网页验收 | [素材交接 · 第一棵松树](docs/asset-handoff.md) | `coop/pines/`、`scripts/prepare-pines.py` |
| 修改木屋油灯、修屋点灯效果 | [木屋防风油灯](docs/coop.md#木屋防风油灯) | `art/camp_lantern.blend`、`coop/props/`、`coop/terrain.gd` |
| 接入 Blender 与 MCP | [本机美术工具](docs/blender-mcp.md) | `scripts/setup-blender-mcp.sh`、`scripts/start-blender.sh` |
| 复查引擎选型与原始 A/B | [引擎对比报告](docs/engine-comparison.md) | `web/`、`godot/`、`shared/layout.json` |

项目只维护这一份 `AGENTS.md`。长期有效的决定、操作步骤和验证记录写入 `docs/` 对应主题；新增主题时在此补一行索引。原始测量和截图留在 `evidence/`，按需查看。
