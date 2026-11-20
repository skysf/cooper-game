# 5594 装备和容器贴图盘点

`index.pck` 有 265,848,716 字节和 860 个条目。装备 13 图共 125,344,546 字节，容器 15 图共 44,608,702 字节，分别占 47.1% 和 16.8%。下表的体积和分辨率来自发行包里的 CTEX 目录和文件头，通道来自对应 GLB 材质。容器所有带 `4k` 的名称均沿用扫描源名，实际底色和法线为 2048 像素。

装备在首次房间快照中已有地面实例，客户端收到快照便读入模型。五类容器在场景初始化时主动发起读取，开局即已有六个实例。背包小图独立使用现成图像。以下距离为新房间初始出生点的水平距离，以每种物件最近实例计。

## katana

开局地面和拿取、装备、丢下，再由同伴显示手中的同一模型。刀身与刀柄共图。 最近初始距离约 1.38 米，贴图合计 17,115,095 字节。

| 文件 | 尺寸 | PCK 字节 | 用途和通道 |
| --- | --- | ---: | --- |
| `antique_katana_01_nor_gl.webp` | 4096 × 4096 | 6,430,121 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `antique_katana_01`。 |
| `antique_katana_01_diff_4k.jpg` | 4096 × 4096 | 8,202,015 | 底色。sRGB RGB。材质 `antique_katana_01`。 |
| `antique_katana_01_metal-antique_katana_01_rough.webp` | 2048 × 2048 | 2,482,959 | 粗糙度/金属度。G 粗糙度，B 金属度，R 无材质引用。材质 `antique_katana_01`。 |

## rifle

开局地面、再拾取与丢下、持枪和开镜、同伴装备，机匣和光学配件分材质。 最近初始距离约 1.60 米，贴图合计 78,410,428 字节。

| 文件 | 尺寸 | PCK 字节 | 用途和通道 |
| --- | --- | ---: | --- |
| `bolt_action_rifle_7_62_nor_gl.webp` | 4096 × 4096 | 12,609,295 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `bolt_action_rifle_7_62`。 |
| `bolt_action_rifle_7_62_accesories_nor_gl_4k.webp` | 4096 × 4096 | 16,114,177 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `bolt_action_rifle_7_62_accesories、bolt_action_rifle_7_62_accesories_glass`。 |
| `bolt_action_rifle_7_62_diff_4k.jpg` | 4096 × 4096 | 20,490,230 | 底色。sRGB RGB。材质 `bolt_action_rifle_7_62`。 |
| `bolt_action_rifle_7_62_accesories_diff_4k.jpg` | 4096 × 4096 | 19,549,396 | 底色。sRGB RGB。材质 `bolt_action_rifle_7_62_accesories`。 |
| `bolt_action_rifle_7_62_metal-bolt_action_rifle_7_62_rough.webp` | 2048 × 2048 | 4,361,739 | 粗糙度/金属度。G 粗糙度，B 金属度，R 无材质引用。材质 `bolt_action_rifle_7_62`。 |
| `bolt_action_rifle_7_62_accesories_metal-bolt_action_rifle_7_62_accesories_rough.webp` | 2048 × 2048 | 4,154,158 | 粗糙度/金属度。G 粗糙度，B 金属度，R 无材质引用。材质 `bolt_action_rifle_7_62_accesories、bolt_action_rifle_7_62_accesories_glass`。 |
| `bolt_action_rifle_7_62_accesories_diff-bolt_action_rifle_7_62_accesories_alpha.webp` | 1024 × 1024 | 1,131,433 | 透镜底色和透明度。RGB 为 sRGB 底色，A 为透明度。材质 `bolt_action_rifle_7_62_accesories_glass`。 |

## pistol

开局地面、再拾取与丢下、第一及第三人称装备和同伴，木握把、枪身和各独立钢件共图。 最近初始距离约 0.73 米，贴图合计 29,819,023 字节。

