# 营地近景、多层摆放与连续路线验收

## 多层摆放

Godot 房间回归使用两位玩家搭叠两层地板。队友把原营地木桌放上去，再摆一枚苹果。另一位玩家把铁矿石丢在桌旁。拆掉上层后，桌脚和散落矿石都落到下层，苹果随桌子下降。拿起桌子后苹果落到下层，另一位玩家收到相同坐标。故意让存档写入失败时，构件、背包和物品位置一起回滚。离房重进验证落点和接触关系，随后从下层拾回苹果。

建造 36 项、放置 26 项、仓储 63 项、采炼 16 项和生存回归通过。 [建造](native-construction.txt) · [放置](native-placement.txt) · [仓储](native-storage.txt) · [采炼](native-mining.txt) · [生存](native-survival.txt)

## 连续路线诊断

本次用锁屏 Apple M1、无窗口 Chrome 157、ANGLE Metal 和 1280 × 720 画布。鼠标锁定由测试页模拟，行走、挖矿、游泳和飞行沿用浏览器中的普通输入和房间服务。GL 追踪样本用于定位问题，正式前台硬件帧时仍需在解锁的显示器上测。

第一轮 5484 从营地走到煤矿，煤矿支线入口最长出现 1166.7 ms。铁矿入口能走通，脚步在铁矿壁前超过预定停点约一米。采样脚本改为分短步、停稳后再瞄准。另一轮 5484 揭示煤洞入路同一小段首绘链接了 27 个 GL 程序。 [第一轮](route-5484-first.json) · [旧包初步 GL 追踪](route-5484-trace-initial.json)

加入矿洞预热的隔离包从营地出发，步行进出两洞并实际按 F 采到煤和铁矿。继续下山、下潜、游到海岛顶，还用实装飞船跨越礁线。煤洞进入段测到 1 个新链接，岩脊段由旧包初轮 183–217 ms 的最大间隔降到该次 16.8 ms。铁矿出洞期最长 1533.3 ms，同一段时间四次 GL 程序参数查询合计约 1.216 秒。另有和链接不重合的长任务。隔离包 PCK 为 `ce68a66e2d2659f037d6783ac0e652738649f75be67f7fbcf611ad547fb3c05f`。 [预热候选完整路线与 GL 追踪](route-cave-prewarm-provisional.json)

带程序标签的第二次旧包追踪确认，进煤矿有 27 个新链接，其中 9 个为植被风动、叶面或远景树冠。记录包含这些程序的光照分支和相机坐标。第一次前台候选在林径转弯处擦树，记录保留 60 Hz 空白窗口和失败位置，后续转弯采用停稳的实际按键。 [旧包程序诊断](route-5484-program-diagnostic.json) · [前台首轮](route-foreground-first.json)

试制 5584 包 `0620e9d007f3c6a4f78494fc579fb9fd069e036071184c79ca3b5c1b83be306c` 在前台再次从营地走到两洞并采出煤铁。铁矿下坡走到 `(-72.079, -61.947)` 时脚点一度跌到 19.10 m，坡面接触接近 19.44 m。旧查询选中了重叠坡道段的短端面。现在遇到这种端面时，脚点改用附近同一坡道实际可走的最高顶面，正常的抬高步限和墙面碰撞继续生效。872 个固定点里原有 13 处丢失坡面，修后为 0，矿洞回归增加 10 项。 [前台触发记录](route-5584-foreground-before-ramp-fix.json) · [坡面查询前](before.txt) · [坡面查询后](after.txt) · [63 项矿洞回归](native-mines.txt)

最终 `78f29a540303441334314c841103c8aac0a2f4812a5ecba4c441f51da09ef39d` 在已解锁的 M1 前台用真实鼠标锁定完成全程。空白窗口实测 59.99 Hz。营地步行到两矿、凿煤铁、沿铁矿坡道下行、游泳下潜登岛、起飞和飞越礁线均通过功能检查。13 段平均为 56.25–60.0 FPS，P95 为 17.4–17.7 ms。7 段超过长帧门槛，最长为铁矿出洞 1283.5 ms。岩脊步行与礁线上空飞行均为 60.0 FPS，最长 17.8 ms。报告保留完整帧间隔和位置。 [前台全程报告](foreground-final/report.json) · [铁矿](foreground-final/iron_mine.jpg) · [凿煤](foreground-final/coal_mine.jpg) · [潜水](foreground-final/underwater.jpg) · [海岛](foreground-final/island.jpg) · [飞船](foreground-final/airship-bay.jpg)

## 网页采炼、建造和四人房间

整枝过渡修订前的隔离包 `830043180b4313b28c5fc8ab652335663cc2b2f8e92a2c960937605e24c0a6c2` 完成网页建造五项。实际按 **F** 凿矿、在背包丢下原矿并按 **E** 捡回，真实模型落点与服务器完全一致。营火添煤和炼铁取锭通过。 [建造](construction-review/report.json) · [采炼与两件拾取](mining-review/report.json) · [煤块落地](mining-review/coal-floor.jpg) · [铁矿落地](mining-review/iron_ore-floor.jpg)

同一隔离包用无窗口 Chrome 和三位通过真实 WebSocket 连接的队友验收。三位各发送 280 条标准移动消息，服务器记录移动范围 2.51–2.67 m。采样从来袭前开始，营地战斗时房间有四位玩家和八位存活 NPC。来袭阶段平均 58.77 FPS，最长间隔 116.7 ms。同屏阶段 57.40 FPS，最长 233.4 ms。住民面板打开时实际输入未引发攻击或走动。 [四人报告](four-player-review/report.json) · [来袭逐帧](four-player-review/raid-arrival-frames.json) · [同场逐帧](four-player-review/submitted-frames.json) · [实拍](four-player-review/four-player-camp-combat.png)

正式 5584 又用同样的四人配置复测。三个队友各发送 288 条移动消息，真实移动约 2.51 米，八位 NPC 同场。第一次来袭的 13 秒为 58.93 FPS，最长 166.6 ms。其后 10 秒同场为 60.0 FPS，最长 16.8 ms。整个过程无脚本或资源错误，面板输入回归通过。 [最终四人报告](four-player-final/report.json) · [来袭逐帧](four-player-final/raid-arrival-frames.json) · [同场逐帧](four-player-final/submitted-frames.json)

## 实机近景

最终包在无窗口 Chrome 157 和 Apple M1 Metal 上复拍云杉树下、木屋陶壶与角色界面。1280 × 720 下三处各记录 3 秒，均为 60.0 FPS，P95 为 16.7–16.8 ms。 [云杉](fixed-final/creek-spruce.jpg) · [陶壶](fixed-final/camp-glazed-jug.jpg) · [角色界面](fixed-final/equipment.jpg) · [定点报告](fixed-final/render-benchmark.json)

## 包内贴图

当前 265,852,716 字节 PCK 的实际文件表有 860 项。三件起始装备的 13 张贴图共 125,344,546 字节，五种容器的 15 张贴图共 44,608,702 字节。逐图核对使用贴图头的尺寸和 GLB 材质实际通道。 [最新版资源清单](release-assets.json) · [候选包逐图盘点与 A/B 办法](texture-inventory-5594.md)

收尾清理了三份本轮临时 PCK 和 WASM，共 914,520,294 字节。保留已发布的试玩包、房间存档和对照证据。
