# 雨线营地 · Godot 合作生存样片

**在同一 Wi-Fi 上试玩**，房主在当前目录运行下面的命令，然后在电脑浏览器打开终端打印的营地链接。队友只需浏览器，房主也无需打开 Godot 编辑器。

```sh
npm run coop:lan
```

- **本机入口**　点击「进入林地」，WASD 行走，鼠标转向，E 互动，Q 切换当前目标，Esc 松开鼠标。点「邀请队友」后，邀请地址会自动选中，按 ⌘C 或 Ctrl+C 即可复制给同一网络的朋友。房主的服务需保持运行。[打开雨线营地](http://localhost:4184/coop/?room=pine)
- **一场合作**　从木棚出发，可分头去鹿鸣溪谷取木料、去北坡瞭望塔取防水布。任务栏显示方位、距离及队伍物资。带齐材料，任一队员回木棚按 E 修屋，所有人都能看到屋顶补齐、营灯亮起。有人在线时房间时钟前进，65 秒后开始下雨，15 秒内逐渐加大。晚归仍能完成任务。
- **湖岸和星空**　从鹿鸣溪谷沿水面朝西边的小栈台走。新房间第一场雨约在第 119 秒结束，随后可以在栈台看落日。约第 150 秒，抬头从南至西南一带开始找银河。昼夜一轮约 7 分钟。
- **用石块**　木棚外的出生点和栈台入口附近都有手掌大小的石块。低头对准，看到提示后按 E 捡起。大块磨石固定在营地地面，靠近后手持扁石片按 F 磨刃。靠近帆布角或麻绳时，按 F 执行当前提示。持物时用左键投掷，按 G 放下。投石入湖会激起水花与涟漪，浅水里的石块还能捡回。
- **木桌与背包**　进木棚后往右看。E 拾取苹果或面包，F 可以当场吃，也可以向水壶喝水。Tab 打开个人背包。靠近木桌能将食物放回桌上。屋内摆件和干燥的屋顶有助于恢复心情。
- **房间与重玩**　每间房最多 4 人，也可单人完成。首次打开默认进 `pine`。点网页的「另开营地」得到独立新房间，再将邀请链接发给队友。浏览器刷新会重连；关闭标签页再开可能获得新玩家身份，房间物资与修复进度按房间码保存。
- **Mac 与网页一起玩**　服务启动后运行 `npm run coop:native`，即可从 LaunchServices 打开同一个默认房间的 Mac 发行版。也支持 `npm run coop:native -- '完整网页邀请链接'`。房主的 Mac 自动从回环地址连接自己的服务，复制给朋友的邀请仍指向同网地址。两端共享 GDScript 移动、碰撞和交互规则。
- **仅在自己电脑上玩**　可用 `npm run coop` 启动回环服务。两台设备组队要使用 `coop:lan`。若已经在前台启动了仅本机服务，先在它的终端按 Ctrl+C，再用局域网命令启动。

## 合作版实现与复验

营地到溪谷的小径旁有八株会长大的树：四株松树、两株白桦、两株云杉。在木棚外朝左看，可以先找到白色树干的成桦。新开营地能看到从幼苗、幼树到成树的过程。走近并看向其中一株，可读到阶段提示。房间无人时成长暂停，再进房会延续此前的树龄。


世界分成 7 个区域，共用 PBR 纹理。先请求营地几何，再按距离预取相邻区域，走远后释放旧分块。溪谷、湖岸、瞭望塔与木棚处于同一块连续世界中。浏览器通过同源 WebSocket 与 Godot 权威服务器通信，Mac 使用相同协议。服务端校验距离、速度、材料与房间人数。任务和石块操作成功前原子保存，位置和天气约每 4 秒以及离房时保存。空房暂停时钟。存档位于项目的 `.local-rooms/`。

服务端使用已安装的标准版 Godot 4.7.2，无需导出模板即可启动。用 `npm run coop:build:web` 从源构建网页，需 Node.js、Python 3、NumPy、Pillow 和同版 Godot。Mac 上的 `npm run coop:build` 会同时构建网页和 Mac 客户端。网页使用 WebGL 2、Compatibility 渲染器与单线程导出，分块、WASM 和 PCK 均可用 gzip 传输。对外可访问的公网房间、Steam 好友邀请和手机触控尚未实现。

- [合作样片验证记录](coop.md)　·　[素材来源与许可](woodland-assets.md)。新地图沿用该页的 CC0 林地材质，新增木塔、溪流、物资和营地构件为本项目程序化几何。HUD 字体的来源及许可在 [NOTICE](../coop/fonts/NOTICE.txt)。
- 房间逻辑与断线复验可运行 `npm run coop:test`。服务启动后，用 `node scripts/coop-playtest.mjs` 复验 Mac 与有窗口 Chrome 的任务流程，用 `node scripts/coop-web-check.mjs` 复验浏览器限速首开和双浏览器入房。测试使用独立房间。

### GitHub Actions

推送到 `main` 或打开 PR 时，Ubuntu 运行器用 Godot 4.7.2 执行无窗口测试，覆盖联机房间、重连、存档、生存状态、石块提示、点灯和日出。运行记录可在 [Co-op CI](https://github.com/skysf/cooper-game/actions/workflows/coop.yml) 查看。

在该页点 **Run workflow**，选择 `web` 或 `macos` 手动打包。成功后可下载对应的 Artifacts。将 Web 包中的 `index.html`、WASM、PCK、脚本和 `zones/` 放进 `dist/coop/`，即可启动本机房间服务。Mac 客户端加入同一服务加载分块。这些检查覆盖逻辑与导出，显卡帧耗仍由实际试玩测量。

## 原始 A/B 对照片

在当前项目目录运行以下命令。两份网页发行构建已放在 `dist/`，本机试玩只需 Node，无需打开编辑器。服务仅监听本机回环地址。

```sh
npm start
```

| | 自由试玩 | 固定路线测试 | 大雨迭代 |
|---|---|---|---|
| A · Babylon.js + TypeScript | [进入林地](http://localhost:4173/a/) | [测试 60 秒](http://localhost:4173/a/?bench=1) | [大雨试玩](http://localhost:4173/a/?profile=storm) |
| B · Godot 4 + GDScript | [进入林地](http://localhost:4173/b/) | [测试 60 秒](http://localhost:4173/b/?bench=1) | [大雨试玩](http://localhost:4173/b/?profile=storm) |

点击「进入林地」，用 **WASD** 行走、鼠标看向四周。沿泥路走约 98 米到木棚。行走模式累计 30 秒开始下雨，**R** 可手动切换，**Esc** 暂停并释放鼠标。沿原路或在棚内都可继续活动。固定路线会自动行走，30 秒切换天气，60 秒后显示成绩，可下载逐帧 JSON。

**复核画面**　在任一版地址后加 `?view=clear` 或 `?view=rain` 即可停在同一个机位。`?view=rain&profile=storm` 使用加大的雨量和更湿的泥地。同一时刻只打开一个活动的 3D 页面。

## 运行与重建

- 运行已有 Mac 版可用 `open dist/native/Woodland.app`。原生走 GDScript 输入与碰撞。用 Finder 双击也会通过 macOS 的 LaunchServices 启动。
- 安装开发依赖用 `npm ci`。更新 A 用 `npm run build:a`，更新 B 用 `npm run build:b`。从源码重新打包 Mac 用 `node scripts/godot.mjs build-native`。两端的场景生成和导出均在命令行完成。
- Godot 脚本查找 `/Applications/Godot.app`、`~/Downloads/Godot.app` 与 PATH，也支持 `GODOT_BIN` 指定可执行文件。此项目锁定标准版 4.7.2，Web 用单线程 release 模板和 Compatibility 渲染器。重新取得缺失模板时，脚本会从官方归档提取所需条目，在项目缓存中校验。 [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) · [Web 导出说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- 再测浏览器请先启动服务。在另一终端运行 `npm run benchmark`，会打开一个本机 Chrome 窗口，复用同一标签页运行 A 冷、A 热、B 冷、B 热。用 `npm run benchmark -- qa` 复核控制与截图。输出写入 `evidence/`，重跑会更新同名记录。

## 场景和基准

[layout.json](../shared/layout.json) 定义路线关键帧、水平视野、相机裁剪面、玩家尺寸、晴雨参数与两个天气档位。生成的 [scene.json](../shared/scene.json) 固定实际物体位置、尺寸和碰撞范围。[同一份 GLB](../shared/woodland.glb) 内嵌五套 CC0 PBR 材质，来源和逐文件校验见 [素材说明](woodland-assets.md)。

两份 Web 样片使用同一浏览器控制器处理鼠标、键盘、平地约束、水平圆形碰撞、路线与测量。A 的世界由 Babylon 渲染；B 的场景加载、相机、材质、照明、雨丝和原生模式由 GDScript 实现。这样可比较网页交付和渲染成本，尚不能据此估算完整生存玩法的物理或脚本开销。

两边都要求 WebGL 2，绘图缓冲区固定为 1280 × 720。每次首帧后检查 `drawingBufferWidth/Height`，尺寸不符会中止测试。水平 FOV 78°，绘制远面 115 米，雾参数、雨丝几何与数量见共享清单。两边均关闭 MSAA 和几何 LOD。测量时保持同一显示器与前台标签页。

平均 FPS 用帧间隔个数除以该阶段所有间隔之和（秒），P95 取排序后的第 ⌈0.95N⌉ 个间隔。按上一帧所属天气统计跨界间隔，雨天统计包括一秒的天气过渡。首次可操作为页面导航开始到首次场景完成渲染且输入按钮已启用。数据包括网页解析、下载、WASM 或 JS 初始化和首帧准备，属于应用帧间隔，尚未测 GPU 单帧耗时。

[对比报告与截图](engine-comparison.md)
