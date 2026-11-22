# 雨线营地 · 合作试玩记录

本次交付是现有林地中的短合作任务。出生地在木棚外，玩家可分头去溪谷取木料、去北坡瞭望塔取防水布，再回棚修屋。木料与防水布分别放进实际拾取者的背包，同类各占一格；修屋从行动者背包消耗各 1 份。队友间可通过丢下和拾取交接。营灯、修复后的屋顶和屋顶下的遮雨效果对房间内玩家共享。

## 怎么玩

房主运行 `npm run coop:lan`。在电脑浏览器进入终端打印的同网地址，点「邀请队友」。同房支持最多 4 名玩家。对方也可在本机项目运行 `npm run coop:native -- '邀请链接'`，用 Mac 窗口加入。网页右下角的「另开营地」会给出一间独立的新营地。Godot 编辑器可以保持关闭。

WASD 行走，鼠标看向四周，顶部显示当前目标的方向和距离。Q 切换队伍尚缺的材料，靠近物品 2.5 米内按 E。材料齐备后返回木棚，按 E 修复。房间进度按房间码保存，本次刷新同一标签页后，玩家回到了修屋时的位置。

从木棚沿小径走向鹿鸣溪谷，可看到四株松树、两株白桦和两株云杉。走到树旁六米内并看向它，左上角会显示树种、阶段和下一阶段的倒计时。新营地中，营地的松苗约在第 7 秒进入幼树阶段、第 42 秒进入成树阶段，继续长高后稳定下来。房间里的队友看到同样的阶段。成长按房间在线时长计算，空房暂停，重新进入后继续。

## 木屋防风油灯

站在木屋外面朝入口看，油灯挂在右侧立柱旁的横梁下。未修屋时可以透过玻璃看到灯芯；材料齐备后回屋按 E，灯焰亮起，暖光照到柱子和门口地面。亮灯沿用房间的修屋存档。项目自制的模型包含提梁、弯曲的侧管、玻璃罩、金属护丝、加油盖和调芯轮。

油灯光源随木棚加载。修复后，灯焰尺寸与光强在 0.55 秒内逐渐升高。Godot 无窗口回归覆盖了修复触发、渐亮与恢复熄灯。

可以直接在 Blender 里修改[油灯源文件](../art/camp_lantern.blend)。游戏读取[导出模型](../coop/props/camp_lantern.glb)，其中 `Flame` 节点的原点位于灯芯顶端，Godot 用它控制点火和火苗高度。项目目录下可用以下命令重新生成模型，并构建可玩的版本。

```sh
./scripts/start-blender.sh --background --factory-startup --python scripts/build-camp-lantern.py
npm run coop:build
```

灯从梁底到油箱底高 58.2 厘米，包含 20,680 个三角形。深青色搪瓷边沿有单独建模的磨损痕迹，灯罩的边缘反光由[玻璃着色器](../coop/materials/lantern_glass.gdshader)计算。

在 M1 的 Chrome 中，两个客户端加入同一个预置木料和防水布的测试房间。第一人留在门口，第二人走近维修点按 E，第一人同步看到火焰和暖光出现。前后截图均为 1280 × 720 实际游戏画面。[熄灯](../evidence/lantern-off.png) · [点亮](../evidence/lantern-on.png) · [联机实测](../evidence/lantern-qa.json)

## 昼夜、鹿鸣湖与石块

昼夜、云层、天气和投石涟漪共用房间时钟。以北纬 43°、九月初为参考，日月沿各自的轨迹运行，月相随照射角改变，星野随恒星时从固定的赤道坐标转动。首轮第 65 秒开始降雨，第 101 秒起雨势减弱，约第 119 秒停止。第 122 秒左右日落，约第 150 秒进入适合观星的深暮色。银河使用 ESO/S. Brunier 的实拍全天全景，月面使用 NASA 的 LRO 彩色图，月相和现场亮度由着色器计算。ESO 原图位于 `art/sky/eso0932a.jpg`。用于游戏的全景缩为 4096 × 2048。XHIP 星表和程序化月面为缺少贴图时的回退。[天空素材来源与许可](../coop/sky-assets.LICENSE.txt)

太阳阴影在昼夜交替时连续改变浓淡与范围。网页版用一张 2048 像素的太阳阴影贴图，最远覆盖 30 米。无窗口回归检查日出和暴雨时的阴影变化。在 Apple M1 内建 60 Hz 屏的 Chrome、1280 × 720 下，通过 E 键首次修屋点灯和跨越日出的两次候选版采样分别为 60.00 和 60.01 FPS，最长绘制间隔均为 18.7 毫秒。[复测机位与判定方法](render-benchmark.md)

白天的天空随视角和太阳方向改变散射色。高空薄云和低空积云各自随风移动，积云的亮边和暗部取决于太阳方向和云层厚度。傍晚从动态天空淡入 ambientCG 的 2K 实拍全景，随后过渡到夜空。游戏版贴图裁掉了原图中的地面和拍摄时的太阳，贴图中的亮区与游戏太阳方向对齐。天空、岸边光色和水面共用暮光强度。贴图随场景初始化，白天、深夜和暴雨逐渐恢复相应天色。[傍晚贴图与原始来源](../coop/sky-assets.LICENSE.txt)

鹿鸣湖位于溪谷西侧。溪床和湖盆共用高度规则，支持沿浅滩行走及登上栈台。水面根据视角、水深、房间天色和雨势切换反射、透视和波纹。近湖时，低分辨率反射视口按需绘制指定远岸景物。投石入水时，服务端广播落点和时间，每个客户端据此绘制同一组水花和涟漪。

远岸树冠从营地的松树、云杉和白桦模型烘焙。浅水能透出河床碎石和水草，水下能见距离随镜头深度、雨量和光照变化。以下两张图来自 1280 × 720 网页发行包，使用 Apple M1 的 Metal 后端和无窗口 Chrome 复拍。[从栈台看远岸](../evidence/lake-optics/current-lake.png) · [水下 0.9 米](../evidence/lake-optics/current-underwater.png) · [画面与逐帧记录](../evidence/lake-optics/render-benchmark.json)

