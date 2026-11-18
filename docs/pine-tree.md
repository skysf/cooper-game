# Pine Tree 01 资产来源

源模型为 Poly Haven 的 **Pine Tree 01**，由 Rico Cilliers 建模、Rob Tuytel 摄影，按 CC0 1.0 发布。 [资产页面](https://polyhaven.com/a/pine_tree_01) · [Poly Haven 许可](https://polyhaven.com/license) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

官方 1K glTF 的 B 变体有 4,234,432 个三角面。项目提取 B 变体的树干和枝条网格，由 Godot 的网格简化器分别生成幼树和成树的木质部分。两个树冠的针叶贴片沿源网格的枝条分布。幼苗使用独立的树干和枝条轮廓。三个模型共用原始树皮、B 树干和针叶的降采样贴图，其中针叶图集合并了源颜色和透明度。 [官方 1K glTF](https://dl.polyhaven.org/file/ph-assets/Models/gltf/1k/pine_tree_01/pine_tree_01_1k.gltf) · [官方文件索引](https://api.polyhaven.com/files/pine_tree_01)

| 模型 | 宽 × 高 × 深（米） | 三角面 | GLB |
| --- | --- | ---: | ---: |
| `pine_sapling.glb` | 0.47 × 0.65 × 0.47 | 340 | 21,556 B |
| `pine_young.glb` | 1.72 × 2.40 × 1.87 | 2,533 | 144,092 B |
| `pine_mature.glb` | 3.22 × 7.00 × 3.36 | 4,158 | 227,168 B |

三个模型的底部在 Y=0。GLB 和共用贴图合计 635,237 B。模型、贴图和 Godot 导入资源均随项目分发。

从项目根目录运行 `python3 scripts/prepare-pines.py --fetch` 可重新生成资产。脚本需要 NumPy、Pillow 和 Godot 4.7.2，并仅下载模型索引、所需贴图和官方二进制的木质网格区段。可通过 `--godot` 指定 Godot 可执行文件。

## 林道成松试点

在 Blender 5.2.4 中打开 [pine_tree_01_trail.blend](../art/pine_tree_01_trail.blend)。场景默认显示 `LOD0`。在 Outliner 切换 `LOD0` 到 `LOD2` 集合即可逐档编辑。近景可以分别编辑树干与主根、分叉根与枝、针叶三个网格。分叉根与枝网格内有表根、分叉主枝、断枝节疤顶点组，贴图打包在源文件中。

根据原版松树校正主干走向，在树干下段重建不规则的锥度、根颈和五条连续主根，并增加三处分叉根与断枝节疤。近景使用 Poly Haven 实拍树皮颜色、法线和粗糙度贴图，原始位移采样到树干网格，根部用顶点色表现湿土和浅苔。针叶沿用原版的照片贴图，跨档保留枝层和梢尖。中景保留较低枝层的叉枝和弯曲针叶，远景保留中上段针叶簇与几条主枝。针叶材质使用双面 Alpha Scissor，阈值为 0.36。 [Poly Haven 原作及 CC0 许可](https://polyhaven.com/a/pine_tree_01)

在项目根目录执行以下命令可从已编辑的 Blender 文件重导游戏 GLB。

```sh
./scripts/start-blender.sh --background art/pine_tree_01_trail.blend \
  --python-exit-code 1 --python scripts/build-pine-pilot.py -- --export-only
```

若需从项目原版成树重新生成源文件与 GLB，可执行以下命令。

```sh
./scripts/start-blender.sh --background --factory-startup \
  --python-exit-code 1 --python scripts/build-pine-pilot.py
```

生成脚本使用 Blender 自带的 NumPy。首次生成时会校验并获取缺失的官方树皮贴图。图形版 Blender 也可在 Python Console 中用 `runpy.run_path` 执行生成脚本。运行 `npm run coop:build` 重新导入 [游戏 GLB](../coop/pines/pine_mature_refined.glb) 并更新试玩包。

Godot 给林道上的 `trail-mature` 在成树阶段使用这组距离模型。名义切换点为 8 m 和 18 m，两个边界都有 1 m 滞回，28 m 外沿用成长林地的裁剪范围。试点 GLB 关闭 Godot 自动 LOD。三个模型的原点在地面，资产高度均为 7 m。房间时钟继续控制树龄和实际高度，达到最终年龄时该树高 6.16 m。

| 资产网格 | GLB 原始三角面 | 针叶三角面 | 针叶贴片 |
| --- | ---: | ---: | ---: |
| 原版成树 | 4,158 | 2,012 | 503 |
| 近景 `LOD0` | 5,251 | 1,112 | 278 |
| 中景 `LOD1` | 1,393 | 482 | 190 |
| 远景 `LOD2` | 467 | 204 | 102 |

原版成树的 Godot 自动 LOD 使用屏幕误差。三个原版材质面分别有 3、1、1 个简化备选。林道这棵成长树原先在 28 m 处裁剪，周围静态林地的分块树片属于单独系统。新版 GLB 内嵌四张贴图，体积 875,644 B。

### M1 网页验收

首版试点完成了固定 3.5、13、23 m 晴雨 A/B 和 53° 方位补测。最初 23 m 机位有前景遮挡，第一轮雨天远景的 60 FPS 未在复测重现。第二机位的晴雨复测前后都为 25 FPS。用 W/S 沿 53° 方位进退，确认了两道距离边界的双向切换。 [首版逐帧数据](../evidence/pine-refinement/frame-times.json) · [雨天复测](../evidence/pine-refinement/far-rain-repeat.json) · [行走记录](../evidence/pine-refinement/walk-lod.json)

最终写实版沿 53° 方位重测，在 Apple M1、16 GB 上使用同一个有窗口的 Chrome 157.0.8103.79，WebGL 2 绘图缓冲区、CSS 画布和 Godot 视口均为 1280 × 720。每个晴雨机位采样约 8 秒，目标树固定为 6.16 m，原版和改造版的驻留分块和同屏成长树数一致。六对采样的帧率均约 25 FPS，P95 从 40.80–40.90 ms 变为 40.80–41.00 ms。以上为浏览器连续帧间隔。 [最终逐帧数据](../evidence/pine-refinement/realism/frame-times.json)

网页主包 gzip 从 3,609,529 B 增至 4,178,072 B，增加 568,543 B（15.75%）。近景增面做了连续根颈和树干，中远景减面，单株实测的帧耗时基本持平。保留林道单株试点，暂缓整片林地替换。 [2.2 m 树根改前](../evidence/pine-refinement/realism/before-roots-clear.png) · [2.2 m 树根改后](../evidence/pine-refinement/realism/after-roots-clear.png) · [改后低层树冠](../evidence/pine-refinement/realism/after-lower-crown-clear.png)

最终版重新步行跨过两道边界。画面中可见的树干和主要枝层保持连续，换档时局部针叶密度有变化。周边高树遮住了部分树冠上缘。 [换档前后截图](../evidence/pine-refinement/realism/walk-cutovers.jpg)

本机复测可用 `node scripts/pine-web-check.mjs prepare .cache/pine-qa-reference --clear-route` 生成测试页。用有窗口的 Chrome 打开命令输出的本机地址并下载结果，再执行 `node scripts/pine-web-check.mjs extract <下载的 JSON>`。房间回归测试通过，覆盖生长时钟持久化、碰撞、共享任务和重连。
