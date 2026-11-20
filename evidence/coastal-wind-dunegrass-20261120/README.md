# 海岸阵风与滨麦实拍

Godot 4.7.2 的 OpenGL 4.1 Metal Compatibility 在 Apple M1 渲染了真实营地分块与海岸，截图分辨率为 1280 × 720。阵风对照固定机位、日照和雨量，只更换房间风场的采样时间。滨麦前后对照固定同一机位，只切换新增滨麦批次是否显示。

- [海湾沙地前后对照](dunegrass-before-after.jpg) · [滨麦近景](dunegrass-detail.jpg)
- [松树、云杉、海岸蕨类和滨麦的阵风对照](shared-gust.jpg) · [树冠的距离过渡](tree-lod.jpg) · [海湾雨丝](rain-direction.jpg)
- [实测与模型数据](render-report.json) · [可复拍脚本](capture.gd)

滨麦（*Leymus mollis*）自然生长在高水位线以上的海滨沙地。这里在海湾主陆的四处沙地试种 26 丛，实际位置在平均海面以上 0.58–1.51 米，避开步道和裸岩。Blender 源文件保留叶、茎、穗三个可编辑部分，游戏模型有带穗和无穗两种外形。叶的折面、纵肋和略带蓝的叶色，借鉴了实地物种性状。 [中国科学院 iPlant 滨麦](https://www.iplant.cn/info/Leymus%20mollis?t=focn) · [石狩市资料馆](https://www.city.ishikari.hokkaido.jp/museum/1001801/1004573/1004708.html) · [华盛顿大学 Burke Herbarium](https://burkeherbarium.org/imagecollection/taxon.php?Taxon=Leymus+mollis)

营地松树分别在 7–9 米和 17–19 米混合两个细节级别，海岸树在 36–43 米与远景树冠过渡。四个相机朝向复验的世界雨向一致。两处矿洞的廊道判定共排除 23 丛旧灌木。浏览器帧时由网页试玩验收。

从仓库根目录运行以下命令。需要已导入资源的原生 Godot 4.7.2 工程和生成好的营地分块。

```sh
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
  --path "$PWD/coop" --rendering-method gl_compatibility --audio-driver Dummy \
  --resolution 96x72 --quit-after 600 \
  --script "$PWD/evidence/coastal-wind-dunegrass-20261120/capture.gd" \
  -- /private/tmp/rainline-coastal-capture "$PWD/dist/coop-atlas/zones/camp.glb"
```
