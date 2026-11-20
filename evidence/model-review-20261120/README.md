# 游戏模型近景审阅

本批在 Apple M1 的 Godot 4.7.2 Compatibility 中打开源码工作区实际导入的 83 个 GLB。每件以相对的两侧机位拍了 640 × 480 截图，固定灯光并按模型的米制包围盒取景。独立模型页用导入材质，角色选一帧站姿或待机。复查还经 `Terrain._parse_chunk` 加载了 7 个线上实际流送分块，使用运行时地面、植被和阴影。截图索引含每件源 GLB 的 SHA256、尺寸、姿态、原图路径和分组页。 [截图索引](capture-index.json) · [资源和纹理依赖](inventory.json)

| 审阅范围 | 图页 |
| --- | --- |
| 角色、装备、飞船与动物 | [装备及飞船](player-gear-and-airship.jpg) · [角色与动物](characters-and-wildlife.jpg) |
| 建筑、营地、储物和采集 | [木屋和家具](cabin-and-furniture.jpg) · [营地杂物与容器](camp-supplies.jpg) · [采集和食物](food-and-harvests.jpg) |
| 溪湖、树木和流送世界 | [树木各生长阶段](trees.jpg) · [滨水及林下植物](waterfront-and-understory.jpg) · [七区实际渲染](streamed-zones.jpg) |
| 矿山及手持道具 | [矿山与矿物](mines.jpg) · [手持道具](held-equipment.jpg) |

## 实际画面复验顺序

- 营火的原导入有清楚的黄色硬边与平直三角火舌，实际燃料点燃也使用这些面。以真实燃料计时和同机位火光复验。 [营火原导入](models/campfire-1.jpg)
- 两座矿洞的旧油灯是实色自发光灯罩，采矿口近壁偏橘。沿同一灯位检查透明灯罩、提环接触和深处通行照度。铁矿脉已完成 UV 校正，拾取版本的铁矿和煤块仍可见硬面与明显色差。 [铁矿拾取模型](models/iron_ore-1.jpg) · [煤矿拾取模型](models/coal-1.jpg)
- 夹克肩袖仍有颜色突变，优先复查实际穿戴和举臂的网格变形。高级 NPC 在剪影、腿部外观与服装上相近，继续用实际行走和持物状态核对可辨度。 [夹克背面与肩袖](models/camp_jacket-1.jpg) · [高级同伴](models/female_elite-2.jpg)
- 水壶、卷帆布、药草束和烤鳄鱼肉的近景比旁边的扫描苹果、箱桶更平整。复验放桌、捡取与手持机位，再补陶釉、布面纤维或更自然的表面细节。 [水壶](models/camp_water_jug-1.jpg) · [帆布](models/material_tarp-1.jpg) · [药草束](models/herb_bundle-1.jpg) · [烤鳄鱼肉](models/crocodile_meat_grilled-1.jpg)
- 海岸地形和草网格在独立图页为白色，因为正式客户端会给它们设置地形和草着色器。着色和实例接续以雨海和七分块场景实拍对照。林地的云杉近景仍能看到长而平整的冠层边缘，地图边缘机位可见背景过空，列入下一轮地表和植被近远接续检查。 [海岸实拍](../world-weather-web-20261120/coast-water-rain.png) · [云杉](models/spruce_mature-2.jpg) · [后林地边界](zones/backcountry.jpg)

本批覆盖文件导入、常用朝向和一个原生运行机位。穿戴、摆放、动作逐帧、碰撞、远近级别及网页帧时在各自的实机复验中记录。 [长期记录](../../docs/world-upgrade.md)

## 复跑

```sh
review_dir=$(mktemp -d)
python3 scripts/audit-coop-3d-assets.py --zones dist/coop-weather-preview/zones > "$review_dir/inventory.json"
/Users/sky/Downloads/Godot.app/Contents/MacOS/Godot --path coop --rendering-method gl_compatibility \
  --script "$PWD/scripts/capture-coop-model-review.gd" -- "$review_dir/inventory.json" \
  "$PWD/dist/coop-weather-preview/zones" "$review_dir/images"
python3 scripts/collect-coop-model-review.py "$review_dir/inventory.json" "$review_dir/images" "$review_dir/sheets"
```
