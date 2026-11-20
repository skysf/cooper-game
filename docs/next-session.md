# 新窗口续接 · 2026-11-20

在项目根目录先读 [AGENTS.md](../AGENTS.md)。当前主线是 Godot 4.7.2 / GDScript，优先桌面浏览器，也有 Mac 发行版。

## 最新试玩

当前交接包包括从鹿鸣湖无缝进入海湾、从礁线游到外海小岛、实拍岩壁材质、营地开局的三件武器和 **M** 键野外图册。图册的六处地标可直接传送，同房间可看见队友，个人标记会随身份及房间保存。滚轮和 **+ / −** 缩放，放大、缩小各有原创电子音。 [图册操作](field-atlas.md) · [海岸路线](coast.md) · [拾取与瞄准](wild-people.md#营地开局武器)

本机 Web 包是 `dist/coop-atlas`，已签名的 Mac 包是 `dist/coop-atlas-native/CooperCamp.app`。两端 PCK 的 SHA256 均为 `e3862feddc0cff581b61ffc3e25f072420066e34fac07f2610986a8feab1cf94`。端口空闲时，从项目根目录重开同一试玩存档。

```sh
COOP_SITE_DIR=dist/coop-atlas COOP_PORT=4794 COOP_ROOM_PORT=4795 \
  COOP_SAVE_DIR=.local-rooms/atlas-preview npm run coop
```

网页进入 [野外图册试玩](http://localhost:4794/coop/?room=pine)。房间名 `pine` 和浏览器身份沿用原存档。需要从源码重建时用 `npm run coop:build`，发行物可先在隔离目录核对再替换。

## 下一轮画面与帧时

- **海湾远景** 减弱雾层后能从外海辨认崖壁与岬角。Apple M1 的前台 Chrome 路线平均 59.7 FPS，最长帧间隔 149.9 ms，九段中三段触发长帧门槛。已有固定机位前后对照和逐帧采样，可沿原路线对比。 [海岸远景专题](coast.md#远景与天气) · [逐帧报告](../evidence/coast-visibility-20261120/foreground/report.json)
- **野外图册** 双前台 Chrome 通过六处传送、队友同步及个人标记存档。连续缩放与拖动的 4.1 秒采样平均 60 FPS，最长 18.8 ms。本机与普通 HTTP 均采到实际缩放声音。 [图册验证](field-atlas.md#实现与复验)
- **林地和角色** 背包同类物品占一格，溪水和任务物资走玩家背包。行走、起落、水中动作由实际移动状态驱动。多人和 NPC 高负载场景仍有需定位的长帧。 [背包和玩家动作](coop.md) · [NPC 专题](wild-people.md)

## 本机旧版与存档

如需复验旧包，从下表取对应的 `COOP_SITE_DIR`、`COOP_PORT`、`COOP_ROOM_PORT`、`COOP_SAVE_DIR`，用同一启动命令。4184 是原营地服务，先核对端口及存档路径再操作。

| 版本 | 网页 / 房间端口 | Web 发行目录 | 本机存档 |
| --- | --- | --- | --- |
| 武器 | 4394 / 4395 | `dist/coop-weapons` | `.local-rooms/weapon-preview` |
| 海岸贴图 | 4494 / 4495 | `dist/coop-coast` | `.local-rooms/coast-preview` |
| 海岸远景 | 4694 / 4695 | `.cache/coast/distance-view/release.Kbvepr/web` | `.cache/coast/distance-view/release.Kbvepr/test-rooms` |
| 背包与动作 | 4284 / 4285 | `dist/coop-resource-fix` | `.local-rooms/wild-people` |

本机窗口收尾备份位于 `.local-rooms/backups/window-close-20261120/`。更换运行包前核对服务命令、端口、房间和保存目录。涉及房间服务时先留备份，再结束 Web 包装进程并等待 Godot 保存退出。先确认两端包已完整导出，再交换目录。

[构建与运行手册](play.md) · [实玩测试与帧时基准](render-benchmark.md) · [主要验收记录](../evidence/)
