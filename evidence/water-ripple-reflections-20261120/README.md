# 湖面与外海的雨滴涟漪

以 5384 网页截图的相机、视野和房间时间复拍鹿鸣湖和近海。原来的两种水面都会在光照之后给每道涟漪加一道浅灰亮边，暴雨时两组落点几乎每格都出圈。对照中单独关掉亮边，近湖和近海的醒目圆印即大幅减少。 [5384 湖面](../world-weather-web-20261120/lake-water-rain.png) · [5384 外海](../world-weather-web-20261120/coast-water-rain.png)

现在两种水面以局部法线表现雨滴对倒影和折射的扰动。每次落水有不同的大小和椭圆方向，沿波峰扩开并随年龄减弱。两组稀疏落点有不同的旋转方向，避免连成整齐的行列。远处按视距和像素覆盖逐渐衰减，融入原有主浪。晴天在计算随机落点和导数滤波前退出，沿用原水面颜色、光照和投石逻辑。

- [鹿鸣湖及近海同机位前后对照](lake-and-sea-fixed.jpg)
- [同一范围内的原着色、单独去亮边和改进版](near-water-profile-controls.jpg)
- [远湖、外海、溪湖交接和岸边浅水](distance-and-waterline.jpg)
- [晴天与水下对照](clear-and-submerged.jpg)

Godot 4.7.2 在 Apple M1 OpenGL 4.1 Metal Compatibility 下，以 1280 × 720 复拍 15 个场景和房间时刻，98 项检查通过。测试覆盖近远湖、浅湾外海、雨势减弱、晴天投石、湖海水下和岸边交接。两个着色器接收相同的房间秒数。

和同机位仍保留主浪的无雨圈对照相比，8 米内亮度增加至少 7/255 的像素，近湖从 10,552 降到 1,008，近海从 10,240 降到 127。局部法线的亮纹与暗纹同时可见。22.1 米外的采样区域未见醒目的独立亮圈，其中外海的 20,489 个采样像素和对照逐像素一致。

晴天海面对照逐像素一致。晴天湖面重复开原着色器时全画面 RGB 平均绝对差为 0.094/255，改动前后为 0.060/255。差异低于同材质重复采样的波动。水下近处随法线有轻微变化，湖海的水下判定和原有折射方案通过复验。该版的网页帧时待下一次测试。 [像素统计、机位和源码哈希](report.json)

可使用正式工程与现有地图分块复拍。脚本读取同目录留存的原着色器，并直接加载正式 `res://` 中的新着色器。

```sh
review="$PWD/evidence/water-ripple-reflections-20261120"
frames=/private/tmp/rainline-water-ripples
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
  --path "$PWD/coop" --rendering-method gl_compatibility --audio-driver Dummy \
  --resolution 96x72 --quit-after 680 --script "$review/capture.gd" \
  -- "$frames" "$PWD/dist/coop-atlas/zones" "$review"
python3 "$review/analyze.py" "$frames"
```
