# 雨线营地长期画质与世界扩建

本文件记录当前进度、关键决定和验收证据。每次切换会话先读「当前进度」和「接下来做什么」。每完成一轮更新对应条目，保留改动路径、可复现的测试、截图和剩余问题。

## 目标

- 全面盘点实际进入游戏的模型。从玩家、装备、飞船、藏獒、动物、住民和来袭者开始，覆盖营地道具、建筑、矿洞和植被。用 GTA V 级写实开放世界的材质、光影、环境运动与近景可读性做质量参照，沿用雨线营地的原创美术和玩法。
- 细化雨量、风向和阵风。让树叶、草和枝条有对应运动，做出雨滴落在湖面、海面后的波纹与反光变化。增加形态与生境有区别的写实植物，检查近景、密集实例和远景接续。
- 检查野人模型比例、材质和各个姿态，包括站立、行走、转向、奔跑、坐卧、工作、交互和战斗。兼容时复用玩家骨架与动作，在实际玩法中检查关节、步态和持物贴合。
- 加入煤矿和铁矿矿洞。煤能添入火堆当燃料，也用于熔炼铁矿。地面采集物、矿石和加工产物都使用可看清的实际模型，并接入背包、储物、掉落、联机同步和存档。
- 增加以美国乡村木屋为参照的建造件，覆盖木屋墙面、屋顶、桌子、椅子。建造件及场景里的桌子和装饰品能预览、放置、移动和拆解。放置预览在有足够支撑且无穿插时显示绿色，否则显示红色。地形、楼面和物品表面都可作为候选支撑，放置结果以物件的脚点、接触面、碰撞和稳定性为准。

## 验收方法

1. 为营地木屋、人物近景、鹿鸣湖、海岸和飞行路线保留固定机位。在近期网页与 Mac 构建用相同镜头、距离、光照和分辨率做前后对照。
2. 每项资产记录来源、运行路径和当前问题。对照源 GLB、导出 GLB、游戏近景和实际动画。优先修复导出破坏的材质、网格和贴合。源件需要补建模时通过 Blender MCP 处理并保留可编辑源文件。详见 [游戏 3D 资产技能](../skills/game-3d-blender/SKILL.md)。
3. 测试雨和阵风时对比晴天、持续降雨、风向变化。检查近岸与外海、湖岸过渡、水中视角和帧时。使用 [画面与帧时基准](render-benchmark.md) 记录目标设备上的变化。
4. 煤铁、储物和建造先跑完整的同一房间循环。核对拾取、制作消耗、预览与服务端放置验证、队友移动、拆解返还、失败回滚、离房重连和旧存档加载。
5. 按盘点、优化、对照、回归测试反复推进。并行工作先明确文件范围，合并各路修改前复查统一入口和存档格式。把阶段成果写回本文件。

## 当前进度

2026-11-20，装备和飞船先行。夹克源模型的拉链与胸袋完整，旧运行 GLB 在 Blender 和 Godot 中都有同样的大片折面。已调整减面与贴体顺序，保留 UV、平滑法线与 1024 像素材质。登山靴使用用户提供的左右靴 GLB，沿用脚骨并重算踩地接触。羽饰头盔使用用户提供的 GLB，木屋地面每个房间生成一顶，拾取并穿戴时与帽子互换。靴子和头盔原色贴图已从自发光接到材质底色，核对了明暗两种环境及样稿转身。飞船颜色和法线贴图恢复至 2048 像素，启用各向异性过滤，模型仍为 89,988 个三角面。

