# JC-B01A 非 headless 最小部署证据（真实窗口/真实 HUD/Binder）

环境：Windows / Godot 4.7.2.stable.official.ed1daf0bf / OpenGL3 真实窗口（非 headless），1600x900。

操作步骤（真实入口）：
1. 场景：res://framework/content/scenario_b01a_deploy_demo.json（fleet_formation/fleet_refit/command_domains/fleet_instances/deployment 同源 seed；部署 A：APSIS command + HARMATTAN screen + FERRY gun + DEEPWELL logistics + WATCHTOWER relay）。
2. 启动参数：`DSH_B01A_SCENARIO=res://framework/content/scenario_b01a_deploy_demo.json`、`DSH_BUILD=orbital_sim`、`DSH_V1_VIEW=fleet_builder`、`DSH_HUD_SIZE=1600x900`、`DSH_SHOT=<png>`、`DSH_B01A_DEPLOY_TEST=1`。
3. 主菜单按“模拟剖面 + B01A 测试”跳转真实 v1_hud；Binder 在真实 Session 上执行 `DEPLOY_PLAN`（ok=true, revision）与 `DEPLOY`（confirm=true，结果 already_deployed/deployed + revision）；HUD 绘制部署状态、按钮、结果/拒绝原因，第 40 帧截图退出。

实测输出：
```
[V1 HUD] binder boot=true errors=[] contacts=0 orders=0
[B01A DEPLOY SELFTEST] plan ok=true revision=rev-425754d2
[B01A DEPLOY SELFTEST] deploy ok=true revision=rev-91bf12e8 reason=already_deployed
V1 HUD SHOT size=(1600, 900) err=0
```

截图：`fleet_builder_deploy.png`（1600x900）：可见 FLEET BUILDER 页、ROSTER/SLOTS/VALIDATION、底部 `DEPLOY PLAN / 部署检查` 与 `DEPLOY / 确认部署` 按钮、状态行 `DEPLOY · DEPLOYED rev=rev-91bf12e8 · 5 instances`、结果行 `DEPLOY · OK · rev=…`。

说明：这是真实可见入口的部署确认/结果样张，不等于完整战役试玩；B1b 逐舰火控账本/B1c 舰组控制未完成。

## 第二轮：未部署 → 确认 → 首次生成（auto=false）

- 场景改为 `deployment.auto=false`：真实窗口 HUD 启动时 `DEPLOY · NOT DEPLOYED`，无参战实体生成。
- 真实点击/执行 `DEPLOY PLAN` → revision=rev-425754d2；`DEPLOY`（confirm=true）→ **首次生成成功**，deploy ok=true、revision 与 plan 完全一致（rev-425754d2），HUD 显示 `DEPLOY · DEPLOYED rev=rev-425754d2 · 5 instances`。
- 截图：`fleet_builder_first_confirm.png`（1600x900，OpenGL3 真实窗口）。
- 配置冻结时机：首次确认时读取当时 FleetRefit 实际配置并写入快照；部署后再改 refit 不改变已冻结快照；首次部署允许在真实 UI 任意帧确认，已部署后换编制仍 `deployment_locked`。
