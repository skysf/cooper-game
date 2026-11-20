# 营地藏獒 · 胸腹比例修正

2026-11-20，已更新 `art/animals/camp_mastiff.blend`、`art/animals/camp_mastiff.glb` 和游戏加载的 `coop/props/camp_mastiff.glb`。两份导出 GLB 散列为 `865e69d391ed382c26dfebf7cfcbdd42abc5382125f078d8ed00e53a237f6250`。

Blender MCP 从源件调整胸腹段，前胸和骨盆远端各平移 50 毫米。左右分别用 `Fore.Upper` 和 `Hind.Upper` 骨头原点沿 Blender 前向 Y 算投影距离。肩髋从 0.395 米增至 0.495 米，静态模型总长从 0.865 米增至 0.965 米。宽、高、头尾和脚掌轮廓由同一套原始网格保留。重新打开候选源件检查了 23 根骨、18,274 个三角形、三张打包贴图及九段动作。三张运行贴图与原版逐字节一致。[模型记录](model.json)

对来自源件的九段动作逐帧映射到拉长骨架，动画导出统一从 0 秒开始。两套 GLB 在 Godot 4.7.2 Compatibility 内取相同时间、镜头和光源。每版共取 260 个相位，各段时长及循环模式一致。四脚蒙皮脚底高度最大变化 2.19 毫米，扣除设计的前后平移后，脚骨轨迹偏差最大 3.10 毫米。小跑和跛行的脚底最大变化分别为 1.36 和 1.30 毫米。[同机位对照](same-camera.jpg) · [逐动作统计](pose-checks.json)

实际候选资源通过原生客户端营地反馈和房间生存回归。单独的本机房间使用两名 WebSocket 客户端，验证收养归属、待命和起身片段的同一相位、跟随移动以及重启恢复。[两客户端记录](loopback.json)

复拍可将原版和新版分别放入隔离 Godot 项目的 `before/camp_mastiff.glb` 和 `after/camp_mastiff.glb`，并创建 `frames/`。以 720 × 500 分辨率运行 [定向渲染脚本](../../scripts/verify-coop-mastiff-shape.gd)。原版在提交 `d4452a7`，本机备份为 `dist/asset-work/mastiff/baseline/`。首轮全游戏模型清单中的藏獒条目对应修改前版本。[原版审计](../world-asset-audit-20261120/README.md)
