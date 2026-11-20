# 鹿鸣溪岸的荚果蕨

在真实 `creek` 和 `crossing` 分块绘制的坡面上试种了 5 株成株和 9 株幼株。着根点距溪水可见边线 0.30–0.82 米，地表高于水线 4.1–7.5 厘米。把植株尺度和最大阵风偏移都计入后，叶缘距林路中心至少 3.36 米，距栈桥和接岸通道至少 3.35 米，距木料取用通道至少 1.65 米。原有角色移动函数实测通过栈桥、木料堆和涉水道。 [坐标、坡度及通行距离](creek-bank-survey.json)

成株的短暗色根茎覆盖旧柄和鳞片。每片绿色不育叶向上展开，羽片由基部向上逐渐展宽，在叶尖附近收窄。成株中部两片更短的深褐色能育叶保留内卷的形态。近看能看到纸质叶片的深裂缘和带浅色叶脉的叶背。按季末林下植株处理，保留小型株和成熟株两种尺度。 [中国科学院植物智荚果蕨](https://www.iplant.cn/bk/16FFCDD10A0664EE) · [不列颠哥伦比亚植物志的河岸生境记录](https://linnet.geog.ubc.ca/Atlas/Atlas.aspx?sciname=Matteuccia+struthiopteris)

- [同机位前后对照](creek-fixed-before-after.jpg)
- [成株、羽片叶脉和根冠细节](fronds-and-crown.jpg)
- [同机位阵风和近远过渡](gust-and-distance.jpg)
- [雨天、栈桥入口与原有水下植被](rain-and-underwater.jpg)

共用 512 × 512 内嵌图集，GLB 为 1.18 MB。成株高约 0.97 米，近、远模型分别为 8,827、2,854 三角。幼株高约 0.74 米，近、远模型分别为 3,839、1,190 三角。以 6 米格分批，8–11.5 米内逐步过渡到远模，22–29 米淡出。实际主视口，近岸机位增加 5 次提交和 66,877 个三角，距主要成株约 16 米的机位增加 3 次提交和 18,556 个三角。主视口帧时与帧率留待下一轮浏览器测试。 [GLB 审计](glb-inspection.json) · [Blender 可编辑部件审计](blender-source.json)

Godot 4.7.2 在 Apple M1 OpenGL 4.1 Metal Compatibility 中使用正式 `res://` 路径复测通过 128 项。毛榛、水葱和荚果蕨接受同一个房间阵风向量。保持光照和水面时间时，所选株位的风速从 0.66 升到 1.60，主要叶片区域有 20,950 个像素变化超过 18/255，根冠区域有 1 个像素超过该阈值。固定在交叠区，比对双模和单模时可辨识植株覆盖变化约 1.4%。已有湖岸植被专项复跑通过，核对了 10 丛毛榛、20 丛水葱与下潜后的水下光色。 [原生回归数据](native-render-report.json)

从项目根目录复跑，依次传入输出目录和现有地图分块目录。

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
  --path "$PWD/coop" --rendering-method gl_compatibility --audio-driver Dummy \
  --resolution 96x72 --quit-after 600 \
  --script "$PWD/evidence/creek-ostrich-fern-20261120/capture.gd" \
  -- /private/tmp/rainline-creek-fern-capture "$PWD/dist/coop-atlas/zones"
python3 evidence/creek-ostrich-fern-20261120/survey-bank.py
```
