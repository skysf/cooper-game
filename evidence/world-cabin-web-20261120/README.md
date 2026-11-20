# 5484 网页试玩验收

使用 Apple M1 的无窗口 Chrome 与 ANGLE Metal，1280 × 720。七处正式游戏机位各采 5 秒。当前包的 SHA256 为 `3a368015c1eb97f3c6a2428bd01afedbeb55897828d9d56b490cb675c07b111f`。 [七处原始帧时](fixed-camera-initial.json)

第一轮中鹿鸣溪岸、雨湖、煤矿、营地屋内与水下为 60.0 FPS。营火和雨海为 57.0 FPS，最长帧间隔分别为 200 和 133.3 ms。七处 P95 为 16.7–16.8 ms。营火正式位置已清出石圈内的旧草叶，保留圈外植被。 [营火剪影前后](before-fire-clearance.png) · [清场后的实拍](campfire-rain.jpg)

相同包、相同条件单独复采营火和雨海，两个机位都是 60.0 FPS，最长帧间隔都是 16.8 ms。保留首轮和复测的完整样本供排查偶发长帧及后续前台长路线对照。 [两处复采数据](fixed-camera-repeat.json)

用实际 **K**、**G**、左键、Shift 及 **W** 从材料造地板、门框、三面墙和屋顶。缺乏支撑的屋顶显示红色，失败确认后背包数量相同。完工后走进门洞，角色站在高 0.18 米的板面。第一次自动输入多走过一个目标点，重跑使用按位置校正的实际键鼠步骤，五项全过。 [建造按键回归](construction-web.json) · [木屋外观](cabin-exterior.jpg) · [装好屋顶](finished-cabin.jpg)

网页实际按 **F** 取煤和铁矿石，按 **E** 打开营火添煤，复拍熄灭与点燃的火堆，最后用两块铁矿石和一块煤炼成铁锭。四项流程通过。 [采炼回归](mining-web.json) · [点火前](campfire-out.jpg) · [点火后](campfire-lit.jpg)

源资产清单共 83 件运行 GLB 和七个流送分块。煤矿和铁矿入口模型在全量拍照后更新为新灯，当前清单含它们的新哈希。 [发布资产清单](release-assets.json) · [荚果蕨实装](creek-ferns.jpg) · [煤矿由内向外](mine-rain.jpg) · [雨湖](lake-water-rain.jpg) · [雨海](coast-water-rain.jpg)
