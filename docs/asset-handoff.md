# 新窗口交接 · 第一棵网页版松树

游戏已选 Godot 4.7.2 标准版、GDScript、Compatibility / WebGL 2。目标机器是 Apple M1、16 GB。主游戏目录是 `coop/`；`godot/`、`web/` 是历史引擎对照样片。项目网页优先，后续希望上 Steam 并和朋友联机，目前已有同网合作样片。

## 从现状接手

- 场内有四株松树、两株白桦、两株云杉参与成长。每种树都有幼苗、幼树、成树三个树龄模型。位置与初始树龄见 `shared/coop-grove.json`，房间成长时钟和模型切换见 `coop/grove.gd`。[合作样片](coop.md)
- 第一件素材用项目现有的 Poly Haven **Pine Tree 01**（CC0）。现有成树 `coop/pines/pine_mature.glb` 高 7 米、4,158 个三角面，已有真实树皮和针叶纹理，可直接作为改造前基准。源资产处理脚本是 `scripts/prepare-pines.py`。[松树来源与生成方法](pine-tree.md)
- Blender 5.2.4 LTS 和 Blender Lab MCP 已安装。项目启动器是 `./scripts/start-blender.sh`。已有 `art/camp_lantern.blend`、`scripts/build-camp-lantern.py` 和 `coop/props/camp_lantern.glb` 可参考从 Blender 源文件到游戏模型的流程。尽量脚本化，无需用户手动搭场景。[工具与后台启动](blender-mcp.md)
- 用户分享的 Sketchfab 松树包为备选；此前官方下载需要登录，项目中没有该包。若以后采用，需保留作者、原作及 CC BY 4.0 链接，注明改动。[树种与许可记录](tree-species.md)

## 下一项交付

1. **先留基准。** 在现有林道挑一株成松，记下机位、距离、天气并截图。检查 Godot 已导入的网格有没有自动 LOD、原有远景树片何时接替。成树固定在同一树龄，以便比较。
2. **在 Blender 改一棵。** 近看优先保住树皮和主枝，中景保树冠层次，远景保轮廓并减少透明针叶重叠。近、中、远代表同一棵树的观察距离；幼苗、幼树、成树代表生长时间，两者需要独立工作。保留地面原点、米制高度、树点 ID、碰撞与联网成长。交付可编辑的 `.blend`、游戏用 GLB、可重复的导出方法。记录作者、许可和具体改动。
3. **在实际游戏里验收。** 用同一台 M1、同一有窗口浏览器、实际 1280 × 720 和同一路线对比改造前后。走近看树皮，再退远看树冠切换是否突跳。用相同数量和位置的树比较晴天、雨天的平均 FPS 与 P95 帧耗时，记录采样时长、模型面数和下载体积。将同机位截图和测量放在 `evidence/`。根据结果决定是否扩展到整片林地。

从项目根目录运行 `npm run coop:build` 重建，再用 `npm run coop:lan` 启动。[本机试玩](http://localhost:4184/coop/?room=pine) · [试玩与测试手册](play.md)

## 后续素材方向

背包可以从允许修改和商用的基础模型开始，在 Blender 改肩带、扣具和磨损，上身检查走跑时的穿插。角色优先选骨架、蒙皮和动画许可明确的基础人体，先在 Godot 验证走、跑、蹲。图片转 3D 可用于有独特轮廓的静态道具。三类工作按需要逐件开启。
