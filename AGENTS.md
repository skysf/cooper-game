# 雨线营地 · 项目入口

当前主线是 Godot 4.7.2 / GDScript 的第一人称合作生存样片，优先桌面浏览器，兼容 Mac 原生版。下列路径均相对项目根目录。按当前任务选读对应文档。

| 任务 | 详细文档 | 代码或数据 |
|---|---|---|
| 新窗口续接与本机试玩 | [简短交接](docs/next-session.md) | 发行目录、启动命令、存档及待优化项目 |
| 试玩、构建、运行测试 | [运行手册](docs/play.md) | `package.json`、`scripts/` |
| 网页画质、30 FPS 与改动前后对照 | [画面与帧时基准](docs/render-benchmark.md) | `scripts/coop-render-benchmark.mjs`、`scripts/coop-flight-playtest.mjs` |
| 扩展可探索区域、东部植被和洞居营地 | [东部山地](docs/world-upgrade.md#东部山地与洞居营地) | `coop/east/`、`art/field_regions/`、`scripts/build-eastern-region.py` |
| 长期模型质量、风雨植被、矿洞和建造 | [世界扩建工作记录](docs/world-upgrade.md) | `art/`、`coop/`、`evidence/` |
| 联机、存档、分块、树木成长与实测 | [合作样片](docs/coop.md) | `coop/`、`shared/coop-grove.json`、`evidence/` |
| 昼夜、湖岸水面、可拾取与投掷的石块 | [昼夜、鹿鸣湖与石块](docs/coop.md#昼夜鹿鸣湖与石块) | `coop/atmosphere.gd`、`coop/lake.gd`、`coop/stones.gd` |
| 鹿鸣湖至浅湾、外海和岛，海岸生成与实际游玩复验 | [鹿鸣湖到外海](docs/coast.md) | `coop/coast/`、`coop/coast_layout.json`、`coop/coast_scene.gd`、`scripts/build-coast.py` |
| 营地容器、拆解、燃料、木工、路牌与鳄鱼肉配方 | [营地储物与制作](docs/camp-storage.md) | `coop/camp_storage*.gd`、`coop/props/storage/` |
| M 键野外图册、传送、队友位置与个人标记 | [野外图册](docs/field-atlas.md) | `coop/field_atlas*.gd`、`scripts/build-coop-atlas.py` |
| 脚步、游泳、投石与红船音效 | [营地声音](docs/coop.md#营地声音) | `coop/camp_audio.gd`、`coop/sounds/` |
| 木桌刻字、食物、背包、服装和第三人称 | [木屋里的桌子与补给](docs/coop.md#木屋里的桌子与补给) | `art/camp_table.blend`、`art/camp_backpack.blend`、`coop/provision_scene.gd`、`coop/survival.gd`、`coop/character_preview.gd`、`coop/follow_camera.gd` |
| 玩家步态、第一人称腿脚与近战、起跳落地和游泳 | [玩家动作](docs/coop.md#玩家动作) | `coop/hiker.gd`、`coop/player_motion.gd`、`coop/player_melee_pose.gd`、`coop/animations/player_locomotion.tres` |
| 编辑角色头身与可拆眼镜、复用 NPC 骨架 | [角色制作模板](docs/coop.md#角色制作模板) | `art/characters/sky_character.blend`、`art/characters/sky_head_v3.blend` |
| 营地藏獒、收养与休息动作 | [营地藏獒](docs/coop.md#营地藏獒) | `art/animals/camp_mastiff.blend`、`coop/props/camp_mastiff.glb`、`coop/camp_dog.gd`、`coop/camp_dog_scene.gd` |
| 鹿鸣湖住船、双人划桨、绵羊剪毛与羊排 | [湖区住船与绵羊](docs/coop.md#湖区住船与绵羊) | `coop/lake_ferry.gd`、`coop/lake_sheep.gd`、`coop/lake_life_scene.gd`、`scripts/build-lake-life.py` |
| 鹿鸣湖鳄鱼、老鹰与受伤恢复 | [鹿鸣湖的鳄鱼和老鹰](docs/coop.md#鹿鸣湖的鳄鱼和老鹰) | `art/animals/`、`coop/wildlife.gd`、`coop/wildlife_scene.gd` |
| 林地野猪的动画、冲撞、取材和猎人装备 | [林地野猪](docs/coop.md#林地野猪) | `art/animals/boar_study/`、`scripts/build-wild-boar.py`、`coop/woodland_boar.gd`、`coop/woodland_boar_scene.gd` |
| 来袭者、俘虏照料、自由同伴、缴获装备与个人关系 | [来袭者与自由同伴](docs/wild-people.md) | `coop/wild_people.gd`、`coop/wild_people_scene.gd`、`coop/wild_people_panel.gd`、`coop/wild_people_config.json` |
| 制作或替换树种、草地、林地材质 | [白桦与云杉](docs/tree-species.md) · [松树模型](docs/pine-tree.md) · [材质与许可](docs/woodland-assets.md) | `coop/trees/`、`coop/pines/`、`coop/vegetation/`、`shared/textures/` |
| 接手现成素材的 Blender 改造与网页验收 | [素材交接 · 第一棵松树](docs/asset-handoff.md) | `coop/pines/`、`scripts/prepare-pines.py` |
| 修复、减面、绑定和验收生成的 3D 游戏资产 | [资产处理与案例](docs/generated-3d-assets.md) · [game-3d-blender 技能](skills/game-3d-blender/SKILL.md) | `art/`、`art/animals/` |
| 修改木屋油灯、修屋点灯效果 | [木屋防风油灯](docs/coop.md#木屋防风油灯) | `art/camp_lantern.blend`、`coop/props/`、`coop/terrain.gd` |
| 接入 Blender 与 MCP | [本机美术工具](docs/blender-mcp.md) | `scripts/setup-blender-mcp.sh`、`scripts/start-blender.sh` |
| 复查引擎选型与原始 A/B | [引擎对比报告](docs/engine-comparison.md) | `web/`、`godot/`、`shared/layout.json` |

项目只维护这一份 `AGENTS.md`。长期有效的决定、操作步骤和验证记录写入 `docs/` 对应主题；新增主题时在此补一行索引。原始测量和截图留在 `evidence/`，按需查看。