| 文件 | 尺寸 | PCK 字节 | 用途和通道 |
| --- | --- | ---: | --- |
| `service_pistol_nor_gl.webp` | 4096 × 4096 | 7,191,191 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `service_pistol`。 |
| `service_pistol_diff_4k.jpg` | 4096 × 4096 | 18,640,745 | 底色。sRGB RGB。材质 `service_pistol`。 |
| `service_pistol_metal-service_pistol_rough.webp` | 2048 × 2048 | 3,987,087 | 粗糙度/金属度。G 粗糙度，B 金属度，R 无材质引用。材质 `service_pistol`。 |

## wicker_basket

开局两篮、容器放置、搬运、投掷以及可制作的篮子。编藤、盖与脚共图。 最近初始距离约 2.37 米，贴图合计 10,579,064 字节。

| 文件 | 尺寸 | PCK 字节 | 用途和通道 |
| --- | --- | ---: | --- |
| `wicker_basket_02_nor_gl.webp` | 2048 × 2048 | 4,466,103 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `wicker_basket_02`。 |
| `wicker_basket_02_diff_4k.jpg` | 2048 × 2048 | 5,256,799 | 底色。sRGB RGB。材质 `wicker_basket_02`。 |
| `wicker_basket_02_rough.webp` | 1024 × 1024 | 856,162 | 粗糙度。G 粗糙度。金属度系数为 0，B 不影响材质。R 无材质引用。材质 `wicker_basket_02`。 |

## wood_crate

开局箱、放置、搬运、投掷。旧木纹、板缝、盖与紧固件共图。 最近初始距离约 2.25 米，贴图合计 9,222,575 字节。

| 文件 | 尺寸 | PCK 字节 | 用途和通道 |
| --- | --- | ---: | --- |
| `wooden_crate_01_nor_gl.webp` | 2048 × 2048 | 3,356,196 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `wooden_crate_01`。 |
| `wooden_crate_01_diff_4k.jpg` | 2048 × 2048 | 4,887,455 | 底色。sRGB RGB。材质 `wooden_crate_01`。 |
| `wooden_crate_01_metal-wooden_crate_01_rough.webp` | 1024 × 1024 | 978,924 | 粗糙度/金属度。G 粗糙度，B 金属度，R 无材质引用。材质 `wooden_crate_01`。 |

## military_crate

开局装绳的箱、放置、搬运、投掷。掉漆、搭扣和盖共图。 最近初始距离约 4.10 米，贴图合计 9,599,574 字节。

| 文件 | 尺寸 | PCK 字节 | 用途和通道 |
| --- | --- | ---: | --- |
| `wooden_military_crate_nor_gl.webp` | 2048 × 2048 | 3,786,229 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `wooden_military_crate`。 |
| `wooden_military_crate_diff_4k.jpg` | 2048 × 2048 | 4,962,306 | 底色。sRGB RGB。材质 `wooden_military_crate`。 |
| `wooden_military_crate_metal-wooden_military_crate_rough.webp` | 1024 × 1024 | 851,039 | 粗糙度/金属度。G 粗糙度，B 金属度，R 无材质引用。材质 `wooden_military_crate`。 |

## wood_barrel

开局普通桶、放置、搬运、投掷。桶箍、木板、盖与堵头共图。 最近初始距离约 3.91 米，贴图合计 7,526,504 字节。

| 文件 | 尺寸 | PCK 字节 | 用途和通道 |
| --- | --- | ---: | --- |
| `wooden_barrels_01_barrel01_nor_gl_4k.webp` | 2048 × 2048 | 2,200,952 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `wooden_barrels_01_barrel01`。 |
| `wooden_barrels_01_barrel01_diff_4k.jpg` | 2048 × 2048 | 4,405,034 | 底色。sRGB RGB。材质 `wooden_barrels_01_barrel01`。 |
| `wooden_barrels_01_barrel01_metal-wooden_barrels_01_barrel01_rough.webp` | 1024 × 1024 | 920,518 | 粗糙度/金属度。G 粗糙度，B 金属度，R 无材质引用。材质 `wooden_barrels_01_barrel01`。 |

