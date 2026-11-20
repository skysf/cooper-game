# 营地泥路与岩石受湿

载入原来的营地与林径分块，在 Apple M1、Godot 4.7.2 Metal Compatibility 中以 1280 × 720 复拍。泥路镜头离地 0.47 米，岩石镜头离地 0.82 米。同机位对照分别锁定晴天光照与暴雨光照。此轮只测陆地材质。

- [湿泥路和暴雨岩石前后对照](wet-ground-comparison.jpg) · [近景亮部细节](storm-highlight-detail.jpg)
- [雨停后的泥路](drying-trail.jpg) · [材质参数、机位与逐像素数据](render-report.json)
- [WebGL 2 材质成本复测](web-check.json) · [原生复拍脚本](capture.gd)

原材质在满雨时给泥路与岩石统一乘以 0.80 的底色系数。此时，泥路粗糙度系数由 0.85 调到 0.34，岩石由 0.72 调到 0.46。雨量回零时两者同时回到干态。

新材质沿用泥路与岩石原来的底色、法线和 ARM 贴图。用实际贴图的遮蔽与粗糙度信息在世界坐标里给湿斑定形。平缓凹处受湿更深，陡处的湿反光收敛得更多。湿态多取样一次现有的 ARM 贴图，沿用原有贴图包。晴天泥路机位逐像素一致，岩石机位全图仅 7 个像素有变化，单通道最大差 4/255。暴雨岩石低机位的下方 320 像素高区域，三通道均至少 240/255 的近白像素由 3,981 降到 0，裂纹、斑驳和较柔和的湿反光仍在。

湿膜随房间实时雨量变化，泥与石的残湿按同一房间时钟衰减。雨停时残湿为 0.317，9 秒后 0.132，24 秒后 0.039，53 秒的复拍已归干。重连或直接切到同一房间时刻得到同一残湿，沿用原来的降雨节奏。

浏览器诊断载入同一泥路、岩石网格和六张原图，交错渲染晴天和暴雨的前后材质。无窗口 Chrome 在 Apple M1 的 ANGLE Metal / WebGL 2 上以 1280 × 720 运行。复测的 8 组各采 75 帧，帧间隔中位数为 16.6–16.8 ms，P95 为 18.3–19.0 ms。报告保留最初一轮的抖动数据。这是独立材质夹具的帧时，整图帧时由最新试玩包复测。 [浏览器夹具节点](web-fixture.gd)

从项目根目录运行原生复拍。需要已导入资源的 Godot 工程和已生成的地图分块。

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
  --path "$PWD/coop" --rendering-method gl_compatibility --audio-driver Dummy \
  --resolution 96x72 --quit-after 500 \
  --script "$PWD/evidence/wet-ground-20261120/capture.gd" \
  -- /private/tmp/rainline-ground-capture "$PWD/dist/coop-atlas/zones"
```
