# 静态林冠同机位原生试拍

在正式 `Terrain` 中加载营地、进营地林径、鹿鸣溪与交汇林地的四个真实分块。仅替换溪岸上游 XZ(-9.299, -66.152) 这株树的网格。保持原树干、树根、碰撞、其余林冠、真实地表、房间时钟和定点光照，拍了 7.2 米附近的四组近景和 18 米的四组远景。远景俯视机位可越过近处邻树枝叶观察树冠。两轮合计通过 100 项结构和画面生成检查，其中部分重复验证了相同结构。 [相机、实际提交数和分块哈希](native-report.json)

- [四方向近景对照](near-four-azimuths.jpg) · [树下细枝和针叶](beneath-the-boughs.jpg)
- [四方向远景对照](far-four-azimuths.jpg) · [稳风、阵风和同机位近远过渡](gust-and-distance-steps.jpg)
- [原地面上的两组阴影三联对照](ground-shadow-controls.jpg)

树下能看见小枝梢和实拍针叶，原有规则大片被分成疏密相间的枝组。远处树高保留，在四个机位中仍比周围的原树冠细疏，颜色也偏暖。近、远样件之间的剪影边界在四个方向的几何抽样中重合约 90%–93%。 [几何轮廓比较](geometry-coverage.json)

地面第三张控制图只抽掉该树，其余照明和植被保持同一状态。以比控制图暗至少 7/255 为门槛，林径侧连续覆盖 15 × 15 像素的暗影样本从 5,343 降到 172，林下侧从 5,064 降到 513。两处目标树导致的显著遮暗像素约少 47%，细分枝的地面投影仍可见。固定暴雨光照与相机时，目标位置风场的幅值由 0.66 升到 1.90，树下图中 36,018 个像素变化达到 14/255。 [原生回归数据](native-report.json)

实际主视口，单株近档增加 4,788 个三角和 9 次可见绘制提交，远档增加 1,134 个三角和 4 次提交。近档阴影提交增加 9,576 个三角。 [原生试点数据](native-report.json) · [网页定点与长路线](../world-detail-web-20261120/README.md)

试拍使用 Apple M1 上的 Godot 4.7.2 Compatibility，分辨率 1024 × 576。 [模型生成](../../scripts/build-streamed-crown-pilot.py) · [分块定位记录](attribution.json)

## 生产源码里的单株试点

当前源码在 `world.json` 的 `streamedCrowns.approach` 声明试点位置、模型资源和 15.796 米的风场基准高度。`Terrain` 随 `approach` 挂载、释放这一株，邻接的 `creek` 去掉同一株越界的旧枝叶。试点包配套读取 `dist/coop-streamed-crown-20261120/zones`。`approach.glb` 为 1,577,152 字节，`creek.glb` 为 2,090,960 字节。七份旧分块文件逐一核对哈希，原有碰撞、树点及其余地图字段一致。 [分块和地图清单哈希](production-packet-report.json)

正式模型沿用实拍样件的树干和枝叶几何。两档复用同一张针叶实拍图和冷绿色校正。GLB 只携带几何和顶点属性，共 544,104 字节。随分块加载、卸载和重载的 25 项短检通过。 [流送短检](production-load-report.json) · [正式 Blender 源件](../../art/vegetation/luming_streamed_crown.blend)

## 18–23 米整枝交接

交接以镜头到树根的水平距离计算。18 米内保留完整近档，23 米起使用完整远档。模型的 189 组枝叶各有一个固定顺序，同一组的近、远针叶和对应细枝使用同一数值。到达切换点时整组替换，树干始终共用一份网格。几何、法线、UV、顶点 RGB 和风场沿用冷绿色版本。 [GLB 顶点属性检查](branch-attributes.json)

在同一个 13.75 米机位分别固定为近档、中点和远档，以复测原来逐像素交接的亮孔。抽查树冠区域中，比两个端点都亮至少 7 级的像素由 8,720 个降至 268 个，仅在中点判为天空的像素由 1,522 个降至 17 个。中点平均亮度由高于较亮端点 3.78 级降到低于该端点 0.52 级。实际 20.5 米机位的中点曝光在两个端点之间，抽查区域中仅在中点判为天空的像素为 0。此次 Godot Compatibility 原生复拍通过 15 项检查。 [三组三联图](whole-branch-transition.jpg) · [曝光数据](transition-exposure.json) · [原生复拍检查](transition-native-report.json)

近远档之外仅显示一套针叶网格。交接区两套网格仍会提交顶点，同行渲染成本需要以网页实际走过该位置的路线为准。

```sh
COOP_ZONES_DIR=dist/coop-streamed-crown-20261120/zones python3 scripts/coop-zones.py --reuse-materials
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path "$PWD/coop" \
  --script "$PWD/scripts/test-coop-streamed-crown.gd" -- "$PWD/dist/coop-streamed-crown-20261120/zones" \
  /private/tmp/rainline-streamed-crown-load.json
```
