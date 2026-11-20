# 营地袭击者角色与装备

四款成年角色使用同一套 25 骨的人形层级。骨名沿用营地玩家模板的脊柱、肩臂和髋腿约定，身体网格按男女参考图分别制作。高级款在对应体型上穿角面具、分层长毛衣和铃带。外衣与毛束合入同一蒙皮网格。服饰使用分片几何与参考投影，近景辫发、羽饰、叶片、耳环、手指与硬质角均有实体轮廓。脸和躯干正中保留原图取样，左右侧由侧视与正背视图连续过渡。

原图在 [source_images](source_images/)；同目录的七个 Blender 源文件保留材质、网格、动作和打包贴图。游戏文件见 [coop/wild_people](../../coop/wild_people/)。已用 Blender 5.2.4 LTS 分别复开源文件，记录见 [源文件检查](preview/source-checks.json)。

| 资产 | 三角面 | 材质表面 | GLB 大小 |
|---|---:|---:|---:|
| 普通男性 | 26,886 | 6 | 1.52 MiB |
| 普通女性 | 38,420 | 8 | 1.89 MiB |
| 高级男性 | 15,084 | 10 | 1.26 MiB |
| 高级女性 | 15,300 | 10 | 1.29 MiB |
| 木棒 | 1,862 | 2 | 43 KiB |
| 长矛 | 2,234 | 3 | 53 KiB |
| 编织盾 | 10,006 | 4 | 227 KiB |

## 引擎接入

角色面向 Godot 的 −Z，单位为米，场景原点在脚下。角色和装备各自只有一个网格。右手握点为 `grip_R`，左手为 `grip_L`。建立对应的 `BoneAttachment3D` 并以单位局部变换挂上装备。长轴沿装备局部 +Y，盾面朝 −Z。石头沿用营地现有资源，移动位移、碰撞、击中与受伤状态由游戏管理。

Godot 导入后，可播放九段循环动作 `Idle`、`Walk`、`Run`、`Limp`、`LimpLeft`、`Guard`、`Block`、`Captive`、`Rest` 和三段单次动作 `Attack`、`Throw`、`Down`。移动循环均为原地动作。左右腿分别受伤时使用 `LimpLeft` 和 `Limp`，武器握持侧保持一致。`Down` 的尾帧供昏迷或死亡状态停留。

## 重建与验收

项目 Blender 启动器执行 [构建脚本](../../scripts/build-wild-people.py)，用本机 Python、Pillow 与 NumPy 从原图处理材质，所用几何与动作均在项目内生成。

```sh
./scripts/start-blender.sh --background --factory-startup --python-exit-code 1 --python scripts/build-wild-people.py -- weapons male female male_elite female_elite
```

[多角度与面部近景](preview/turnarounds.jpg) 及 [动作与装备](preview/poses.jpg) 均由 Godot 4.7.2、Apple M1、OpenGL Compatibility 实际加载 GLB 后拍摄。每款的步行与跑步各采样 49 个时刻，其余动作各采样 17 个时刻，并在渲染同步后读取蒙皮包围盒和双踝摆幅。渲染中另测了棍、矛和盾的握点偏差。[Godot 验证数据](preview/godot-checks.json) 包含动作名、时间、循环模式和逐段量值。

最终抽样的步行最低点高于地面 2.0–8.1 毫米，跑步为 3.0–12.5 毫米。左右伤腿的踝部前后摆幅分别约 0.236 米和 0.760 米，动作换边后两侧数值互换。倒地过程中高级衣摆最低点短暂低于地面约 1.2 毫米。验证中的棍、矛与盾在对应握点的局部原点误差均为零。

独立复测可在临时 Godot 项目内建立 `wild_people/` 与 `frames/`，将七份 GLB、角色的导入侧文件和[验姿脚本](../../scripts/verify-wild-people.gd)复制进去。完成资源导入后，在 420 × 540 的 Compatibility 渲染窗口执行该脚本，逐视角的 PNG 与数值报告会写入临时项目的 `frames/`。

六种新增背包缩略图沿用营地原有的透明物件渲染方法，由[图标生成脚本](../../scripts/build-wild-people-icons.py)出图。木棒、矛、盾、石头和水壶取自游戏模型，药草使用一束扎起的叶枝。

实际网页营地中以约 1.81 米的距离检查女性跪姿时，发现第一版正背投影在腰侧出现明显直线。最终贴图使用参考中的侧视重建过渡，并从最终 GLB 重新检查了[同角度侧身](preview/captive-side.png)。
