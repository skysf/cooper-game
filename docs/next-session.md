# 新窗口续接 · 2026-11-20

在项目根目录先读 [AGENTS.md](../AGENTS.md)。当前主线是 Godot 4.7.2 / GDScript，优先桌面浏览器，也有 Mac 发行版。

## 最新试玩

当前 Web 合并包是 [5584 试玩](http://127.0.0.1:5584/coop/?room=pine)。加入夹克贴合、陶壶与原矿拾取近景、鹿鸣溪上游的针叶树试点和多层家具支撑。矿洞、联机原地救援、原木建造、营火与风雨仍在同一个包中。此包的分块必须配随包链接的 `dist/coop-streamed-crown-20261120/zones`。 [长期进度与下一批问题](world-upgrade.md)

端口空闲时，从项目根目录重新启动。`pine` 沿用这个版本自己的本机房间与浏览器身份。

```sh
COOP_SITE_DIR=dist/coop-detail-preview COOP_PORT=5584 COOP_ROOM_PORT=5585 \
  COOP_SAVE_DIR=.local-rooms/detail-preview npm run coop
```

图册版包括从鹿鸣湖无缝进入海湾、从礁线游到外海小岛、实拍岩壁材质、营地开局的三件武器和 **M** 键野外图册。图册的六处地标可直接传送，同房间可看见队友，个人标记会随身份及房间保存。滚轮和 **+ / −** 缩放，放大、缩小各有原创电子音。 [图册操作](field-atlas.md) · [海岸路线](coast.md) · [拾取与瞄准](wild-people.md#营地开局武器)

图册版的 Web 包为 `dist/coop-atlas`，已签名的 Mac 包为 `dist/coop-atlas-native/CooperCamp.app`。两端 PCK 的 SHA256 均为 `e3862feddc0cff581b61ffc3e25f072420066e34fac07f2610986a8feab1cf94`。需要从源码重建时用 `npm run coop:build`，发行物可先在隔离目录核对再替换。 [图册版试玩](http://localhost:4794/coop/?room=pine)

## 下一轮画面与帧时

- **野人步态** 先用实际可见的靴底量脚滑。两套高级款修叠层的隔离方案已可用 Blender 重建。先复验走、跑、跛行、坐卧和持物，再进入四人房间测试。 [靴底与步态对照](../evidence/wild-people-elite-fit-20261120/README.md)
- **首开与长帧** 5584 已用前台真键鼠走完两矿、下潜登岛和飞船越礁。七段超过长帧门槛，铁矿出洞最长 1.28 秒。开局的三件装备和五类容器贴图合占试玩包约 64%，先用单张全尺寸贴图验证压缩及首开时间。 [完整验收与包内盘点](../evidence/world-detail-web-20261120/README.md)
- **林地与建造** 溪上游单株已接入树冠近远交接。沿林缘和矿洞外围扩展时对比真实落点、风动与长路线。多层地板的桌面物品已能保存落点，下一轮检验斜屋面和不同玩家同时移动物件。 [长期工作记录](world-upgrade.md#接下来做什么)

## 本机旧版与存档

如需复验旧包，从下表取对应的 `COOP_SITE_DIR`、`COOP_PORT`、`COOP_ROOM_PORT`、`COOP_SAVE_DIR`，用同一启动命令。4184 是原营地服务，先核对端口及存档路径再操作。

| 版本 | 网页 / 房间端口 | Web 发行目录 | 本机存档 |
| --- | --- | --- | --- |
| 溪岸木屋和燃烧细节 | 5484 / 5485 | `dist/coop-cabin-preview` | `.local-rooms/cabin-preview` |
| 风雨、岩壁和同伴脚点 | 5384 / 5385 | `dist/coop-weather-preview` | `.local-rooms/weather-preview` |
| 挡雨、植物与救援 | 5284 / 5285 | `dist/coop-recovery-preview` | `.local-rooms/recovery-preview` |
| 矿洞与建造 | 5184 / 5185 | `dist/coop-mining-preview` | `.local-rooms/mining-preview` |
| 原木建造 | 5084 / 5085 | `dist/coop-construction-preview` | `.local-rooms/construction-preview` |
| 穿戴与飞船 | 4984 / 4985 | `dist/coop-wearables-preview` | `.local-rooms/wearables-preview` |
| 野外图册 | 4794 / 4795 | `dist/coop-atlas` | `.local-rooms/atlas-preview` |
| 武器 | 4394 / 4395 | `dist/coop-weapons` | `.local-rooms/weapon-preview` |
| 海岸贴图 | 4494 / 4495 | `dist/coop-coast` | `.local-rooms/coast-preview` |
| 海岸远景 | 4694 / 4695 | `.cache/coast/distance-view/release.Kbvepr/web` | `.cache/coast/distance-view/release.Kbvepr/test-rooms` |
| 背包与动作 | 4284 / 4285 | `dist/coop-resource-fix` | `.local-rooms/wild-people` |

本机窗口收尾备份位于 `.local-rooms/backups/window-close-20261120/`。更换运行包前核对服务命令、端口、房间和保存目录。涉及房间服务时先留备份，再结束 Web 包装进程并等待 Godot 保存退出。先确认两端包已完整导出，再交换目录。

[构建与运行手册](play.md) · [实玩测试与帧时基准](render-benchmark.md) · [主要验收记录](../evidence/)
