# 营地夹克的肩袖与层叠贴合

夹克的原始模型有 464,843 个三角面，Blender 编辑源有 119,840 个，旧运行件有 37,945 个。深灰肩片、橄榄绿面料、拉链和胸袋来自原始参考图。统一贴体与光照后，旧运行件肩肘的长三角和硬折面明显增多。共享顶点的着色法线连续，肩部 UV 接缝的亮度差 P95 为 0.042。内衬和裤腰的大片颜色区域由实际穿插造成。

[原始图](../../art/clothing/source/Character_Clothes/Jacket.png) · [原件、编辑源、旧运行件和新版素模对照](source-to-runtime.jpg) · [Blender 姿势近景](pose-comparison.jpg)

## 已接入的改动

夹克导出在减面时优先保住肩部、肘部、拉链、领边与袖口。新版有 51,946 个三角面、一个材质和原来的五骨。1024 像素底色与 512 像素粗糙度/金属度贴图逐像素一致。展开肘部的绑定过渡能减少跪起时的尖折。使用相同候选几何比较时，半跪起身中压缩至休止长度 35% 以下的肘边由 92 条降到 4 条。旧运行件的这个数量为 16 条。两个版本站立、举臂、半跪和倒地的投影轮廓重合率为 98.63%–99.24%。

| 几何指标 | 原始 GLB | Blender 编辑源 | 旧运行件 | 新运行件 |
| --- | ---: | ---: | ---: | ---: |
| 肩部边长 P95 | 0.71 cm | 2.17 cm | 6.25 cm | 2.38 cm |
| 肘部边长 P95 | 0.79 cm | 2.26 cm | 5.98 cm | 2.36 cm |
| 肩部三角面与着色法线夹角 P95 | 15.1° | 30.3° | 71.4° | 36.3° |

夹克内衬收窄并压入后半区，领口仍有深色内层。裤腰仅在同时穿着夹克、裤子时收进外套，变体由所有角色共享。实际 Godot 导入件修改上腰的 1,269 个顶点，保持裤腿坐标、蒙皮、索引、原材质、UV 和 4 档 LOD。脱下夹克时切回原裤，地面物品也使用原裤。角色页脱下夹克后的图片逐像素一致。

## 明暗、动作和穿戴复验

在 Apple M1 的 Godot 4.7.2 Compatibility 中记录新旧各 12 张图。采用相同导入设置、灯光和镜头。队友举臂使用游戏原有的持物动作，半跪和倒地从实际恢复动画取样。亮光和暗光都能看到背部连续布纹和遮住裤腰的衣摆。固定截面探测中，站姿背部明显外露内衬的点数由 927 降至 6，站姿前后区域的裤腰外露点由 355／522 降到 17／1。六个姿势均未测到腰部中线的新空隙。采样的游泳姿势肩部边长拉伸比 P95 仍为 1.45，旧运行件为 1.37。袖口和下摆在极近机位还能看见原件的细小褶皱。

[明亮和暗处的正背面](final-seams.jpg) · [全身、举臂、半跪和倒地](final-poses.jpg) · [角色页、脱下、落地和远观](final-equipment.jpg)

[旧几何](baseline-metrics.json) · [肩肘加密且沿用旧权重](geometry-only-metrics.json) · [新版几何和权重](candidate-metrics.json) · [层叠截面测量](layer-clip-variants.json) · [腰部遮盖测量](waist-coverage.json)

## 源件和复跑

[完整可编辑源](../../art/camp_jacket.blend)作为唯一持久的 Blender 源件。[正式生成脚本](../../scripts/build-camp-clothing.py)从该源件完成保护性减面、现有贴体、绑定与材质导出。下方命令生成可编辑的拟合场景和 GLB，适合在独立文件夹复查。生成步骤全自动，由两次 Blender MCP 后台导出复核指纹。

```sh
jacket_review=$(mktemp -d)
./scripts/start-blender.sh --background --python-exit-code 1 \
  --python evidence/camp-jacket-fit-20261120/build-candidate.py -- "$jacket_review"
Godot --headless --path coop --script ../evidence/camp-jacket-fit-20261120/check-layers.gd
```

`check-layers.gd` 校验安装后的真实网格和穿脱行为。实际工作区通过全部 13 项检查，单次腰部网格生成用时平均约 1.42 毫秒。原有 21 项玩家动作、营地衣物反馈和生存存档回归全部通过。反馈测试退出时报告了 6 个尚未清理的 ObjectDB 实例。

[工作区层叠验证](production-layer-checks.json) · [工作区九姿态](production-poses.json) · [玩家动作回归](production-locomotion.json) · [衣物和生存测试](production-regressions.txt) · [旧运行截图索引](godot-final-before.json) · [新运行截图索引](godot-final-candidate.json) · [源码和运行件指纹](sources.sha256)
