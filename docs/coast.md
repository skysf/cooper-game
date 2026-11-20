# 鹿鸣湖到外海

海岸试玩已接在原营地世界的西侧。从木屋走到鹿鸣湖北岸，认准「海湾」木牌，沿山径登上崖顶。到崖边后沿「沙滩」木牌走折返缓坡。两座岬角之间是浅湾，浅湾外的白浪是礁线，越过后可在岛的东侧沙嘴上岸。岛上小径通到两道山脊之间的高点。外海水面可以继续向西探索，当前可游玩的西界比原地图向外扩了约 275 米。[本机海岸试玩](http://localhost:4494/coop/?room=pine)

用 **WASD** 行走和游泳，深水中 **C** 下潜、**空格** 上浮。红船可用 **E** 上下机，空格上升、C 下降。可开船越过岬角、在外海水面停泊下水。队友可以留在木屋，同一房间共享时间、天气和角色位置。

## 地形和材质

构图参考用户给的俯拍照，以及冲绳果报崖的岩壁和植被、德之岛的岸边礁盘。两座岬角围成浅湾，浅色沙底逐渐过渡为礁盘，白浪随礁脊走向打断深蓝外海。[果报崖](https://www.okinawaclip.com/post/uruma-recommend/) · [德之岛海岸](https://route-official.com/amamitreil-tokunosshimaarea/)

陡崖使用 Rock Face 03 的 2K 色彩和法线，较缓的岩面和岸边圆石使用 Seaside Rock 的 2K 色彩和法线。崖壁的裂缝来自实拍贴图，原先按高度循环加深的暗纹已移除。投影在岩面上缓慢偏移，减少大面积重复。礁盘底色使用原来的 Rock Face，沙地使用 Aerial Beach 01。这些纹理均为 Poly Haven 的 CC0 素材。[Rock Face 03](https://polyhaven.com/a/rock_face_03) · [Seaside Rock](https://polyhaven.com/a/seaside_rock) · [Rock Face](https://polyhaven.com/a/rock_face) · [Aerial Beach 01](https://polyhaven.com/a/aerial_beach_01) · [固定机位对照](../evidence/coast-cliff-20261120/cliff-before-after.jpg)

山径、沙滩、礁床和岛由 Python 生成，Godot 用同一份高度格点渲染并结算行走、游泳和停船。客户端与房间服务器沿地表三角形的同一条对角线插值。海岸资产随游戏包首开驻留，远树用树冠卡片，近树保留几何，岩石与低植被按位置成批绘制。玩家能从旧林地走过连接处，越过礁线后也没有单独的场景加载或换房。原林地仍按距离预取细节分块。[地形设计](../coop/coast_layout.json) · [共享高度与碰撞](../coop/coast_layout.gd) · [岸地与海面](../coop/coast_scene.gd)

## 远景与天气

海岸晴天的深度雾从 58 米开始渐入，远处最高遮盖度为 34%。雨势加大时从较近距离进入蓝灰雾，仍可辨认远处的岩壁、坡道和树线。海水主要在海平线附近渐隐，水下独立按深度调整雾色和可见距离。海岸镜头的绘制距离为 290 米，地形与植被继续按分块剔除。[Godot 深度雾参数](https://docs.godotengine.org/en/4.6/classes/class_environment.html#class-environment-property-fog-density) · [晴雨同机位前后对照](../evidence/coast-visibility-20261120/distant-cliffs-before-after.jpg)

远景效果可在 4694 独立房间试玩。Mac M1 的前台 Chrome 完整跑过步行、上下山、游泳、登岛和飞行，共采集 136.8 秒，平均 59.7 FPS。飞机飞过岛后回看海岸的样本平均 59.6 FPS，最长帧间隔 66.6 毫秒。整条路线最大仍为 149.9 毫秒，九段中三段触发长帧门槛。试过在完整游戏视口预热，后两次测到更高的峰值，当前测试包采用原先的小视口预热。固定海上机位全浸没的两张画面对照逐像素一致。[远景测试房](http://localhost:4694/coop/?room=pine) · [逐帧测试](../evidence/coast-visibility-20261120/foreground/report.json)

## 构建和复验

`npm run coop:build:web` 依次生成海岸、林地细节和 Web 发行包。Mac 可用 `npm run coop:build`。按设计调整海岸后，可以单独运行 `python3 scripts/build-coast.py` 预览生成数据。如需重开本机独立试玩，确认 4494 和 4495 空闲后运行下列命令。

```sh
COOP_SITE_DIR=dist/coop-coast COOP_PORT=4494 COOP_ROOM_PORT=4495 \
  COOP_SAVE_DIR=.local-rooms/coast-preview npm run coop
```

前台复验在空白页确认显示刷新率，再在 1280 × 720 的 Chrome 画布内实际点击进入并获取鼠标锁定，按普通键鼠流程从木屋走、游、潜水、登岛和驾驶飞船。登岛后和飞过小岛后会转动视角扫过远处岬角。脚本使用独立房间组，并记录实际提交帧、浏览器焦点、分块请求和位置。[前台试玩脚本](../scripts/coop-coast-playtest.mjs)

```sh
node scripts/coop-coast-playtest.mjs .cache/coast/foreground
```

用 `COOP_COAST_MINES=1` 可在岬顶途中绕行煤、铁矿洞并按 **F** 各开采一次。锁屏调试可同时设 `COOP_COAST_HEADLESS=1`。`COOP_COAST_GL_TRACE=1` 记录 GL 程序和长任务，可将停顿对应到路线坐标。无窗口和开启追踪的时间样本用于排查，正式硬件测试沿用前台运行。 [矿洞与海岸路线诊断](../evidence/world-detail-web-20261120/README.md)

2026-11-20 在 Mac 内建屏、Apple M1、Chrome 157 和 Metal 上实测了海岸初版。七段累计约 115 秒、6,890 个帧间隔，整体 59.7 FPS。各段 P95 为 18.2–18.6 毫秒。6 个间隔超过 50 毫秒，最大 82.8 毫秒，没有连续两个慢帧。按 30 FPS、P95 34 毫秒及长帧门槛复核，七段均通过。首次诊断发现转向未出现过的材质会触发浏览器编译，发行包在开放输入前预绘营地到海岸的视角、角色和雨丝材质。[海岸初版前台逐帧报告](../evidence/coast-20261120/foreground-final/report.json)

| 实际游玩路段 | FPS | P95 帧间隔 | 最长帧间隔 |
| --- | ---: | ---: | ---: |
| 木屋到鹿鸣湖北岸 | 59.4 | 18.3 ms | 67.5 ms |
| 湖岸接缝到崖顶 | 60.0 | 18.2 ms | 18.7 ms |
| 崖顶转向并走下沙滩 | 59.6 | 18.6 ms | 82.8 ms |
| 游越礁线并潜水 | 60.0 | 18.6 ms | 18.8 ms |
| 上浮、登岛并走到岛顶 | 59.6 | 18.5 ms | 65.8 ms |
| 红船起飞到崖顶 | 60.0 | 18.5 ms | 18.8 ms |
| 满速飞越礁线到岛 | 59.0 | 18.5 ms | 67.2 ms |

第二个客户端在木屋，始终能看到同一房间中的远端玩家坐标。游越礁线及登岛、飞船跨礁两个阶段都没有新增地图分块请求。[崖顶实玩截图](../evidence/coast-20261120/foreground-final/clifftop.png) · [潜水实玩截图](../evidence/coast-20261120/foreground-final/underwater.png) · [岛顶实玩截图](../evidence/coast-20261120/foreground-final/island.png)

替换崖壁贴图后，在同一台 Mac M1 前台重跑完整路线。约 115 秒、6,879 个帧间隔，整体 59.8 FPS。崖顶走下沙滩一段为 59.4 FPS，P95 为 18.6 毫秒。完整测试有 4 个帧间隔超过 50 毫秒，最长 99.6 毫秒，通过七段的帧时门槛。[崖壁新版逐帧报告](../evidence/coast-cliff-20261120/foreground/report.json) · [海湾新版俯瞰](../evidence/coast-cliff-20261120/bay-aerial.png)

Mac 发行版已复验加入房间和恢复岛顶存档。4494 试玩入口实际传输的 PCK 与 Mac 版散列一致。[Mac 入房记录](../evidence/coast-cliff-20261120/native.json) · [新版发行包校验](../evidence/coast-cliff-20261120/release.json)

共享物理复验覆盖新旧地形接缝、上坡、下坡、游越礁脊、登岛、满速飞行、海面停泊和岛上位置恢复。接缝采样最大高差约 1.75 厘米，飞船达到 11 米每秒。常规房间联机、重连、并发拾取和存档回归也已通过。[物理检查](../evidence/coast-20261120/physics.json) · [联机检查](../evidence/coast-20261120/network.json)

```sh
"$GODOT_BIN" --headless --path coop --script "$PWD/scripts/test-coop-coast.gd"
```

[海岸俯拍](../evidence/coast-20261120/aerial-daylight.png) · [崖顶视角](../evidence/coast-20261120/clifftop-daylight.png) · [沙滩和浅礁](../evidence/coast-20261120/shallow-reef.png)
