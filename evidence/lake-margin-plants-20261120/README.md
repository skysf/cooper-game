# 鹿鸣湖林缘与浅水植被

先在隔离工程验收，合入正式源码后再次导入鹿鸣湖分块，用 Godot 4.7.2 和 Apple M1 的 OpenGL 4.1 Metal Compatibility 在 1280 × 720 复拍。前后对照固定机位、天气和光照，只切换两种新植被。稳风和阵风照片保留同一光照和水面时间。浏览器帧时等到进入后续试玩包再验。

- [林缘与浅水固定机位前后对照](forest-and-shallows-before-after.jpg)
- [毛榛枝叶近景](hazel-close.jpg) · [林下果苞同机位对照](hazel-husk-before-after.jpg)
- [水葱圆秆和侧生小穗](bulrush-close.jpg) · [从水下看水葱](bulrush-underwater.jpg)
- [阵风与栈台通行视角](gust-and-dock.jpg) · [实际位置与模型规格](render-report.json) · [可复拍脚本](capture.gd)

毛榛采用东北亚林下和山坡灌丛的实际形态。模型按年轻株处理，保留灰褐色分叉小枝、宽卵状带齿的叶片和带细齿的管状果苞。10 丛分别落在东岸林缘与西岸的干地坡肩，模型根部相对湖面高 0.075–0.832 米，实测最大坡度约 27°。果苞采用偏暖的成熟色，以便在林下近景里和叶片区分。两个固定机位以相同光照复拍了这处贴图调整。 [中国科学院 iPlant 毛榛](https://www.iplant.cn/bk/12D6ACBA12837243) · [邱园接受名与原生分布](https://powo.science.kew.org/taxon/urn%3Alsid%3Aipni.org%3Anames%3A77189917-1)

水葱原生长于湖岸浅水。模型用连续的圆柱秆、贴近基部的叶鞘、从秆尖一侧伸出的褐色分枝穗表达形态。20 丛种在东岸四个浅水口袋，根部位于湖底，实测水深 0.175–0.350 米。 [上海数字植物志水葱](https://shflora.ibiodiversity.net/pages/Schoenoplectus_tabernaemontani.html) · [华盛顿州生态局水生植物手册](https://fortress.wa.gov/ecy/gispublic/AppResources/lakes/AquaticPlantGuide/descriptions/sci.html)

两种植物用同一房间阵风。毛榛主枝承受低频弯动，叶片加少量快速摆动，水葱长秆沿同一风向有较大偏移。按 8 米格分为 12 批，近景批兼顾湖面反射，21–30 米逐渐淡出。新植被的外缘离林路中线至少 2.51 米，离栈台宽度之外至少再留 2.20 米。栈台对照中原森林枝叶的横向遮挡在两张照片中都可见。现有九项海岸步行、游泳与飞行回归通过。

Blender MCP 复开源件后确认两种物种分别保留三个可编辑部分，独立对应枝叶/果苞与秆/叶鞘/穗。两张 512² 贴图打包在源文件内，各自的 GLB 单材质并保留顶点色。 [Blender 源件审计](blender-source.json)

测试可从项目根目录复跑。参数为输出目录和现有地图分块目录。

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
  --path "$PWD/coop" --rendering-method gl_compatibility --audio-driver Dummy \
  --resolution 96x72 --quit-after 650 \
  --script "$PWD/evidence/lake-margin-plants-20261120/capture.gd" \
  -- /private/tmp/rainline-lake-margin-capture "$PWD/dist/coop-atlas/zones"
```
