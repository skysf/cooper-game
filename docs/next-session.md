# 新窗口续接 · 2026-11-22

在项目根目录先读 [AGENTS.md](../AGENTS.md)。当前主线是 Godot 4.7.2 / GDScript，优先桌面浏览器，也有 Mac 发行版。

## 最新试玩

按 **M** 选择「野猪林地」，可以在根影林径西侧观察野猪。听到踏蹄低吼后侧移躲开冲撞。取材后可在营火烤肉，或在营地木桌制作披肩、猎犬哨和铺盖卷。 [本机试玩](http://127.0.0.1:5684/coop/?room=pine) · [配方与操作](coop.md#林地野猪) · [双人游戏录像](../evidence/woodland-boar/forest-encounter.webm)

按 **M** 可直达「湖岸芦苇荡」「藤蔓谷口」「赤层岩坡」。湖岸成熟的白穗按 **E** 采成芦苇束，可添入营火，也可在营地木桌旁按 **K** 制作编条。网页版与 Mac 版使用这一组场景。 [本机试玩](http://127.0.0.1:5684/coop/?room=pine) · [场景与素材](world-upgrade.md#湖岸芦苇荡藤蔓谷口与赤层岩坡)

5684 的西岸新增乐山大佛。在 **M** 键图册点击「外海小岛」会面向大佛，点击「乐山大佛」会到佛脚前的石滩。两种试玩包沿用同一房间和存档。[进入普通房间](http://127.0.0.1:5684/coop/?room=pine) · [海岸与实景](coast.md#外海小岛对岸的乐山大佛)

常用的 **5684 / pine** 现已更新湖区住船和绵羊，继续使用 `.local-rooms/human-models` 的原存档。在 **M** 图册选择鹿鸣湖，栈台 **E** 上船、**F** 开船。可在船上走动、按住 **Control** 蹲进船篷、在床边按 **E** 睡下回血。营地可建绳床供玩家、同伴和俘虏轮用，每床一次一人。靠近湖水按 **F** 取水，栈台或船上用 **R**。湖岸草地看向绵羊按 **E** 剪毛。 [进入普通房间](http://127.0.0.1:5684/coop/?room=pine) · [湖区住船与绵羊](coop.md#湖区住船与绵羊)


2026-11-21 的东部山地版已接入 5684 普通营地，沿用此前人形版的房间存档。按 **M** 可选根影林径、箭袋树花谷、层岩台地及两座矿口。也可以从木屋东边沿路牌出发。低头看腿脚、左键徒手连击、**V** 肩后视角均可继续使用。 [普通营地](http://127.0.0.1:5684/coop/?room=pine) · [徒手来袭者](http://127.0.0.1:5684/coop/?room=trail-encounter) · [东部山地与洞居营地](world-upgrade.md#东部山地与洞居营地)

```sh
COOP_SITE_DIR=dist/coop COOP_PORT=5684 COOP_ROOM_PORT=5685 \
  COOP_SAVE_DIR=.local-rooms/human-models npm run coop
```

Mac 版的九个地景分块随本次本机发行包提供。连接同一房间可运行下列命令。

```sh
open -n dist/coop-native/CooperCamp.app --args -- --room=pine --url=ws://127.0.0.1:5684/room --zone-base=http://127.0.0.1:5684/coop/zones/
```

上一版 Web 合并包是 [5584 试玩](http://127.0.0.1:5584/coop/?room=pine)。Tab 打开新版背包、角色和图鉴。目击动物或获得鳄鱼肉会更新个人图鉴。启动进度在游戏就绪时完成。Esc 关闭当前界面，Shift+Esc 返回营地菜单。探索中鼠标解除锁定时，可点击画面继续。枪械击中头部会一击击杀，来袭者会分路撤出营地。此包的分块通过链接读取 `dist/coop-streamed-crown-20261120/zones`。 [图鉴与烹饪](camp-storage.md#野外图鉴) · [来袭者](wild-people.md)

端口空闲时，从项目根目录重新启动。`pine` 沿用这个版本自己的本机房间与浏览器身份。

```sh
COOP_SITE_DIR=dist/coop-animal-combat COOP_PORT=5584 COOP_ROOM_PORT=5585 \
  COOP_SAVE_DIR=.local-rooms/detail-preview npm run coop
```

图册版包括从鹿鸣湖无缝进入海湾、从礁线游到外海小岛、实拍岩壁材质、营地开局的三件武器和 **M** 键野外图册。图册的六处地标可直接传送，同房间可看见队友，个人标记会随身份及房间保存。滚轮和 **+ / −** 缩放，放大、缩小各有原创电子音。 [图册操作](field-atlas.md) · [海岸路线](coast.md) · [拾取与瞄准](wild-people.md#营地开局武器)

优化时可把 `dist/coop-animal-combat` 用作当前对照包。用 `npm run coop:build:web` 将候选版输出到 `dist/coop`，再用下列命令比较两版。Mac 版可用 `npm run coop:build` 从源码重新导出。

```sh
npm run coop:render:benchmark -- dist/coop-animal-combat dist/coop
```

## 下一轮画面与帧时

- **野人步态** 先用实际可见的靴底量脚滑。两套高级款修叠层的隔离方案已可用 Blender 重建。先复验走、跑、跛行、坐卧和持物，再进入四人房间测试。 [靴底与步态对照](../evidence/wild-people-elite-fit-20261120/README.md)
- **首开与长帧** 5584 已用前台真键鼠走完两矿、下潜登岛和飞船越礁。七段超过长帧门槛，铁矿出洞最长 1.28 秒。开局的三件装备和五类容器贴图合占试玩包约 64%，先用单张全尺寸贴图验证压缩及首开时间。 [完整验收与包内盘点](../evidence/world-detail-web-20261120/README.md)
- **林地与建造** 溪上游单株已接入树冠近远交接。沿林缘和矿洞外围扩展时对比真实落点、风动与长路线。多层地板的桌面物品已能保存落点，下一轮检验斜屋面和不同玩家同时移动物件。 [长期工作记录](world-upgrade.md#接下来做什么)

## 本机清理与存档

4173 的早期 A/B 服务和 4184 / 4185 的旧营地服务已关闭。旧导出包已清理，历史测量保存在 `evidence/`。当前房间使用 `.local-rooms/detail-preview/pine.json`。

旧房间、测试存档和历次备份归档在 `.local-rooms/backups/retired-servers-20261121.qpbwbdaj/old-saves-and-service-logs.tar.gz`。归档保留工作区相对路径，可先解到单独目录找回指定房间。

[构建与运行手册](play.md) · [实玩测试与帧时基准](render-benchmark.md) · [主要验收记录](../evidence/)
