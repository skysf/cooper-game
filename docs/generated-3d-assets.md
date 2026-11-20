# 生成的 3D 资产处理

在营地项目内处理 AI 生成的 GLB、Blender 模型修复、减面、贴图、绑定和动画时，读取 [game-3d-blender](../skills/game-3d-blender/SKILL.md)。本机 Blender 后台入口、用户配置和 MCP 验收步骤见 [Blender 与 Codex](blender-mcp.md)。

## 已验证的案例

| 资产 | 实际采用的做法 |
|---|---|
| [背包](../art/camp_backpack.blend) | 将约 149 万个三角面降到 6,000，保住肩带空隙、腰带和包体轮廓。左右肩带与腰带用四个形态键适配。 |
| [裤子](../art/camp_pants.blend) · [夹克](../art/camp_jacket.blend) · [帽子](../art/camp_cap.blend) | 裤腰和裤脚去除内部封面，保留服装外边缝。夹克降低面数时要对照 PBR 渲染，薄布和袖口保形优先。帽子清除误生的侧帽檐，再修侧面曲率和布纹。 |
| [藏獒](../art/animals/camp_mastiff.blend) | 修掉重复卷尾，校正后腿休止姿态。验证跑步、进食、扑咬和左前腿跛行时的变形与触地。后续新增动作和运行约定见 [营地藏獒](coop.md#营地藏獒)。 |
| [鳄鱼](../art/animals/camp_crocodile.blend) · [老鹰](../art/animals/camp_eagle.blend) | 鳄鱼把闭合嘴部拆成可动下颌和口腔，按曲线重排原模尾巴并验证摆尾和近地扑咬。老鹰把折翼做成形态键与骨骼同轨导出，`PerchContact` 按约 9 cm 枝径校准。运行约定见 [鹿鸣湖的鳄鱼和老鹰](coop.md#鹿鸣湖的鳄鱼和老鹰)。 |

同一资产在 Blender 源目录和 `coop/` 运行目录可能有不同版本。核对具体包围盒、面数或动画时，检查实际交付或加载的文件。

## 营地开局武器

游戏构建直接使用 `coop/weapons/` 中的模型与贴图。要重导出模型和背包图标，从下方素材页下载三件模型的 4K Blender 版本，分别解包到 `art/weapons/source/<素材名>_4k.blend/`，保留同名的 `.blend` 文件和 `textures/` 子目录，然后在项目根目录运行 `./scripts/start-blender.sh --background --python-exit-code 1 --python scripts/build-camp-weapons.py`。

日本刀、带瞄准镜的栓动步枪和手枪的可见组合分别有 6,670、19,365、16,650 个三角面。游戏保留完整网格及 4K 底色和法线，粗糙度和金属度打包为 2K，镜片透明底色为 1K。Godot 导入时生成 mipmaps，并使用 Basis Universal 压缩。持握点、瞄具定位点和地面接触在游戏坐标下校对。

三件模型由 Poly Haven 以 CC0 1.0 发布。日本刀由 Tal Swicegood 制作，两把枪由 Mateusz Sadek 制作。 [日本刀](https://polyhaven.com/a/antique_katana_01) · [步枪](https://polyhaven.com/a/bolt_action_rifle_7_62) · [手枪](https://polyhaven.com/a/service_pistol) · [许可](https://polyhaven.com/license)
