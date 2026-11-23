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

## 煤块与铁矿拾取件

煤块和铁矿各保留 396 个三角形与原有接地点。煤块的亮哑纹理沿断面延续，铁矿的钢灰矿粒与红褐氧化斑分布在连续的矿物和母岩表面。两件各用一个材质，颜色与法线为 512 像素，粗糙度为 256 像素。实拍覆盖实际木屋桌面、手臂距离和雨天脚边。双人房间验证了采出、落地、捡回和上桌的坐标与数量。 [正式 Blender 源件](../art/mines/rainline_mines.blend) · [煤块同机位](../evidence/mineral-pickups-20261120/coal-same-camera.jpg) · [铁矿同机位](../evidence/mineral-pickups-20261120/iron_ore-same-camera.jpg) · [采集和拾回坐标](../evidence/mineral-pickups-20261120/mined-pickup-authority.json)

从项目根目录用下面两步重导出拾取件。第一步读取源件里的 `coal` 和 `iron_ore` 场景以及已打包的贴图。第二步用装有 Pillow 的 Python 生成运行 GLB、外置贴图与 Godot 导入参数，输出在临时目录中的 `runtime/coop/props/mines`。 [拾取件导出脚本](../scripts/refine-mine-pickups.py)

```sh
pickup_output=$(mktemp -d)
./scripts/start-blender.sh --background art/mines/rainline_mines.blend \
  --python-exit-code 1 --python scripts/refine-mine-pickups.py -- export "$pickup_output/raw"
python3 scripts/refine-mine-pickups.py pack "$pickup_output/raw" "$pickup_output/runtime"
```

## 乐山大佛与大脚趾甲尺度

佛像是参照乐山大佛坐姿制作的独立游戏雕刻，足底基准面至螺髻高 70.94 米，脚下石台向下延伸 1.65 米。两脚各有五趾，每只脚朝内的大脚趾甲约宽 2.21 米、长 1.92 米。Blender 使用米制、正面朝 −Y，导出至 Godot 后正面朝 +Z。游戏以原尺寸把雕像安放在外海小岛对岸，朝向岛顶步道。重导出后运行 `python3 scripts/build-coast.py` 可同步游戏 GLB 和房间碰撞数据。[可编辑源件](../art/landmarks/leshan_buddha/leshan_buddha.blend) · [游戏 GLB](../coop/coast/leshan_buddha.glb) · [海岸实景](../evidence/leshan-coast/island.png)

Godot 4.7.2 识别 `HalluxNail_L-col` 和 `HalluxNail_R-col`，为两块可见甲面各建了三角网碰撞。独立场景使用正式营地角色和游戏的 0.29 米碰撞半径，每次让四人落到同一枚甲面。两脚均通过。每只脚另取 132 个脚印采样点，命中同一枚甲面，最近的两人之间有约 0.20 米余量。游戏版雕像有 194,693 个三角面，躯体与足部各用一套 2K 底色和法线。[四人脚底近景](../evidence/leshan-buddha-scale/four-on-one-toenail.png) · [尺度对照](../evidence/leshan-buddha-scale/scale-review.jpg) · [碰撞实测数据](../evidence/leshan-buddha-scale/grounding.json)

两张头部侧照用于确定耳轮、耳甲腔、鼻翼及半垂眼睑的立体形状。眼睑和眼球与眼眶共用边界顶点。鼻梁沿截面过渡到鼻头和两侧鼻翼，耳甲腔与耳屏雕在同一个耳壳里。整个头部沿用已有砂岩、风化纹理和眉部色板。网页近岸地标与 Mac 版都读取同一份 GLB。 [同光照灰模对照](../evidence/leshan-face/face-comparison.webp) · [海岸近景](../evidence/leshan-face/coast-reverse.webp) · [岛上实景](../evidence/leshan-face/offshore-island.webp) · [网格检查](../evidence/leshan-face/geometry.json)

从外海小岛仰视时，原先的两道眼缝很难辨出目光。现在上下眼睑中央的间距从约 0.49 米增至 0.80 米，上睑遮住虹膜上缘，瞳孔凹入石面。眼窝的局部遮蔽烘入原有砂岩材质。网页与 Mac 发行包使用同一版面部网格。 [晴天与阴雨同机位对照](../evidence/leshan-eyes/eyes-before-after.webp) · [浏览器岛上实景](../evidence/leshan-eyes/offshore-island.webp) · [几何与实测](../evidence/leshan-eyes/checks.json)

从项目根目录执行下列命令可重新制作两份模型。只重导出手工调整过的源件时，可使用第二条命令。第一条命令末尾加 `-- --sculpt-only` 可单独保存 Blender 雕刻。

```sh
./scripts/start-blender.sh --background --factory-startup --python-exit-code 1 --python art/landmarks/leshan_buddha/build.py
./scripts/start-blender.sh --background art/landmarks/leshan_buddha/leshan_buddha.blend --python-exit-code 1 --python art/landmarks/leshan_buddha/package_glb.py
```

砂岩细纹取自营地已有的 Poly Haven 岩面材质。雕刻参考了用户提供的正面照片、Christels 的头部近照和 Jan Kranendonk 的全身及脚边参照。[Rock Face 03](https://polyhaven.com/a/rock_face_03) · [头部近照](https://commons.wikimedia.org/wiki/File:The_head_of_the_Leshan_Giant_Buddha.jpg) · [坐姿](https://commons.wikimedia.org/wiki/File:Leshan_giant_Buddha.jpg) · [脚边尺度](https://commons.wikimedia.org/wiki/File:Tourists_at_the_giant_Buddha_of_Leshan.jpg)

## 营地开局武器

游戏构建直接使用 `coop/weapons/` 中的模型与贴图。要重导出模型和背包图标，从下方素材页下载三件模型的 4K Blender 版本，分别解包到 `art/weapons/source/<素材名>_4k.blend/`，保留同名的 `.blend` 文件和 `textures/` 子目录，然后在项目根目录运行 `./scripts/start-blender.sh --background --python-exit-code 1 --python scripts/build-camp-weapons.py`。

日本刀、带瞄准镜的栓动步枪和手枪的可见组合分别有 6,670、19,365、16,650 个三角面。游戏保留完整网格及 4K 底色和法线，粗糙度和金属度打包为 2K，镜片透明底色为 1K。Godot 导入时生成 mipmaps，并使用 Basis Universal 压缩。持握点、瞄具定位点和地面接触在游戏坐标下校对。

三件模型由 Poly Haven 以 CC0 1.0 发布。日本刀由 Tal Swicegood 制作，两把枪由 Mateusz Sadek 制作。 [日本刀](https://polyhaven.com/a/antique_katana_01) · [步枪](https://polyhaven.com/a/bolt_action_rifle_7_62) · [手枪](https://polyhaven.com/a/service_pistol) · [许可](https://polyhaven.com/license)
