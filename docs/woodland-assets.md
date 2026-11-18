# 林地素材与许可

五套材质均由 Poly Haven 以 CC0 1.0 提供，允许修改、再分发与商用。下载日期为 2026-11-18。 [Poly Haven 许可](https://polyhaven.com/license) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

| 游戏表面 | 原作者 | 原始材质 |
| --- | --- | --- |
| 泥路 | eye-candy.xyz | [Mud Forest](https://polyhaven.com/a/mud_forest) |
| 林地落叶层 | eye-candy.xyz | [Forest Floor](https://polyhaven.com/a/forest_floor) |
| 树干、枝条与根部 | Rob Tuytel | [Bark Brown 01](https://polyhaven.com/a/bark_brown_01) |
| 潮湿岩石 | Rob Tuytel | [Mossy Rock](https://polyhaven.com/a/mossy_rock) |
| 庇护所木板、支柱与长凳 | Amal Kumar | [Wood Planks](https://polyhaven.com/a/wood_planks) |

每套使用 1024 × 1024 的 Diffuse、OpenGL 法线、ARM 三张 JPEG。ARM 的红、绿、蓝通道分别保存环境遮蔽、粗糙度和金属度。15 张原图逐一核对了官方 API 提供的 MD5，再压缩为项目内 JPEG。原图 URL、MD5 及交付文件的 SHA-256 见 [texture-sources.json](../shared/texture-sources.json)。

树干、树枝、岩石、泥路与庇护所的几何由本项目脚本生成。针叶与蕨叶透明图由本项目绘制。上述项目原创的几何与图像按 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) 提供。所有使用中的纹理都内嵌在同一个 GLB，试玩时只需 localhost。

## 再生成

从项目目录执行 `node scripts/build-scene.mjs`。脚本读取已有 `shared/textures/` 和 `shared/layout.json`，写出 `shared/woodland.glb`、`shared/scene.json` 并将二者复制给两个引擎。GLB 以米为单位并以 Y 为竖直轴，试走向负 Z。清单列出主要物体实位与圆柱碰撞半径。草簇、枝叶等装饰分布由清单种子确定。单独重画植物贴图可执行 `python3 scripts/foliage.py`（需要 Pillow），然后重新生成 GLB。

路面几何固定在 y = 0。树根接触阴影与林冠投影采用顶点色。泥路使用一张覆盖 8 × 8 米的 2048 像素平铺 PBR 图集。路肩按泥土、枯叶颗粒和噪声同时融合底色、法线与 ARM，沿两侧无缝过渡为调暗的林地材质。车辙积水降低局部粗糙度，压平法线，保留水下泥土并混入微弱的近似天光。运行 `python3 scripts/ground.py`（需要 Pillow、NumPy）可从已交付的 1K 源图重建这些派生纹理。针叶与蕨叶采用双面 alpha-cutout 材质。

## 合作版静态林木

合作版的 180 株静态针叶树使用 [coop-fir-wood.mjs](../scripts/coop-fir-wood.mjs) 生成木质网格。每株由自身坐标派生固定随机种子，分别决定三至六条表根的方位、伸展和弯曲，以及低处长枝、岔枝、断梢和短节疤的组合。根颈和表根是连续网格，末端铺向地面，枝条有逐段收尖的曲线和封闭或不规则的断面。沿用已有的 Bark Brown 01 材质。

`npm run coop:build` 调用 `scripts/build-scene.mjs --coop`，从 `.cache/coop-world-source/` 的合作版源场景切分网页和 Mac 分块。静态树点、碰撞、针叶和其他场景网格与原版数据一致。成长树的 Blender 试点见 [Pine Tree 01](pine-tree.md)。

溪谷侧同一株树在有窗口的 M1 Chrome 中按两套固定机位复拍，视口与实际绘图缓冲区为 1280 × 720。 [树根改前](../evidence/forest-wood/before-roots.png) · [树根改后](../evidence/forest-wood/after-roots.png) · [树枝改前](../evidence/forest-wood/before-branches.png) · [树枝改后](../evidence/forest-wood/after-branches.png)

溪谷分块 gzip 增加 220,079 B。七个按需下载的分块合计增加 1,506,049 B。去除树梢的极近顶点之前，另在相同远一些的晴天机位采样约 8 秒，原版和新版均为 25.00 FPS，P95 帧间隔为 41.70 → 41.80 ms。 [原始帧耗时](../evidence/forest-wood/overview-frame-times.json)

## 可拾取的石块

圆石和扁石取自 Kless Gyzen 的 **Rock Moss Set 01** 第 3、2 块，保留原网格与扫描贴图坐标，并缩到 13.5 厘米和 11.5 厘米。磨刃版从扁石侧边切出斜刃，补成闭合网格，切面材质取自 Rob Tuytel 的 CC0 **Mossy Rock**。小石块使用内嵌的 512 像素贴图。圆石 5,000 个三角面，扁石 10,996 个。[Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01) · [Mossy Rock](https://polyhaven.com/a/mossy_rock)

鹿鸣湖岸的八块岩石使用 Rico Cilliers 的 **Boulder 01**。运行时复用同一份 LOD3 网格和 1024 像素贴图，每块独立定向缩放。水面反射会绘制这组岩石，雨天材质随岸线变深。实例的碰撞从 [湖岸布局](../coop/water_layout.json) 写入共享世界清单。[Boulder 01](https://polyhaven.com/a/boulder_01)

要重做岩石模型，可从上面的素材页下载原始 `.blend` 和 4K 贴图，将 `rock_moss_set_01_4k` 和 `boulder_01_4k` 两个目录放入 `art/rocks/`。`python3 scripts/build-camp-stones.py` 用它们重新生成 [coop/props](../coop/props/) 中的四个 GLB。运行需要 NumPy、Pillow、`zstd` 和 [本机 Blender 安装](blender-mcp.md)附带的 OpenEXR 库。脚本直接读取网格和图像，无需打开 Blender 窗口。
