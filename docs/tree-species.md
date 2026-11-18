# 混交林树种与模型

合作样片的松树来自 Poly Haven。新增的垂枝桦（游戏中称白桦）和云杉是项目原创的程序模型，三者有独立的树冠轮廓。白桦的树干带横向深色皮孔，枝端较细，下垂叶簇使用带锯齿的阔叶图。云杉围绕中央主干分层长枝，下层较宽，枝梢稍上翘，侧枝向下垂。[松树来源与制作](pine-tree.md)

| 树种 | 幼苗 · 0.65 米 | 幼树 · 2.4 米 | 成树 · 7 米 |
|---|---:|---:|---:|
| 白桦 birch | 756 三角形 | 1,932 三角形 | 3,100 三角形 |
| 云杉 spruce | 1,048 三角形 | 2,708 三角形 | 4,472 三角形 |

三阶段分别生成主枝数量、冠形和干径。每棵树使用树皮、双面透明裁切枝叶两种材质。GLB 内保存网格，三个年龄共用外置纹理。在 Godot 中替换某阶段的造型时，保留对应的资源路径、米制高度、Y 轴朝上和地面原点。生长和存档接口见[合作样片](coop.md)。

## 文件、来源和许可

| 内容 | 位置 | 来源与许可 |
|---|---|---|
| 白桦与云杉的六组网格 | `coop/trees/{birch,spruce}_{sapling,young,mature}.glb` | 项目原创，[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 白桦树皮、枝叶 | `coop/trees/birch_bark.jpg`、`coop/trees/birch_leaves.png` | 项目原创程序纹理，[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 云杉针叶 | `coop/textures/needles.png` | 项目原创针叶图，经 `scripts/coop-zones.py` 缩小复用，[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| 云杉树皮底色 | `coop/textures/bark_diff.jpg` | Rob Tuytel 的 [Bark Brown 01](https://polyhaven.com/a/bark_brown_01)，[CC0 1.0](https://polyhaven.com/license) |

## 备选松树素材

LOLIPOP 的树包含 15 款不同大小的松树造型和多级 LOD，采用 CC BY 4.0，可按署名条款商用。核查时匿名下载接口要求登录。本版沿用 Poly Haven 松树；包中的网格和贴图未纳入项目。[Sketchfab 原树包](https://sketchfab.com/3d-models/pine-trees-pack-lowpoly-game-ready-lods-e1e9c07b8e2e445c943fec660beefba2) · [许可条款](https://creativecommons.org/licenses/by/4.0/)

## 再生成与导入

在项目根目录执行以下命令。已有纹理随仓库交付，仅调整几何时只需运行第二行。Python 绘图脚本依赖 Pillow 和 NumPy。两条命令使用固定种子，无需打开 Blender 或 Godot 编辑器。

```sh
python3 scripts/birch-textures.py
node scripts/build-tree-species.mjs
```

已在独立的 Godot 4.7.2 Compatibility 项目中导入并实例化全部六个 GLB，逐个检查两组网格的材质能解析到预期的外置纹理、合并包围盒底部位于地面、顶端达到表中高度（容差 0.1 毫米）。三角形数来自导入前 GLB 的索引数；同一个文件可被多个树点复用。