## wood_barrel_tall

开局大桶、放置、搬运、投掷。材质为第二套扫描，桶箍与木板共图。 最近初始距离约 5.16 米，贴图合计 7,680,985 字节。

| 文件 | 尺寸 | PCK 字节 | 用途和通道 |
| --- | --- | ---: | --- |
| `wooden_barrels_01_barrel02_nor_gl_4k.webp` | 2048 × 2048 | 2,313,313 | 切线法线。R/G 为切线分量，标准材质重建 Z，法线导入已开启。材质 `wooden_barrels_01_barrel02`。 |
| `wooden_barrels_01_barrel02_diff_4k.jpg` | 2048 × 2048 | 4,453,915 | 底色。sRGB RGB。材质 `wooden_barrels_01_barrel02`。 |
| `wooden_barrels_01_barrel02_metal-wooden_barrels_01_barrel02_rough.webp` | 1024 × 1024 | 913,757 | 粗糙度/金属度。G 粗糙度，B 金属度，R 无材质引用。材质 `wooden_barrels_01_barrel02`。 |

## 下一轮先验证一张底色

`service_pistol_diff_4k.jpg` 为 4096 × 4096 的不透明 RGB 底色，对应的 CTEX 为 18,640,745 字节，约占整个 PCK 的 7.0%。CTEX 内是 Zstd 超压缩的 13 级 KTX2 mip，可对照解压后的 UASTC 分块。木握把和钢件共用同一个材质，便于在原机位检查边缘磨损和颜色细节。

先在仅含该图片的隔离工程确认重现基线 CTEX。最高分辨率、mipmap、UASTC 级别 1、RDO 0.45 保持基线，只将 Zstd 超压缩级别由已用 Godot 4.7.2 确认的默认值 6 提高作 A/B，核对每级 mip 的解压结果逐字节相同。节省有限时再将 RDO 增量作为独立实验，视觉验收需逐项核对。公开启动包仍使用同一主场景和原余下资源。 [Godot 导入参数](https://docs.godotengine.org/en/stable/classes/class_resourceimportertexture.html) · [Godot Basis 超压缩参数](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-textures-basis-universal-zstd-supercompression-level)

浏览器按固定带宽和相同冷缓存条件串行比较 A/B，记录实际传输字节、首个可玩时刻、物件首帧和帧间隔。原游戏机位核对地面近看、拿起、装备和第三人称手持，固定光照并检查木握把、钢件磨损、边缘倾斜时的纹理，以及各级 mip。确认该图以外的资源哈希一致。

## Web 分包候选

用同一现成 CTEX 做独立资源包能保留完整贴图。拆分单位为整个模型的网格资源、导入映射和所有贴图，它们都就绪后再实例化。开局三件装备距玩家 0.73–1.60 米，背包和拾取前的地面机位都需要真实模型。仓储初始化主动发起五类加载，也需要随挂载时机调整。第一轮流送由距离较远的大木桶做验证，它有约 7.68 MB 的贴图，需兼测已有存档就在桶边的加入路径。后续可按装备拆分，步枪不能把共用法线和粗糙度的镜片与镜架当成互不相干的物件。

记录组包实际请求的时刻、同机位完整资产出现的第一帧和首个交互。玩家初始就能看见或操作物件时，关键分包需要先就绪。如果需要等到完整首景才能开放，单独报告启动包缩小与实际可玩时刻两种结果。 [Godot 资源包加载](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html)

篮子的 G 通道是有效的单通道粗糙度，适合作为低风险打包试验。其余箱桶和装备的 G 与 B 都有材质用途，法线的 R/G 导入也已设置。镜片 RGBA 约 1.13 MB，保留原透明通道。
