# 野外图册

进入游戏后按 **M** 打开野外图册，用 **M**、**Esc** 或「关闭」返回。用滚轮围绕鼠标指向的位置缩放，也可以点 **+**、**−** 或使用对应键。左键拖动浏览，「定位我」把当前缩放视图移回玩家。放大和缩小各有独立制作的短促电子音。[当前试玩](http://127.0.0.1:5684/coop/?room=pine)

图册共有十二处地标。西侧包括营地木屋、鹿鸣湖、海湾崖顶、海湾沙滩、乐山大佛、外海小岛和瞭望塔。东侧包括根影林径、林坡煤矿、箭袋树花谷、层岩铁矿和层岩台地。点击地标可传送到附近的安全落脚点。选择「外海小岛」可隔水远眺大佛，选择「乐山大佛」可到佛脚前的石滩。倒地后需先恢复行动，驾驶飞船时需先停稳。房间服务器检查落脚点和船体、其他玩家的位置，再写入玩家位置存档。[实际图册](../evidence/leshan-coast/map.png)

青色方向箭头表示自己，带数字的圆点表示队友的房间编号。队友位置随联机更新，离线后圆点消失。右键地图任意位置可放个人标记，也可点「放置标记」再左键选点。点击已有个人标记可删除。同房间、同一玩家身份刷新后保留最多 32 个个人标记。

## 实现与复验

地图底图从现有高度格、鹿鸣湖、溪水、树木与步道生成，和角色使用同一世界坐标。地图打开时只绘制二维界面，房间时钟、角色和队友同步继续运行。[地图生成](../scripts/build-coop-atlas.py) · [地标及边界](../coop/field_atlas.gd) · [缩放音效生成](../scripts/build-camp-audio.py)

图册已并入当前试玩。需要复验候选版时，用当前源码构建网页包，在 4794 / 4795 启动独立服务。

```sh
npm run coop:build:web
COOP_PORT=4794 COOP_ROOM_PORT=4795 COOP_SAVE_DIR=.cache/field-atlas/qa-rooms npm run coop
```

双客户端 Chrome 前台测试通过六处传送、实时队友、私人标记刷新与删除、缩放和音效触发。Apple M1 的 1280 × 720 缩放及拖动采样 4.1 秒，平均 60.0 FPS，P95 帧间隔 18.6 ms，最大 18.8 ms。也验证了两名玩家同时到访时使用不同的落脚点、存档失败时撤回传送、Mac 发行版读取小岛位置入房。[前台报告](../evidence/field-atlas-20261120/foreground/report.json) · [地图截图](../evidence/field-atlas-20261120/foreground/atlas.png) · [房间规则验证](../evidence/field-atlas-20261120/protocol.json) · [Mac 入房](../evidence/field-atlas-20261120/native.json)

用 Chrome 音频节点采样了实际输出，本机和普通 HTTP 两条播放路径都在滚轮放大、缩小时输出短音，地图静止时输出为零。[缩放声音输出](../evidence/field-atlas-20261120/audio.json)

启动试玩服务后可复验 Chrome 操作流程。

```sh
COOP_ATLAS_FOREGROUND=1 node scripts/coop-atlas-playtest.mjs
```