从东岸栈台俯视，浅水可以看见天然碎石、沉积物、砾石滩和成簇的水草。向西平视时，树冠、岸坡和天空会在细浪间形成倒影。按 C 下潜，能见距离随镜头深度、日照和雨势变化，清天的湖床上有随波移动的光纹。抬头可见折射的天光，靠近水平方向时水面对湖内光线形成全反射。[湖床与岸林素材](woodland-assets.md#鹿鸣湖床与西岸树林)

圆石可压帆布，压住时布角的摆动减弱。扁石可在营地磨出刃口，再割开木板上的麻绳。石块的归属、位置、刃口和割绳状态由房间服务器管理。正常离房时玩家手中的石块落在脚边。入水后若停在够得到的浅处，可以捡回。旧房间首次读取时补齐营地和湖岸的石块，并继续原来的房间计时和修屋进度。[石块模型来源](woodland-assets.md#可拾取的石块)

Godot 无窗口验证走通了服务端抢拾、压布、磨刃、割绳、投掷、落点生成与存档恢复。早期的天空预览使用无窗口 OpenGL 渲染。后续的网页回归从实际房间进入湖岸、下潜和修屋，保存画布截图与逐帧间隔。[昼夜预览](../evidence/coop-sky-offscreen.jpg) · [银河预览](../evidence/coop-milky-way-offscreen.png) · [Godot 验证输出](../evidence/coop-lake-headless.txt) · [网页画面基准](render-benchmark.md)

| 功能 | 入口 |
|---|---|
| 日月、星野、云层和照明 | [atmosphere.gd](../coop/atmosphere.gd) · [camp_sky.gdshader](../coop/materials/camp_sky.gdshader) |
| 湖岸、栈台、浅水深度和倒影 | [lake.gd](../coop/lake.gd) · [water_layout.json](../coop/water_layout.json) · [water.gdshader](../coop/materials/water.gdshader) |
| 石块交互、飞行和房间存档 | [stones.gd](../coop/stones.gd) · [stone_scene.gd](../coop/stone_scene.gd) · [server.gd](../coop/server.gd) |

## 红色飞船与水中移动

飞船停在出生点往鹿鸣溪谷方向约 6 米的空地。看向飞船按 E 登机。空格上升，C 下降，WASD 水平移动，鼠标转向。向前加速时船尾两台主引擎向后喷射。垂直起降用船腹喷口，斜向爬升时可以同时看见两组喷流。松开方向键会减速悬停，V 在跟拍与驾驶位之间切换，在船外可以看到驾驶员落座。

降落时服务端检查船体下方多处接触面。平地、开阔水面、宽石面和有足够承托的树冠都可以停靠。靠边或坡度过大时船会向下滑。湖面停稳后按 E 下机可在船旁游泳，浮到水面后看向飞船可重新登机。

每个房间共用一架飞船和一个驾驶位。位置、驾驶员和降落状态由房间服务同步。每次停稳都会记录停船位置，驾驶员在飞行中断线时，飞船回到最近一次停稳的地方。角色走入深水后自然切换到游泳，C 下潜，空格上浮。陆地空格用于跳跃，小石块可直接跨过。

原件归档在 `art/vehicles/source/红色科幻飞船.glb`，运行资产由 [转换脚本](../scripts/build-camp-spaceship.py) 生成，接收支持 `meshopt_simplifyWithAttributes` 的 meshoptimizer 动态库路径。模型保持 89,988 个三角面，机头朝 Godot 的 `-Z`。新版将颜色与法线贴图恢复到源文件的 2048 × 2048，金属度和粗糙度图为 1024 × 1024，启用各向异性过滤，GLB 为 5.72 MB。 [运行资产](../coop/props/camp_red_spaceship.glb) · [Godot 同机位对照](../evidence/airship-hull-detail.jpg)

## 营地声音

泥路、林地落叶、木栈台和浅水各有脚步声。进入深水、在水面划水和下潜有各自的水声。投石和落石声随房间服务器确认的动作播放，石块落在泥地、木板、硬物和水里时音色不同。附近队友听到动作发生的方位。红船登机时启动，运转声音随推力变化，停稳下机后关闭。

北坡林地使用鞋底压过腐叶和松针的录音，裸土坡和泥路使用鞋底轻擦细土的录音。两种地面各有三个实录风格的 SkyCut 单步，行走和跳跃落地都按脚下地面选取，同一人物连续两步会换用另一条。东部地面的判定随地形烘焙，沿用画面中沙土和小径的分布。游戏资源从 SkyCut 工程中标记的六个片段导入为 16 位单声道 PCM。 [SkyCut 工程](../art/game_audio/雨线营地%20·%20环境与生物音效.skycut) · [Godot 导入脚本](../scripts/import-footstep-cues.gd) · [北坡实机录音](../evidence/forest-footsteps-20261121/loam.wav) · [土坡实机录音](../evidence/forest-footsteps-20261121/soil.wav) · [网页播放验证](../evidence/forest-footsteps-20261121/verification.json)

脚步和划水声跟随角色位置和实际位移。一次性音效最多同时播放 8 路，飞船、雨、溪流和泉眼、营火、鳄鱼游动各有独立循环。Mac 与支持 AudioWorklet 的网页使用 Godot 音频，普通局域网 HTTP 页面通过 Web Audio 播放包内同一份 PCM。网页自动播放由「进入林地」时的点击解锁。 [音效脚本](../coop/camp_audio.gd) · [合成脚本](../scripts/build-camp-audio.py)

SkyCut 生成的 18 条录音已进入游戏包。苹果有清脆的咬皮声，面包和三明治用较轻的撕咬声，肉类用纤维撕开和咀嚼声。营地水壶、桌上溪水和背包里的水共用吞咽声。进食、取物、制作及采矿在房间保存成功后才向附近玩家发声。击中人或动物的声音与挥空分开。鳄鱼发起扑咬会播放一次攻击声；只有游动、潜入或浮出时有游水声。矿洞深处会衰减户外雨声，营火只在燃料有效时可听到。 [录音清单与响度](../evidence/eastern-ground-repair-20261121/sounds.json) · [双人局域网音频实测](../evidence/eastern-ground-repair-20261121/voice-and-food.json) · [浏览器 AudioWorklet 实测](../evidence/eastern-ground-repair-20261121/voice-and-food-worklet.json)

室外雨声使用 SkyCut 原录音的两个声道。预处理去掉收尾的低音量片段，将两段稳定雨声等功率交叉淡化，并把文件接点放在相邻的原始采样之间。网页通过 Web Audio 在音频线程上循环，Mac 使用无方向的立体声播放器。降雨强度、人物潜水和矿洞深度控制音量，切换肩后视角时沿用人物所在位置。湖岸倒影使用独立的渲染层，进入游戏前按同一图层绘制两侧河岸。实测首次转身时的材质程序链接从 7 次降到 0 次。 [雨声制作脚本](../scripts/prepare-rain-loop.py) · [转向与循环实测](../evidence/rain-loop-20261121.json)

## 木屋里的桌子与补给

进木棚后靠右是一张 1.58 × 0.72 米的木桌。桌面用四块带开缝的旧木板拼成，桌腿向外微斜，木销固定桌面。靠走道的木板上刻着 `SKY 1120`。在 Blender 中逐笔画出字形，再把深浅不一的 V 形刀槽直接做进桌板网格。桌子和石陶水壶共用一份可编辑的 Blender 源文件。 [编辑源件](../art/camp_table.blend) · [初始建模脚本](../scripts/build-camp-table.py)

水壶使用一套 1024 × 1024 的颜色、法线和粗糙度贴图。青灰釉上有拉坯细纹，壶底露出陶胎脚圈，上把手和壶颈以一圈陶泥衔接。桌上、落地和携带状态载入同一模型，摆放包围与原水面位置沿用现有数据。 [游戏模型](../coop/props/camp_water_jug.glb) · [桌面与把手同机位对照](../evidence/camp-water-jug-20261120/same-camera.jpg) · [水面、落地和携带对照](../evidence/camp-water-jug-20261120/placement-and-water.jpg)

桌上初始放两只苹果和两个面包。按 E 拾进个人物品栏，按 F 原地吃。看向水壶按 F 喝水。按 Tab 打开物品栏，苹果和面包显示各自模型渲染的缩略图，格子角落显示堆叠数量。背包统一按物品种类计格：同种食物、药草、溪水、材料、衣物、武器或盾牌，无论数量都合并在同一格；不同种类分别占格。选中后仍每次吃、放下或在桌边放回一份。

木棚左侧地上有一个 [实物背包](../art/camp_backpack.blend)。第一位走近并按 E 拾取的玩家自动穿戴，物品栏从六格扩到十二格。背包归属、物品和个人状态保存到原房间，联机队友都能看到佩戴效果。原始 Blender 文件经过 [导出脚本](../scripts/build-camp-backpack.py) 生成运行模型，脚本也会从游戏实际使用的苹果和面包 GLB 渲染物品栏图片。

按 V 在第一人称和第三人称之间切换。第三人称从肩后稍高处跟随角色，户外默认看见全身。靠近墙壁、树干或屋顶时镜头收近，离开障碍后逐渐拉回。

Tab 面板有「背包」和「角色」两个页签。背包左栏按全部、食物和服装筛选，中间保留物品模型小图与堆叠数，右栏显示选中物品的大图、食材增益或穿戴部位以及可用操作。「角色」页有可拖动旋转的全身预览、装备部位和个人状态。选中部位可穿上包内同部位衣物、脱下收进背包，或直接丢到脚边。同种脱下衣物累加到同一格，队友可以拾取地上的衣物。穿戴状态和掉落地点随房间存档。旧房间首次加载会为玩家穿上帽子、夹克和长裤。木屋门内地面每个房间放一顶头盔。看向头盔按 G 拾取，从背包戴上时原有帽子收进背包。

2026-11-19 帽子比例修正烘入 `art/camp_cap.blend` 并重导出 `coop/props/camp_cap.glb`、`coop/textures/inventory_cap.png`，原 Hiker 挂点与缩放保持。实际穿戴宽度由 22.50 cm 收到 16.70 cm，帽顶高出头皮由 5.14 cm 降到 1.33 cm；正侧背均贴合且保留眉眼、眼镜。 [相同机位旧新对照](../evidence/cap-fit-20261119/role-preview.png) · [最终发行包真实角色页](../evidence/cap-fit-20261119/character-page-cap-final.png)。Godot 导入、短资产/坐姿/脱戴检查、无头 Chrome 角色页与 Mac 最短独立入房已验证。22:37 通过完整静态目录原子交换热更新 4284，房间服务器与实时存档未重启或改写；服务 PID 93107、原 4184 PID 76294 保持。当前实际包版本见 `evidence/cap-fit-20261119/live-release.json`，刷新原标签页即可使用。

服装源文件为 `art/camp_jacket.blend`、`art/camp_pants.blend` 与 `art/camp_cap.blend`。[服装导出脚本](../scripts/build-camp-clothing.py) 在 Blender 中适配比例并生成运行模型和物品图。夹克在贴体前减面，保留原件的平滑法线、拉链、胸袋和 1024 像素颜色贴图。夹克和长裤跟随角色的手臂和腿摆动。头盔和左右登山靴的 [适配导出脚本](../scripts/build-camp-wearables.py) 读取用户提供的 GLB。 [头盔 Blender 源文件](../art/camp_helmet.blend) · [登山靴 Blender 源文件](../art/camp_boot.blend)

[全身角色源文件](../art/characters/sky_character.blend) 的 [Godot 运行模型](../coop/props/sky_character.glb) 共用于角色预览、本地第三人称、队友和驾驶员。站姿骨骼驱动走路、游泳和右手持物，坐姿带动夹克和长裤的肘膝。左右登山靴默认穿戴，各自跟随脚骨。走路、跑步和落地按真实鞋底网格校准。帽子和头盔跟着头骨转动，穿戴时收起头发网格。 [夹克、靴子与头盔实装对照](../evidence/camp-ui/wearables-detail.jpg)

网页加载时，角色预览在油灯预热后完成一次实际绘制。点开「角色」直接显示保留的纹理，拖动或穿脱时才更新，关闭后停止绘制。[首开角色页实测](render-benchmark.md#角色预览首开)

在 Apple M1 的 Godot 4.7.2 Compatibility 渲染器验证了 1280 × 720 的场景与装备页。无窗口测试覆盖物品筛选、堆叠重排、穿脱、满包、帽子和头发、手部持物、鞋、肘膝和联机驾驶座。 [原生角色](../evidence/camp-ui/character-native.png) · [帽子](../evidence/camp-ui/character-cap-native.png) · [第三人称](../evidence/camp-ui/third-person-native.png) · [驾驶座](../evidence/camp-ui/pilot-native.png)

无窗口 Chrome 使用 Apple M1 的 Metal 渲染器加入真实测试房间。Tab 打开十二格背包，吃掉一份苹果后服务器增加饱腹值，角色页可脱下夹克进包再穿回。拖动转身后缩到 960 × 540，仍可用 Esc 关闭。 [网页背包](../evidence/camp-ui/backpack-web.png) · [筛选](../evidence/camp-ui/backpack-filter-web.png) · [角色](../evidence/camp-ui/character-web.png) · [转身](../evidence/camp-ui/character-profile-web.png) · [紧凑窗口](../evidence/camp-ui/character-compact-web.png) · [记录](../evidence/camp-ui/browser-qa.json)

同机的网页和 Mac 发行版也在一个双人房间走通了采集和修屋。网页玩家用 WASD 和 E 取回木料、防水布，Mac 队友在房间第 129 秒看到了修好的屋顶。刷新网页后，服务器恢复了同一名玩家、原位置和任务进度。此次桌面处于锁屏状态，网页测试模拟了焦点和鼠标锁定，Mac 客户端以无窗口方式运行。[修屋画面](../evidence/camp-ui/cross-platform/repair.png) · [跨端试玩记录](../evidence/camp-ui/cross-platform/report.json)

饱腹和水分随在线时长缓慢下降。苹果补饱腹和少量水，面包更顶饱。屋内两件摆件会加快心情恢复，屋顶修好后屋里还能避雨。四件游戏模型已放在 [coop/props](../coop/props/) 中。需要重做时，可从 [Artaley3D](https://artaley3d.com/models) 下载四件原始扫描，解压到 `art/household/`，再运行 `python3 scripts/build-camp-household.py`。房间用 [survival.gd](../coop/survival.gd) 统一定义食物类型和进食效果，后续动物投喂可以沿用同一类背包物品。

无窗口服务端回归走通了旧存档、两人抢拾、私人背包、吃喝、放回、放下、心情恢复、存档失败回滚和重启恢复。网页和 Mac 发行包均读到了木桌刻槽、食物实例和桌边碰撞。刻字近景由 Blender 使用原桌板渲染。[回归脚本](../scripts/test-coop-survival.gd) · [SKY 1120 刻字近景](../evidence/camp-table-carving.png)

## 角色制作模板

[Sky 全身 Blender 源文件](../art/characters/sky_character.blend)以站立 A 姿打开。模型含发高 1.75 米，下半身的比例依据半身参考推定。脸、耳后和颈部与身体连成一张封闭网格，保留了[定稿头像](../art/characters/sky_head_v3.blend)的正面五官和 UV。眼镜是独立配件，便于更换镜框或制作 NPC 变体。

源文件包含 79 根骨骼及独立的灰色短裤。站姿、单侧抬腿和深坐时，短裤与身体均通过三角面相交检查。深坐姿势下源模板的前裆褶皱仍有少量布面彼此重叠。

游戏中的装备预览、本地角色、联机队友和驾驶员共用同一份 [角色 GLB](../coop/props/sky_character.glb)。运行版约 1.48 MiB，包含 26,574 个三角面、53 根骨骼和三张内嵌贴图。站姿和坐姿分别做过蒙皮验证，颈部、手腕、腰和脚踝的边界在这两种姿势下都能接合。眼镜单独跟随头部。运行时的装备、步态和驾驶动作由 [hiker.gd](../coop/hiker.gd) 驱动。

玩家的[移动动作库](../coop/animations/player_locomotion.tres)沿用这套骨架。步行每周期 1.46 米，快跑每周期 2.56 米，起跳、腾空与落地各有一段动作。蛙泳与踩水的髋部位移按水面高于角色原点 0.12 米制作。七段动作保存在[可编辑 Blender 源文件](../art/characters/locomotion/player_locomotion.blend)中。[穿戴动作对照](../evidence/player-locomotion/)记录同一角色的靴底、眼睛水线与衣袖形变。

## 营地藏獒

从出生点面向木屋，可以在入口右侧或屋前空地找到藏獒。它会在木屋附近走动、停下观察周围。修好屋顶、点亮营灯后，它会回门廊趴一会儿，然后继续走动。走近并看向它，按 E 收养。收养后看向它按 E，可以切换跟随和原地待命。待命时它会趴下，再次跟随前会先起身。已收养的藏獒和主人在修好的木屋里停留时也会休息。

房间只有一只藏獒，由第一位收养它的玩家指挥。位置、归属和指令随房间记录，动作在队友之间同步。跟随使用房间的碰撞规则，遇到木屋侧墙等障碍时会绕行。旧房间更新后会在入口补上这只狗，保留已有的修屋进度。

[Blender 源文件](../art/animals/camp_mastiff.blend)用于编辑。将导出的 GLB 同步到 `coop/props/camp_mastiff.glb` 后由 Godot 导入。运行时按顺序播放 `Lie-down`、`Rest`、`Rise`。停步时播放 `Idle`，近距离走路，落后时用对角步态小跑。步频跟随房间里的实际移动速度，动画切换时平滑过渡。GLB 名称中的 `-loop` 后缀会在导入时启用循环。服务端和客户端回归覆盖自主走动、收养竞争、修屋后回门廊休息、绕墙跟随、待命和存档。

## 湖区住船与绵羊

在 **M → 鹿鸣湖** 落地后，住船停在东岸木栈台外侧，绵羊在栈台靠湖的草坡吃草。走到栈台外端按 **E** 登船，按 **F** 请摆渡人和采药人起桨。也可以站在栈台上按 **F**，从岸边看他们划船。两人各操一舷，起桨后划 17 个完整桨程，再收桨靠回同一座栈台，全程约 47 秒。上船后站在露天甲板，面朝湖面。**WASD** 在甲板走动，按住 **Control** 蹲进船篷，离开低矮处后可站起。**V** 切换观景视角。靠岸后，走近露天甲板出口按 **E** 上岸。 [登船视野](../evidence/lake-dockwork/open-deck-view.jpg) · [湖上实录](../evidence/lake-dockwork/lake-voyage.webm)

篷下左右各有一个铺位，靠近床边按 **E** 躺下，每秒恢复 1.5 点健康，上限 100。再按 **E** 回到过道。每张床一次接待一人，两个铺位可以分别使用，开船后仍可休息。营地绳床采用同一套规则。 [营地建床与安排住民](camp-storage.md#营地绳床)

走近并看向绵羊，按 **E** 剪下一束羊毛。羊会抬头停步，换成剃后的短毛外形。羊毛在房间累计运行 14 分钟后长回。多人同时剪只能收取一束，背包满时保留原毛。狩猎后可从这只羊身上取两份带骨生羊排，有长毛时还可取得一束羊毛。消耗一份生羊排可以在燃烧的营火旁制作一份烤羊排。存档会记录这只羊的生死和毛况。 [实机毛况和背包物品](../evidence/lake-life/sheep-and-lamb.jpg) · [绵羊 Blender 原稿](../art/animals/sheep_study/sheep_study.blend) · [绵羊动作源文件](../art/animals/sheep_study/sheep_motion.blend)

住船沿用湖区设计稿中的搭接木壳、亚麻油布篷和柳编药篮。两个船工的待船、起桨、划水和靠岸动作与房间时钟同步，桨片触水时驱动湖面涟漪与划水声。靠岸时摆渡人双手收绳盘缆，采药人从背篮取出草药整理。开船时两人放下手里的活，各自双手握桨。桨声与沿溪能听到的水声由 SkyCut 生成。 [靠岸人物实录](../evidence/lake-dockwork/dock-chores.webm) · [靠岸动作 Blender 源文件](../art/characters/reed_marsh_study/lakefolk_1700/lakefolk_dockwork.blend) · [船与人物 Blender 原稿](../art/characters/reed_marsh_study/lakefolk_1700/lakefolk_houseboat.blend) · [双人划桨 Blender 源文件](../art/characters/reed_marsh_study/lakefolk_1700/lakefolk_rowing.blend)

从项目根目录运行下面的命令可重新导出游戏模型、生成背包图标及可编辑的动画场景。

```sh
./scripts/start-blender.sh --background --python-exit-code 7 --python scripts/build-lake-life.py
./scripts/start-blender.sh --background --python-exit-code 7 --python scripts/lake_life/presentation.py
```

在鹿鸣湖任一处能够到水面的湖岸按 **F**，可将一份淡水装进背包。在船上或栈台看到开船提示时，按 **R** 取水。

2026-11-21 在独立房间验证了抢同一张床、两张床同时休息、航行中回血和起身让床。网页实测还从住民面板安排俘虏接着使用玩家刚离开的营地床。用游戏中的头盔和篷布网格采样，过道内蹲着转身、蹲走的最小净空约 2 厘米，左右铺位躺下时分别约有 53、56 厘米。可用 `scripts/test-coop-lake-life.gd` 重跑床位、船上移动和人物姿势回归。 [舱内视角](../evidence/lake-dockwork/inside-canopy.jpg) · [夜间登船](../evidence/lake-dockwork/night-from-deck.jpg) · [营地床轮用](../evidence/lake-dockwork/camp-guest-rest.jpg)

## 林地野猪

按 **M** 选择「野猪林地」可到根影林径西侧的观察位置。野猪会沿林地拱土、换地方、屈腿卧下、呼吸和起身。进入约 4.6 米范围会惊动它。野猪先转向目标、踏蹄低吼，约 1.2 秒后沿当时的方向冲撞。侧移可以避开，正面撞到扣 19 点健康，同一轮只结算一次。冲过后它会继续跑开。叫声从野猪所在的位置传出。 [双人带声实录](../evidence/woodland-boar/forest-encounter.webm)

野猪倒地后按 **E** 取材，有两份生野猪肉、两枚獠牙和一张整皮。在点燃的营火旁，每份生肉可烤成一份烤野猪肉，补充 35 点饱腹和 5 点心情。取材剩余量随房间保存。尸体取空且距倒地已满 15 分钟房间运行时间后，林地会再出现野猪。

| 营地木桌配方 | 材料 | 用法 |
|---|---|---|
| 獠牙扣猎人披肩 | 野猪皮 1、野猪獠牙 1、绳子 1 | 在背包里穿戴，可以和夹克一起穿。雨天引起的心情损耗减少三分之一。 |
| 獠牙猎犬哨 | 野猪獠牙 1、绳子 1 | 在背包选「吹哨召回」。36 米内自己收养的藏獒会沿可走路线跟来。 |
| 猪皮铺盖卷 | 野猪皮 1、羊毛 1、绳子 1 | 从背包选「铺开休息」，瞄准平地后左键放下。按 **E** 躺下或起身，空置时按 **G** 收卷。玩家、同伴、俘虏轮流使用，每张铺盖一次容纳一人。 |

原画稿包含野猪、肩肉、整皮和一对下颌獠牙。动作源文件保留蒙皮、十段动作及营地装备模型。进入 Blender 动作编辑器可以切换动作。游戏模型约 2.91 万个三角形，网页版和 Mac 版共用同一套动画数据。 [Blender 原画稿](../art/animals/boar_study/wild_boar.blend) · [动作与装备源文件](../art/animals/boar_study/wild_boar_motion.blend) · [动作预览](../art/animals/boar_study/wild_boar_motion.jpg)

## 鹿鸣湖的鳄鱼和老鹰

鳄鱼从鹿鸣湖东南岸靠溪谷的一段岸边开始巡游。它会趴在岸上、走入水中、游泳、下潜和上浮。水位使用与湖面和投石相同的高度清单。靠近岸上的鳄鱼会先看到扑咬预警，后退可以躲开。咬中扣 18 点健康，回到修好的木屋会逐渐恢复。投石打中鳄鱼前半身会触发缩退，岸上的鳄鱼接着退向水里。

老鹰会在湖东岸栈台附近松树的低枝栖停，然后起飞绕湖，途中拍翅、滑翔、转弯和俯冲，也会落到岸上短暂停留。落枝使用 GLB 的 `PerchContact` 对齐直径约 9 厘米的枝条。整轮航线约 66 秒，由房间时钟驱动。队友共享鳄鱼的位置、动作与老鹰航线。

两种动物的 Blender 源文件和导出稿在 [art/animals](../art/animals/)，Godot 加载 `coop/props/camp_crocodile.glb` 与 `coop/props/camp_eagle.glb`。无窗口验证覆盖七段鳄鱼动画和十段老鹰动画、抓枝对齐、岸上扑咬、飞行中的石块命中、健康恢复和旧房间存档迁移。实际浏览器画面和帧率待测。

## 混交林网页版实测

在 Apple M1 的桌面 Chrome 中，WebGL 2 绘图缓冲区为 1280 × 720。沿小径能在同一画面中看到针叶和白色桦树干。分别走近的观察机位显示「白桦 · 成树」与「云杉 · 成树」。同一版本也通过了浏览器行走测试，从营地出发拾取木料和防水布、返回修屋，再刷新页面，任务与位置均恢复。

下节的帧率数据来自较早的四株松树版本。[林间小径](../evidence/mixed-trail.png) · [营地白桦](../evidence/mixed-birch.png) · [雨中云杉](../evidence/mixed-spruce.png) · [浏览器记录](../evidence/mixed-forest.json)

## 松树试种实测

试种区共四株松树。幼树与成树的树干、枝条取自 Poly Haven 的 Pine Tree 01 B 变体，树冠用原素材的针叶照片和遮罩重新布置。幼苗另建了适合这一阶段的轮廓。单株三个阶段分别为 340、2,533、4,158 个三角面。[原素材、许可和生成脚本](pine-tree.md)

同一机位拍下营地旁一株松树，第 1 秒高 0.60 米，第 19 秒高 1.96 米，第 48 秒高 4.32 米。稍后加入的第二个网页玩家也看到该株处于成树阶段。旧存档首次更新保留原房间天气及物资，服务重启后两个客户端读回相同的成长时钟。[三阶段同机位截图](../evidence/grove-growth.jpg) · [浏览器记录](../evidence/grove-comparison.json) · [双端及旧存档验证](../evidence/grove-rooms.json)

在 M1 同一个有窗口的 Chrome 标签页、实际 1280 × 720 的固定林地视角，晴天和暴雨各采样 8 秒。下表为浏览器动画回调间隔。该窗口本轮约 25 Hz，每种条件单次采样，观察到的小幅差异不足以判断 GPU 性能余量。

| 画面 | 改动前平均 FPS | 试种后平均 FPS | 改动前 P95 帧耗 | 试种后 P95 帧耗 |
|---|---:|---:|---:|---:|
| 晴天 | 24.5 | 25.0 | 41.7 ms | 41.7 ms |
| 暴雨 | 24.6 | 24.9 | 41.9 ms | 41.8 ms |

在同一 Wi-Fi 地址和限速条件（下行 10 Mbps、上行 2 Mbps、70 ms 延迟）下，改动前后各测一次冷启动。首次可操作从 12.48 秒到 13.02 秒，届时已完成的子资源传输从 12.95 MiB 到 13.41 MiB。[同机位晴天](../evidence/grove-after-clear.png) · [同机位暴雨](../evidence/grove-after-rain.png)

试种后的网页和 Mac 发行版也走通了整段任务。网页玩家经过松林，在暴雨中带回木料和防水布，对端观测到已修好的屋顶。浏览器刷新后身份与进度保留。

## 初版合作样片验证

- **朋友从链接进场要多久**　在这台 M1 的有窗口 Chrome 157 中，用局域网 IP、空 HTTP 缓存、模拟下行 10 Mbps／上行 2 Mbps、70 ms 延迟测了一次。从导航到角色可以操作用时 **12.48 秒**。当时已完成的子资源传输合计 **12.95 MiB**，营地几何已就绪，邻区已开始预取，瞭望塔尚未发起请求。第二个独立浏览器上下文从页面里选中并打开邀请地址，双方都显示 2 人及 1 个队友角色。两个上下文运行在这台 Mac 上。
- **局域网地址单人通关**　通过同一 Wi-Fi 地址打开网页，用实际键鼠输入完成双材料采集与修屋，在第 78 秒确认棚下避雨。随后按 Esc、打开邀请并刷新，身份、位置和屋顶均已恢复。
- **房间规则与存档**　使用实际 Godot 无界面服务器和 WebSocket 客户端验证四人上限、房间隔离、移动速度、距离判定、缺少材料时的修复判定。两人同时拾取同一件物品，服务端只接受一次。关闭服务后重启，两名 GDScript 客户端均通过同一套网络代码重新接入，读回身份、位置、修棚状态和天气时钟。模拟 TCP 仍在但收不到快照时，客户端触发重连。[原始记录](../evidence/coop-rooms.json)
- **网页与 Mac 合作**　有窗口的 Chrome 从 Wi-Fi 地址连接，房主的 Mac 发行版通过 LaunchServices 启动并从回环地址连接。两边各看到一名队友，原生客户端给出的邀请仍是 Wi-Fi 地址。自动化驱动键鼠，网页玩家在房间第 26 秒到达溪谷、第 49 秒到达瞭望塔，第 88 秒已在修好的棚下避雨。驻营的 Mac 玩家同步看到了两件材料、修好的屋顶与满雨量。刷新网页后身份、位置与任务进度一致。切换应用时浏览器曾释放鼠标，重新点击「进入林地」即可继续。[溪谷](../evidence/coop-wood.png) · [瞭望塔](../evidence/coop-tarp.png) · [修好的庇护所](../evidence/coop-repair.png)
- **分块驻留**　地图由 7 份可独立获取的几何组成，纹理与低细节远景复用。本次跨端试玩在溪谷、塔边和回营三个采样点均驻留 3 区。另用同一地形脚本在无界面进程完成 12 次往返，采样时最多驻留 3 区。第 1 至 12 轮回营后均为 117 个节点、0 个孤儿节点，Godot 静态内存计数为 57,311,459 字节。浏览器进程和 GPU 的长期内存表现待测。[逐轮数据](../evidence/coop-streaming.json)
- **本机运行条件**　Apple M1、16 GB、macOS 26.5.2、Godot 4.7.2 标准版。网页版使用 Compatibility、WebGL 2 及 1280 × 720 绘图缓冲区。同一 Mac 上的两个客户端用于联机验收，跨物理设备 Wi‑Fi、手机触控和公网延迟仍待实际玩家验证。

## 代码入口

远景地表随游戏常驻，覆盖玩家视野内的地图边界。它与湖床共用高度规则，详细分块缺失时，树的远景轮廓仍和地表接在一起。分块在 26 米内按距离预取，34 米外卸载，详细分块最多驻留 4 个。只有新分块比最远的驻留分块近至少 3 米时才替换，以免在边界来回加载。[分块回归脚本](../scripts/coop-streaming-test.gd)

| 功能 | 文件 |
|---|---|
| 玩家视角、输入、队友、任务提示 | [client.gd](../coop/client.gd)、[hud.gd](../coop/hud.gd) |
| 权威房间、快照、原子存档 | [server.gd](../coop/server.gd) |
| 客户端预测、快照超时与重连 | [network.gd](../coop/network.gd) |
| 两端共用移动、碰撞、雨势规则 | [rules.gd](../coop/rules.gd) |
| 区域加载、预取与释放、建筑和物资 | [terrain.gd](../coop/terrain.gd)、[world.json](../coop/world.json) |
| 小径树种、位置、初始树龄和阶段模型 | [coop-grove.json](../shared/coop-grove.json)、[grove.gd](../coop/grove.gd) |
| 本地静态服务、gzip 和 WebSocket 入口 | [coop-serve.mjs](../scripts/coop-serve.mjs) |

`python3 scripts/coop-zones.py` 将试验林清单和固定的树干碰撞写入 `coop/world.json`。现有房间首次用新版服务器打开时，会以存档里的在线时长为成长起点，继续原本的天气与任务进度。更新后重启房间服务器，让两端读取同一份世界清单。

在同一条邀请地址下，HTTP 获取客户端和区域文件，WebSocket 的 `/room` 连接到本机 Godot 房间进程。Mac 也从房主服务按需读取区域。房主机器需保持在线。双方共用 GDScript 玩法。Steam 上架、Steam 好友邀请以及公网托管尚未接入。

## 个人物资与溪水

2026-11-19 修复背包资源与战斗输入：

- 溪水保持独立饮水资源，不作为食物参与同伴觅食或袭击者抢食。所有随身溪水归同一格；选中「喝一份」消耗 1 份、水分 +32，水分达到 96 时拒绝浪费消耗。原桌上固定水壶仍可就近喝水。
- 靠近木桌，背包中的溪水可「放桌上」：扣 1 份并生成真实可拾取水壶。桌面有六个位置；位置满时不扣物。看向它按 E 拾回同一堆，F 可直接喝这一份。联机拾取、饮用与保存失败均由权威端保证守恒。
- 木料、防水布同类各占一格，进入实际拾取者个人背包。初次修屋和后续在修屋点完整修复都消耗本人木料、防水布各 1 份；住民面板修补耐久 +25 同样消耗各 1 份。材料能丢到地上，由队友拾取。石块的原有实体持有规则保持。
- 溪谷木料、瞭望塔防水布每次提供 1 份余料，取走后随在线游戏时间 180 秒恢复，离线不推进。来源是否已取仅控制场景物资显示，不能抵扣修屋费用。
- 旧存档中尚未修屋而已取得的共享木布，各保留 1 份，迁移给第一个回来接管的既有玩家；早期只有位置记录的玩家也按稳定身份识别。满包时保留待领取记录，腾格后自动进入该玩家背包，背包会提示。迁移标记、归属与待领取数量保存，重启不复制。已修好屋顶不再补发已消耗材料。
- 移除 R 与独立战斗姿态。攻击随当前实际装备决定：徒手、圆石、木棍为钝击，长矛和磨利投石为锐器。1–4 装备、5 盾牌和右键防御保留；自然站立、行走、跛行、倒地动画保留。旧战斗模式字段加载时忽略。

定向验证运行：

```sh
/Users/sky/Downloads/Godot.app/Contents/MacOS/Godot --headless --path coop --script "$PWD/scripts/test-coop-resource-fix.gd" -- "$(mktemp -d)"
```

资源权威检查、Survival 回归与构建日志在 `evidence/resource-fix-20261119/`；独立双玩家网络、重启和普通背包鼠标验证在 `evidence/stream-water-fix-validation-20261119-sol/`。普通试玩发行包先完整构建至隔离目录，确认后切换 4284 服务的 `COOP_SITE_DIR`，不覆盖 4184 正在读取的 `dist/coop`。

本轮验收已通过：36 项资源权威与迁移断言；完整 Survival 和客户端反馈回归；原真实 WebSocket 联机回归的 18 项分类检查；独立 QA 的 28 项网络/重启检查、18 项正常键鼠背包操作和最终修字截图；Mac 最短真实入房。4、7、10 份溪水在满六格的实际背包里均只占最后一格，玩家喝水、桌上放水、队友拾回和木布丢拾均有截图。最终两端 PCK 相同，详见 `evidence/resource-fix-20261119/build-manifest.json` 和独立 QA 的 `final-smoke-report.json`。

普通服务更新于 21:49，`http://localhost:4284/coop/?room=pine` 健康检查 `ready=true`，HTTP 下载的 PCK 与最终包 SHA256 一致。保持同一 origin、房间和真实保存目录 `.local-rooms/wild-people`，用户刷新当前标签页即可继续。服务 Node PID 为 93107（重启后可能改变）；原 4184 PID 76294、原发行目录和存档均未动。停机前与 Godot 最终保存后的完整备份分别在 `.local-rooms/backups/resource-fix-20261119/before-stop` 与 `after-stop`，运行证据为 `evidence/resource-fix-20261119/live-release.json`。

2026-11-19 23:00 统一单格修复已部署普通 4284/4285：13 个注册背包物品共用每种一格规则，容量仍为 6/12 种，单种安全数量上限 2,147,483,647；旧存档保留同种总数，不改 item→数量结构。24 项聚合/边界/类别守恒断言、Survival 与 HUD 回归、独立 50 项真实网络与 21 项正常网页操作均通过。苹果和药草 4/7/10 的真实采集、吃/用/丢拾与刷新、重连、重启有证据：`evidence/inventory-single-stack-20261119/`、`evidence/inventory-single-stack-validation-20261119-sol/`。本次先交付单格版，人物新动作另行接入。


## 玩家动作

### 人形模型、第一人称腿脚与近战（2026-11-21）

陆地上低头可以看到自己的手、衣摆、膝盖和登山靴。脱掉长裤会露出模型原有的短裤和裸腿。按 **1** 选择徒手，再连续点左键，角色依次打出左直拳、右直拳和左摆拳。短暂停手后会收回防守姿势。**V** 可切换肩后视角，队友也能看到同一侧手的动作。持盾时保留左臂护盾，木棍、长矛和日本刀各自使用挥击、刺出和挥砍动作。 [动作实录](../evidence/human-motion-20261121/attacks.mp4) · [腿脚对照](../evidence/human-motion-20261121/legs-and-feet.jpg)

可编辑的玩家源文件为 `art/characters/sky_field_character.blend`，游戏读取 `coop/props/sky_character.glb`。用 `scripts/build-player-field-model.py` 从原步态工程重建雕形、皮肤纹理和近战轨道，脚掌固定的接触姿势由 `scripts/bake-human-attacks.py` 烘焙。房间共享出手时间、装备、连拳序号和俯仰角。`player_melee_pose.gd` 根据这些数据采样，在走动时沿用下半身步态。用以下命令输出候选资产、复验实际导入骨架。 [五套模型及动作清单](../evidence/human-motion-20261121/assets.json)

```sh
./scripts/start-blender.sh --background --factory-startup --python-exit-code 1 --python scripts/build-player-field-model.py -- .cache/human-motion
/Users/sky/Downloads/Godot.app/Contents/MacOS/Godot --headless --path coop --script "$PWD/scripts/test-coop-human-attacks.gd"
```

70 项近战与骨架检查通过，另外复验了 21 项玩家移动检查、46 项武器检查和四款来袭者的步态。两个浏览器分别作为出拳者和队友，记录到三次出手的动作与房间时间一致。Mac 发行版也已进入营地并加载场景。 [检查结果](../evidence/human-motion-20261121/checks.json) · [双端记录](../evidence/human-motion-20261121/browser.json) · [网页版出拳](../evidence/human-motion-20261121/web-punch.jpg) · [网页版低头看腿脚](../evidence/human-motion-20261121/web-first-person-feet.jpg)

### 步态、跳跃与游泳（2026-11-19）

第一人称跳跃时，镜头与本地人物共用当帧脚底高度。站姿、游姿和步行起伏使用相对眼高平滑。验证覆盖 30 与 60 FPS 下的起跳到落地，以及网页版平视、低头和肩后视角的连续画面。 [跳跃记录](../evidence/valley-and-portals-20261121/checks.json)

玩家继续使用原 `sky_character.glb` 骨架、头身、眼镜、帽子与服装。新增 `coop/animations/player_locomotion.tres` 的 Walk、Run、Takeoff、Air、Land、Swim、Tread 动作，源文件为 `art/characters/locomotion/player_locomotion.blend`。原 Stand/Sit 保留，外套仅修正袖子绑定权重以跟随划臂，网格与贴图不变。[步态对照](../evidence/player-locomotion/walk.png) · [跑动](../evidence/player-locomotion/run.png) · [起落](../evidence/player-locomotion/jump.png) · [划水与踩水](../evidence/player-locomotion/swim.png)。

`hiker.gd` 用一个手动更新的 AnimationPlayer 采样和混合动作，停止原八关节正弦循环；采样后仅叠加持物/盾牌臂，并让衣物、靴子、帽子跟随同一骨骼。步频取实际水平位移，不把跳跃高度或被墙挡住的输入当成走路。Walk 参考 1.46 m/s、Run 参考 3.56 m/s；原 WASD 的 3.6 m/s 速度和按键保持，不增加冲刺档或姿态选择。

起跳与落地由实际地面接触和垂直速度决定，跳跃顶点即使速度接近零也仍在空中。落地有约 0.22 秒恢复。已有地面接触者会跟随小幅下坡，避免沿缓坡反复触发离地/落地。游泳由实际水域和深度决定；移动或潜升时划水，静止时踩水漂浮。原先整个人物节点的水中转动和偏移已移除，水线由骨骼动作处理。水中手持物视觉暂时收起，不改变库存或装备，回岸恢复。背包人物保持自然站姿，驾驶座仍使用 Sit。

服务端在现有 y/vy/swimming 基础上共享 grounded、实际碰撞后 vx/vz、水中 waterVy；本地动画可使用移动预测，远端随共享状态和位置插值。开发观察为 CooperStatus.localPhysics 与 playerMotion（包含最近十二条动作切换），没有新增玩家操作入口。

短定向验证：

```sh
/Users/sky/Downloads/Godot.app/Contents/MacOS/Godot --headless --path coop --script "$PWD/scripts/test-coop-player-locomotion.gd"
```

实现证据在 `evidence/player-locomotion-20261119/`，独立双端验证在 `evidence/player-locomotion-validation-20261119-sol/`。着地检查使用变换后的实际鞋底顶点。新版登山靴以相同方式通过 16 项动作定向检查。

动作集成已通过 16 项真实物理与骨架定向检查、原 Survival 与角色/衣物/握持回归，以及独立 9 项运动物理、15 项双端交互。46 组连续关键帧覆盖自动 Walk/Run、松键/撞树停步、双方起跳/空中/落地、浅岸到深水、划水/停游、潜浮、返岸、重连与装备守恒。浏览器全程无界面运行，没有录像工具安装或性能打分。最初撞树路径因测试转向等待过短而绕行，已保留原件并仅补正确方向的撞停检查。

2026-11-19 23:27 普通 `http://localhost:4284/coop/?room=pine` 已换完整动作包并确认 `ready=true`，HTTP PCK 哈希与上述候选一致；刷新当前标签页即可使用。新后台 Node PID 60342、会话 91257，保存目录仍为 `.local-rooms/wild-people`。本次重启前与 Godot 最终保存后均有备份，位于 `.local-rooms/backups/player-locomotion-20261119/`；原 4184 PID 76294 与其 `dist/coop` 均保留。最新包证据见 `evidence/player-locomotion-20261119/live-release.json`。

同批 Mac 修复包保留在 `dist/coop-resource-fix-native/CooperCamp.app`，可加入相同普通营地：

```sh
open -n dist/coop-resource-fix-native/CooperCamp.app --args -- --room=pine --url=ws://127.0.0.1:4284/room --zone-base=http://127.0.0.1:4284/coop/zones/
```

最终固定路径的 Mac 发行版最短入房已通过，PCK 与网页同为 `7fe68e3ccd9779161ed9e8144f75e9b25d4378f7957b34656696b31d92d6b457`、46,857,572 字节；真实岸上 grounded/swimming、装备数量、WebSocket 和分块地址正确。最终记录为独立验证目录的 `mac-report.json`。发布时 staging 与备份目录原子互换，第一次 Mac 收尾误读旧包的原件已归档 `attempt-3-mac-staging-swap`；纠正固定路径后通过，未改代码或重复已过动作场景。
