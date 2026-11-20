# 阵风雨丝遮挡验收

固定机位使用 Godot 4.7.2、Apple M1 原生 Metal Compatibility、1280 × 720。保留相同的世界时间、场景几何和雨量，仅切换雨丝遮挡。另拍一张隐藏雨丝的参考，用于辨别实际雨丝像素。

- [修好营地、原木屋和两矿洞的同机位前后](sheltered-views.jpg)
- [移走屋顶、斜屋顶与矿洞外露天坡道的对照](roof-move-and-open-slopes.jpg)
- [原生机位与回归数据](render-report.json) · [原生复拍脚本](capture.gd)

新建木屋用套件中两面真实斜屋瓦的碰撞板，随房间权威快照更新位置、朝向与倾斜。携带、移走和拆除屋顶会更新原位置的雨。营地木板檐线和补布使用与现有模型吻合的矩形斜板，修好后生效。两矿洞用已贴合实际岩壁的厚石壳碰撞，入口保持敞开。从洞内朝洞口拍摄，煤洞与铁洞的洞口裁切区域仍分别辨出 250 和 249 个明显雨丝像素。露天坡道的遮挡开关对照一致。

雨丝从底端沿当前房间阵风的反方向求交，截去被阻挡的部分。包围盒来自地形和摆放数据中的遮挡几何。几何数据按相机附近的网格选择，每座矿洞实测最多 117 块，上传到约 8 KiB 的最近采样浮点贴图。遮挡在顶点阶段求交，露天无邻近屋顶时走零遮挡分支。晴天和水下的雨丝隐藏行为通过复测。

浏览器使用正式雨丝着色器、960 滴雨丝和煤矿实际 117 块石壳，在 Apple M1 的 Chrome WebGL 2 / ANGLE Metal 中单独渲染。分别有 0、117、117、0 块遮挡的数据各采 75 帧，中位帧间隔为 16.6–16.7 ms，各次 P95 为 18.3–19.2 ms。像素对照确认浏览器实际使用了浮点贴图，帧时仅代表独立雨丝夹具。 [浏览器画面](web-shader-proof.jpg) · [浏览器日志和计时](web-check.json) · [Godot 着色器取样函数](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shader_functions.html) · [WebGL 2 浮点纹理格式](https://registry.khronos.org/webgl/specs/latest/2.0/)

实际建造权威状态 19 项、矿洞几何和通行 52 项回归均通过。房间快照接线位于客户端更新天气之前，服务器及碰撞逻辑沿用现有实现。

从项目根目录运行原生复拍。需要导入好资源的 Godot 工程和现有地图分块。

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
  --path "$PWD/coop" --rendering-method gl_compatibility --audio-driver Dummy \
  --resolution 96x72 --quit-after 750 \
  --script "$PWD/evidence/rain-shelter-20261120/capture.gd" \
  -- /private/tmp/rainline-rain-shelter-capture "$PWD/dist/coop-atlas/zones"
```

轻量浏览器夹具从 [煤矿遮挡数据导出脚本](export-coal-shell.gd) 写入 `boxes.bin`。空的 Godot Compatibility 工程使用 [雨丝测试节点](web-fixture.gd) 和同一份 `rain_streaks.gdshader`，将数据文件随 Web 导出。页面的 `window.rainShadeQA` 保存帧间隔，`window.setRoofCount` 设为 0、117 或 -1 对应关闭遮挡、开启遮挡和仅保留背景。