- 已通过 Godot 16 项动作检查、装备和动物画面回归及房间生存回归。房间测试覆盖头盔首次生成、同时拾取、换戴、落地、队友拾取和重载不重复生成。网页试玩用真实 G 键拾取头盔，经背包换戴帽子并核对数量。角色样稿通过高清模式旋转与穿戴测试。
- 装备和飞船的独立试玩保留在 `http://127.0.0.1:4984/coop/?room=pine`。发行目录 `dist/coop-wearables-preview`，独立房间存档 `.local-rooms/wearables-preview`。角色样稿为 `dist/ui-mockup/rainline-wardrobe.html`。 [角色实装对照](../evidence/camp-ui/wearables-detail.jpg) · [飞船同机位对照](../evidence/airship-hull-detail.jpg)
- 本轮源资产和验证入口见 [合作样片](coop.md#木屋里的桌子与补给)。资产修改验收工作流已同步到 [游戏 3D 资产技能](../skills/game-3d-blender/SKILL.md)。
- 首批固定机位已留档。Apple M1 上无窗口 Chrome/Metal 以 1280 × 720 运行装备飞船初版。林地、湖岸、装备、水下和暴雨各采两秒，均为 60.0 FPS，P95 为 16.7–16.8 ms。记录早于新装备的受光修正。正式帧时验收按项目手册在前台另跑。 [基线数据和截图](../evidence/world-upgrade-baseline-20261120/)
- 第一轮清单覆盖 67 个包内 GLB、7 个动态分块以及运行时生成的植被和地表。野人原模型有可复用的 23 根同名骨骼。先修实际移动和踩地，老鹰尸体的姿势缺失另外跟进。 [模型清单与机位](../evidence/world-asset-audit-20261120/README.md)

### 建造与第一轮环境试玩

- 本机试玩 `http://127.0.0.1:5084/coop/?room=pine` 使用 `dist/coop-construction-preview` 与独立房间存档 `.local-rooms/construction-preview`。网页已用真实 K、G、左键、Shift 和 W 走通地板、门框、三面墙、屋顶、进门和走上抬高地板。照片保留了绿色预览、缺支撑的红色预览和拼装后的实际画面。 [网页验收](../evidence/construction-web-20261120/report.json)
- 美国乡村原木套件含地板、横纹原木墙、1.04 × 2.05 米真门洞、双坡木瓦屋顶。保留可编辑源件，导出并用 Godot 实际模型通过 26 项几何和支撑检查。放置规则独立通过 26 项，房间流程通过 19 项，涵盖初始木桌、桌上装饰、桌面支撑、失败不扣材料、同房间一致和存档重载。 [木屋源件](../art/cabin_kit.blend) · [模型合装图](../evidence/cabin-kit-20261120/assembly.jpg) · [房间回归](../scripts/test-coop-construction.gd)
- 藏獒肩髋之间从 39.5 cm 延至 49.5 cm，贴图与九段动作的时长、循环保持一致。Godot 比较了每版 260 个采样相位，四脚脚底最大高度变化 2.19 mm。双客户端通过收养、跟随与重进房间。 [藏獒对照与验证](../evidence/mastiff-fit-20261120/README.md)
- 湖面和海面随同一房间雨量显现雨滴扩散环和反射变化。相同机位对照保留晴天海面，原生 Metal 六组固定机位验证湖岸、海面、水下的晴雨过渡。草与白桦共用房间阵风。白桦树干和叶片同向弯，叶片叠加短时振动。 [湖雨](../evidence/water-rain-20261120/fixed-lake.jpg) · [海雨](../evidence/water-rain-20261120/fixed-coast.jpg) · [风动影像](../evidence/woodland-wind-20261120/camp-gust.webp)

### 西岸矿洞与第二轮环境试玩

- 合并试玩使用 `dist/coop-mining-preview`、网页 / 房间端口 5184 / 5185、独立存档 `.local-rooms/mining-preview`。包含装备、飞船、藏獒、木屋、煤铁流程、第二批风动与野人步态。2026-11-20 17:02 的 Web PCK SHA256 为 `63744090c50844a8e278cbae22cdafbef941185a32ad5ff5cbe606b65d2c6f7f`。 [雨线营地试玩](http://127.0.0.1:5184/coop/?room=pine)
- 煤、铁矿都从西岸山径接入。两座矿洞含岩层、通透入口、引道、木梁、油灯和可采矿脉。真实模型与碰撞通过 52 项检查，两条路线在 30 和 60 Hz 下都能直接步行，侧壁、后壁和顶梁能挡住角色。煤矿入口世界 XZ 为 `(-74.25,-31.35)`，铁矿为 `(-74.25,-66.55)`。 [矿洞可编辑源](../art/mines/rainline_mines.blend) · [洞体与通行报告](../evidence/mines-20261120/godot-checks.json)
- 瞄准矿脉按 **F**，库存随房间共享并按房间时间露出新矿。煤块可在营火中添燃，营地石砌炉将两块铁矿石和一块煤炼成一块铁锭。煤块、矿石、铁锭都可进背包、进容器、放在桌上和落地。16 项房间检查覆盖共享库存、取矿与存档失败回滚、燃料、在炼批次重连、队友取锭和重复领取阻止。网页完整开采到取锭的操作通过，另用双 WebSocket 跑通原进营路线、多人同步和重启。 [房间回归](../scripts/test-coop-mining.gd) · [网页采矿和炼铁报告](../evidence/mining-web-20261120/report.json) · [炉子可编辑源](../art/iron_furnace.blend) · [玩法说明](camp-storage.md#煤铁与炼铁炉)
- 草和原先烘焙进地图的蕨丛现在按地板占地遮挡，地板移走时会恢复。木屋合装、走入、走出已在同一合包复拍。 [屋外实机](../evidence/construction-web-20261120/cabin-exterior.jpg) · [摆放操作](../evidence/construction-web-20261120/report.json)
- 松、云杉、海岸蕨类和雨丝已接入房间阵风，新增 26 丛滨麦用于干沙带。原生 Metal 固定机位验证树的近远交接和转动相机时雨向恒定。海岸灌木分发避开矿洞通道。 [海岸风与滨麦实拍](../evidence/coastal-wind-dunegrass-20261120/README.md)
- 四套 NPC 复用玩家骨架的走、跑姿态，保留独立左右跛行和持物点，新增踩脚转向。两套代表模型的行走支撑脚横滑由约 1.35 m/s 降至 0.017–0.031 m/s。四套 14 段动作已复拍。两客户端循环取得 53 组相同快照，覆盖走跑及跛行速度同步。 [步态对照](../evidence/wild-people-stride-20261120/stride-comparison.jpg) · [转身对照](../evidence/wild-people-stride-20261120/turn-comparison.jpg)
- 这一轮清单累计盘到 82 个包内 GLB、7 个流送分块，均有引用，依赖路径扫描通过。 [矿洞版资产清单](../evidence/world-asset-audit-20261120/after-western-mines.json)
- 合包用 Apple M1 的无窗口 Chrome/Metal 以 1280 × 720 各采 2 秒。林地、雨湖、雨海、水下和暴雨五个固定机位均为 60.0 FPS，P95 帧间隔 16.7–16.8 ms。前台真机的长路线、多人和密集场景另做压力验收。 [固定机位与逐帧数据](../evidence/world-stage-web-20261120/render-benchmark.json)

### 室内挡雨、近景材质与原地救援试玩

- 救援版保留在 `dist/coop-recovery-preview` 与独立房间存档 `.local-rooms/recovery-preview`，网页和房间端口为 5284 和 5285。2026-11-20 17:36 导出的 Web PCK SHA256 为 `9c31aff4c1ed6ab1de1097bc2c33fe30dfa953f5d7543c55b8b03ff9bc2f7812`，包含此前发布的矿洞、炼铁、木屋建造和林地天气。 [打开救援版](http://127.0.0.1:5284/coop/?room=pine)
- 单人倒地立即回营。联机时队友靠近并对准倒地玩家可按 **E**，在 15 秒内救起后原地站起，保留背包。超时或房间只剩倒地玩家时回营。房间会拦截隔墙、超距和重复请求。实际网页按键及存档验证通过，线上超时快照在 15.066 秒收到。房间 68 项和仓储 63 项通过。玩家倒地与起身的导出检查覆盖原角色骨架、衣物和靴子，21 项通过。 [救援画面](../evidence/player-rescue-20261120/down-and-rescue-prompt.jpg) · [起身画面](../evidence/player-rescue-20261120/getting-up.jpg) · [网页验收](../evidence/player-rescue-20261120/web-report.json) · [房间记录](../evidence/player-rescue-20261120/room-logic.json)
- 老鹰在枝头、空中和水上采用对应的坠落过程，落定后可搜取。湖上坠落的尸体会漂向岸边可到达处。鳄鱼和藏獒补了实际侧倒后的姿态。既有尸体存档可直接显示落定姿势。四套 NPC 补取水与采果，库存和动作进程在同一房间共享。代表模型的工作动作脚底偏差小于 4 mm。 [老鹰坠落与双人回归](../evidence/eagle-collapse-20261120/README.md) · [鳄鱼倒地](../evidence/animal-collapse-20261120/crocodile.jpg) · [藏獒倒地](../evidence/animal-collapse-20261120/mastiff.jpg) · [NPC 工作](../evidence/wild-people-work-20261120/README.md)
- 修好的营地木屋、可搬动的双坡屋顶和煤铁矿洞能挡雨。屋檐外与洞口外的雨丝仍可见，移走屋顶后原地恢复降雨。泥路和岩石根据表面粗糙度呈现不同的湿痕，雨停后按房间时间逐渐干燥。 [屋内与洞内同机位对照](../evidence/rain-shelter-20261120/sheltered-views.jpg) · [移走屋顶](../evidence/rain-shelter-20261120/roof-move-and-open-slopes.jpg) · [湿地与干燥对照](../evidence/wet-ground-20261120/README.md)
- 用 Blender MCP 重做炼铁炉各石面 UV，保持原 2K 贴图和石砌炉轮廓。炉石顶部的纹理拉伸中位数由约 36.69 降至 1.32。铁矿脉有更紧贴岩面的碎层轮廓，采矿位置保持一致。实际网页重新走通两矿开采、营火添煤及炼铁取锭，采集近景发现铁矿脉表面还需要修整。 [炼铁炉前后](../evidence/furnace-uv-20261120/furnace-uv-before-after.jpg) · [铁矿脉前后](../evidence/iron-vein-fit-20261120/iron-vein-ab.jpg) · [采集实拍](../evidence/recovery-stage-web-20261120/iron-seam-interaction.jpg) · [网页采矿与炼铁报告](../evidence/recovery-stage-web-20261120/mining-report.json)
- 新增 10 丛毛榛和 20 丛水葱，分别贴合鹿鸣湖干地林缘和浅水，枝叶随同房间阵风移动。已复拍叶脉、果苞、圆秆与水下视角，验证步行和栈台通行。 [湖岸植物实拍](../evidence/lake-margin-plants-20261120/README.md)
- Apple M1 上用无窗口 Chrome/Metal 以 1280 × 720 各采 2 秒。林地、雨湖、雨海、水下和暴雨五个机位均为 60.0 FPS，P95 帧间隔为 16.7–16.8 ms，最长为 16.8 ms。正式压力验收需要前台长路线、密集植被和多人同时活动。此次在雨海机位发现贴水岩壁仍有条状纹理拉伸。 [网页帧时](../evidence/recovery-stage-web-20261120/render-benchmark.json) · [雨海岩壁机位](../evidence/recovery-stage-web-20261120/current-coast-water-rain.png)

### 雨丝、岩壁、家具与同伴脚点

- 风雨版试玩保留在 `dist/coop-weather-preview` 与独立房间存档 `.local-rooms/weather-preview`，网页和房间端口为 5384 和 5385。最终 Web PCK SHA256 为 `b8a1fd9674bd66bc5a3f5c412189e5d5245044c3c4d7c8f1b147e50bfe90b053`。 [打开风雨与建造试玩](http://127.0.0.1:5384/coop/?room=pine)
- 雨滴落点由世界坐标和房间时钟决定，每滴在所在位置采样草木共用的阵风。近处渐隐，雨丝宽窄不一，末端带透明过渡。固定镜头和时刻、只移动雨区约 0.66 米时，可辨的 767 个雨丝像素有 764 个继续出现在原处。露天林地雨丝高对比像素从 1,811 降至 286。两座矿洞、修好的营地、原木屋及移动和倾斜屋顶的挡雨已重拍。 [雨丝与遮挡实拍](../evidence/world-rain-20261120/README.md)
- 海边局部陡岩在降雨机位出现横向拉丝。实测岩面朝 X，旧投影几乎用的是 Z 方向。改成按三角面方向选择投影并约束陡面铺砂。保持原地形和通行，岩纹恢复。晴天沙地机位的对照区域通道变化最大为 1/255。 [海岸同机位](../evidence/coastal-cliff-projection-20261120/fixed-coast-rain.jpg) · [投影诊断](../evidence/coastal-cliff-projection-20261120/analysis.json)
- 通过 Blender MCP 重新铺铁矿脉 UV 并细化 2K 颜色、法线和 1K 粗糙度。矿粒和锈斑在采集距离可辨，UV 拉伸第 95 百分位由 97.44 倍降到 1.37 倍。2,930 个三角面坐标与朝向一致，矿洞 52 项及采矿炼铁 16 项通过。5384 网页用真实按键完成煤铁采集、营火添煤和炼铁取锭。 [矿脉近景对照](../evidence/iron-vein-grain-20261120/mining-camera-ab.jpg) · [网页采集实拍](../evidence/world-weather-web-20261120/iron-mine.jpg) · [网页采炼验收](../evidence/world-weather-web-20261120/mining-web.json)
- 木桌和木椅通过 Blender MCP 补端面年轮，并用现有松木贴图给每块木板单独铺木纹。桌面刻字保留，椅座和靠背边缘加了约 1 mm 的圆角。Godot 实际导入、斜面摆放与桌上小物接触检查 39 项通过，建造和仓储回归 19 项及 63 项通过。桌面 0.790 米、椅座 0.455 米的接触高度保持一致。 [木桌近景](../evidence/furniture-finish-20261120/camp-table-detail.jpg) · [木椅近景](../evidence/furniture-finish-20261120/wood-chair-detail.jpg) · [实际摆放报告](../evidence/furniture-finish-20261120/godot-placement.json)
- 同伴和藏獒按各房间的落地构件绕障，能通过真门框，踏上 18 cm 的木地板。墙、箱子和桌子可挡路，拿走地板后首个快照恢复实际地面高度。真实斜板接触和旧狗存档加载通过。34 项房间与视图检查通过。两房顺序测试在缓存绕行路径和地板面后，服务端 P95 从首个候选的 7.83–9.32 ms 降至 1.79–2.65 ms。 [路径和帧时](../evidence/companion-navigation-20261120/README.md) · [双房间验收脚本](../scripts/test-coop-room-navigation-fit.gd)
- 首轮网页煤矿机位出现 116.6 ms 长帧。跳过镜头后方雨滴的遮挡运算，缩小遮挡数据的收集范围。最终网页在 Apple M1 无窗口 Chrome/Metal 以 1280 × 720 各采 5 秒，雨湖、雨海、煤矿和水下为 60.0 FPS，暴雨林地和营地屋内为 59.8 FPS。六处 P95 为 16.7–16.8 ms，最长 33.3 ms，煤矿最长 16.8 ms。实际 WebSocket 双客户端、重连和房间持久化回归通过。 [最终逐帧报告](../evidence/world-weather-web-20261120/fixed-camera-final.json) · [首轮煤矿数据](../evidence/world-weather-web-20261120/first-cave-and-dive.json) · [房间回归](../evidence/world-weather-web-20261120/loopback.json)
- 救援版的源码复查记录含 82 个包内 GLB、7 个流送分块以及玩家的两套动作库，引用和纹理依赖扫描均通过。后续使用同一清单核对新增和改过的资产。 [源码资产清单](../evidence/world-asset-audit-20261120/after-recovery.json)

### 全模型机位、溪岸木屋和燃烧细节

- 本机合并包使用 `dist/coop-cabin-preview` 和独立房间存档 `.local-rooms/cabin-preview`。网页和房间端口为 5484 与 5485。最终 Web PCK SHA256 为 `3a368015c1eb97f3c6a2428bd01afedbeb55897828d9d56b490cb675c07b111f`。 [本机试玩](http://127.0.0.1:5484/coop/?room=pine)
- 原生 Godot 用实际导入器拍出 83 个运行 GLB 的两侧定点图，并通过流送加载代码拍到全部 7 个分块。每份截图带资产散列、取景、尺寸和姿势，初审发现营火、矿灯、夹克肩袖、陶壶与原矿小块、云杉近景等仍值得继续修。 [模型审阅页](../evidence/model-review-20261120/README.md)
- 溪岸新增 5 丛成株和 9 丛幼株荚果蕨。有深裂羽片、浅色叶背、深褐色能育叶、根冠和远模。真地表复验 128 项通过，覆盖旧水葱和毛榛、水下受光、栈桥和涉水线路。 [溪岸前后](../evidence/creek-ostrich-fern-20261120/creek-fixed-before-after.jpg) · [形态与导入](../evidence/creek-ostrich-fern-20261120/README.md)
- 木屋墙面、门框、地板和屋檐重新布置木纹及梁端细节。四件构件逐三角坐标、朝向和支撑数据相同，建造 26 项通过。六张木材贴图维持原尺寸，导入体积合计增加约 1.46 MB。 [室内及檐口对照](../evidence/cabin-loggrain-20261120/same-camera.jpg) · [建造检查](../evidence/cabin-loggrain-20261120/godot-cabin-kit.json)
- 煤铁矿共八盏约 28 cm 的矿灯复用营地油灯的玻璃、灯芯和提环，保留两个矿洞原有的挂点。洞口的橘色溢光减弱，深处八个固定路面样点照度维持或提高。导入、通行与采炼 52、16 及灯具实例 8 项通过。 [煤矿对照](../evidence/mine-lamps-20261120/coal_mine-same-camera.jpg) · [铁矿对照](../evidence/mine-lamps-20261120/iron_mine-same-camera.jpg) · [路面照度](../evidence/mine-lamps-20261120/route-pixel-luminance.json)
- 湖和海的雨纹按局部法线、倒影与折射变化，落点大小、速度和倾斜有变化。近水面醒目亮纹减少，远处逐步融入原浪。98 项原生检查覆盖 15 个机位和时刻，包括晴天投石与水下。 [雨湖雨海前后](../evidence/water-ripple-reflections-20261120/lake-and-sea-fixed.jpg) · [水面验证](../evidence/water-ripple-reflections-20261120/README.md)
- 营火接入有细边的火舌、火星、带阵风偏移的烟和随燃料渐弱的火光。放置时在土面清出火圈周围的小块植被，移除后恢复。雨天、夜间和熄灭定点通过 14 项原生检查，仓储回归 63 项通过。 [暴雨及夜晚对照](../evidence/campfire-motion-20261120/rain-and-night.jpg) · [清出火圈](../evidence/campfire-motion-20261120/ground-clearance.jpg) · [营火验收](../evidence/campfire-motion-20261120/README.md)
- 静态寻路在监听前共用一次基础地形扫描，各自保留藏獒和 NPC 的净空。175,421 个网格与原版一致。双客户端同输入对照中，首个在线模拟步由 447.9 ms 降至 16.1 ms，藏獒首次路径所在步由 436.9 ms 降至 3.15 ms。服务到就绪多用 0.24–0.43 秒。两房布局、路径与旧存档通过。 [联机冷启动与逐帧数据](../evidence/cold-navigation-20261120/README.md)
- 5484 网页实际建造五项、采炼四项通过。检查绿红预览、材料扣除、进门和 18 cm 板高，采两洞、添燃和炼铁取锭。Apple M1 无窗口 Chrome 七处各采 5 秒，P95 为 16.7–16.8 ms，首轮营火和雨海最大帧间隔分别为 200 和 133.3 ms。两处在同包同机位单独复采都是 60 FPS，最大都是 16.8 ms。 [新版网页验收与两轮数据](../evidence/world-cabin-web-20261120/README.md)

### 夹克贴合、拾取模型和多层支撑

- 本机合包为 `dist/coop-detail-preview`。网页和房间端口为 5584 与 5585，使用独立存档 `.local-rooms/detail-preview`，分块目录链接到 `dist/coop-streamed-crown-20261120/zones`。PCK SHA256 为 `78f29a540303441334314c841103c8aac0a2f4812a5ecba4c441f51da09ef39d`。84 个包内 GLB 和 7 个流送分块的引用、大小与依赖均通过。 [本机试玩](http://127.0.0.1:5584/coop/?room=pine) · [包和分块清单](../evidence/world-detail-web-20261120/release-assets.json)
- 肩肘夹克修形和穿戴层已接入正式素材。修背衬与裤腰时保留原外套轮廓、肩片材质和裤子资源。叠穿使用共享的裤腰网格，脱下后还原。重新导入通过 13 项穿戴行为、9 种采样姿势和 21 项玩家动作。伸臂游泳的肩部拉伸继续跟进。 [同机位明暗和衣缝](../evidence/camp-jacket-fit-20261120/final-seams.jpg) · [动作和重建](../evidence/camp-jacket-fit-20261120/README.md)
- 陶壶补釉面、拉坯纹、脚圈和把手连根，保留桌面、底边和水面。煤块、铁矿块各保留 396 个三角与原模型边界，分别改为连贯薄层与带氧化斑的矿粒，各使用一套材质。生产导入和真实模型尺寸复核通过。 [陶壶近景](../evidence/camp-water-jug-20261120/same-camera.jpg) · [煤块](../evidence/mineral-pickups-20261120/coal-same-camera.jpg) · [铁矿石](../evidence/mineral-pickups-20261120/iron_ore-same-camera.jpg) · [重建方法](generated-3d-assets.md#煤块与铁矿拾取件)
- 多层支撑让桌面存放物随桌子落稳，拆除桌面时会沿当前模型查询落在下一层地板或地面。背包掉落也使用这套查询。联机存档记录新的支撑关系，验过失败回滚和重连拾取。建造 36 项、放置 26 项、仓储 63 项、采炼 16 项及生存回归通过。 [多层摆放和房间验收](../evidence/world-detail-web-20261120/README.md#多层摆放)
- 鹿鸣溪上游一株原地针叶树改成细分小枝组，保留树干与 0.268 m 的碰撞。18–23 米从近档逐枝交接，实拍 20.5 米中点的抽查区域新增天空像素为 0。近景和过渡复拍 15 项、相邻分块加载与重载 25 项通过。树龄系统和其他林地继续用原来的分块。 [树下近景](../evidence/streamed-crown-pilot-20261120/beneath-the-boughs.jpg) · [近远交接](../evidence/streamed-crown-pilot-20261120/whole-branch-transition.jpg) · [实际分块](../evidence/streamed-crown-pilot-20261120/README.md)
- 从真实输入走两洞、海滩、礁线、下潜到外岛，并用现有飞船飞过礁线。矿洞部分预热减少了首次进去时的 GL 链接，铁矿出洞仍会出现集中链接。通过着色程序名称核对，部分新建分支来自洞灯影响坡外的植被与散石，洞灯现已为这两类背景关闭。仍需同条件统计最长帧和建立首次进房开销的基准。 [阶段路线与帧时](../evidence/world-detail-web-20261120/README.md#连续路线诊断)
- 前台发现铁矿下坡一处身体会跌到坡面下。新脚点判断会在重叠的坡道端面和顶面之间选取可站立的顶面。872 个实测点原来有 13 处丢失坡面，修后为 0，矿洞共 63 项通过。 [坡道诊断](../evidence/world-detail-web-20261120/README.md#连续路线诊断) · [矿洞回归](../evidence/world-detail-web-20261120/native-mines.txt)
- 修后前台长路线共 13 段。真实键鼠和联机房间完成步行开采两矿、下潜登岛及驾船越过礁线，功能检查全部通过。平均帧率为 56.25–60.0 FPS，7 段超过长帧门槛，最长在铁矿出洞，为 1283.5 ms。 [前台逐帧报告](../evidence/world-detail-web-20261120/foreground-final/report.json)
- 5584 用无窗口 Chrome 和三位真实 WebSocket 队友确认四人在线，三位队友各实际移动约 2.51 m，营地有八位存活 NPC。来袭的 13 秒平均 58.93 FPS，最长 166.6 ms，后续同场 10 秒 60.0 FPS、最长 16.8 ms。 [四人房间逐帧](../evidence/world-detail-web-20261120/four-player-final/report.json)
- 查了当前 PCK 的实际文件表，约 253.5 MiB 中有 119.5 MiB 来自三件开局装备的贴图，42.5 MiB 来自五种容器贴图。首屏已经看得见部分装备和容器。优先试改善压缩或延迟启用全尺寸贴图，用同机位验证画质及加载耗时。 [包内体积分布](../evidence/world-detail-web-20261120/release-assets.json)

## 木屋和矿洞的首轮方案

- 木屋以美国阿巴拉契亚乡间木屋为参照。首组构件取水平原木和外露转角、石墩、坡屋顶与木瓦这些能从近景辨认的特征。桌椅、装饰和建筑件共用支撑与摆放规则。 [美国国家公园管理局 Junglebrook 农舍报告](https://irma.nps.gov/DataStore/Reference/Profile/2271863) · [美国国会图书馆 Henry Whitehead 木屋调查](https://tile.loc.gov/storage-services/master/pnp/habshaer/tn/tn0000/tn0004/data/tn0004data.pdf)
- 矿洞先检查从营地通往海岸的支线入口，评估崖沿步道可达性、船位、野生动物路线和旧地形分块。客户端和服务器目前通过共享高度图查询地面。第一对洞体优先验证横向可进入的坑道、可踩的洞底和连续碰撞，再确定更深层洞体的数据表示。 [海岸地图与共享地形](coast.md)

## 接下来做什么

1. 用 NPC 真正可见的靴底校准步态。两套高级造型的隔离检查发现裤靴下还有旧脚部和凉鞋。去除重叠样件后，动作、落地高度和持物点保持，按外靴底统计仍可看到原步态滑动。下轮一起复核走路、坐卧、持物、上下板和爬坡，再验网页四人房间。玩家夹克的游泳伸臂也留在动作矩阵里检查。 [高级款外靴与步态对照](../evidence/wild-people-elite-fit-20261120/README.md)
2. 先以一张开局装备的全尺寸底色做压缩与加载对照。测试相同分辨率、相同镜位的纹理和实际首开时间。将前台路线与四人压力测试里的长帧同 GL 程序、纹理载入及资源预热逐一对应。
3. 按针叶树试点的方法继续修林缘和岩坡可见树冠，海边、林下和矿洞外增加适宜植物。复查矿洞木梁转角、散石轮廓和近景接地，结合同机位和长路线继续对齐 GTA V 级写实环境细节。
4. 复验斜屋面、组合支撑和多层结构中的桌椅、容器、摆件。扩大到真实多人互相搬放，同时关注对象过高、位于狭缝或无法稳定落下时的恢复。
