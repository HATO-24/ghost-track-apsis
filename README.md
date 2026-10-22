# GHOST TRACK · APSIS

近未来轨道战场上的**信息战指挥游戏**。玩家不操船，只下达命令；看到的是传感器与下属汇报拼出来的不完整战场。

- 设计计划书 → [`docs/01_设计计划书.md`](docs/01_设计计划书.md)
- 物理与轨道模型 → [`docs/02_物理与轨道模型.md`](docs/02_物理与轨道模型.md)
- 世界观 → [`docs/03_世界观.md`](docs/03_世界观.md)
- 舰船设定 → [`docs/04_舰船设定.md`](docs/04_舰船设定.md)
- 技术手册 → [`docs/05_技术手册.md`](docs/05_技术手册.md)
- 工业与企业 → [`docs/06_工业与企业.md`](docs/06_工业与企业.md)
- 第一关 · 监督交接 → [`docs/07_第一关_越权回收.md`](docs/07_第一关_越权回收.md)
- 声望、报告与审裁 → [`docs/08_声望与审计.md`](docs/08_声望与审计.md)
- UI 设计 → [`docs/09_UI设计.md`](docs/09_UI设计.md)
- 术语表 → [`docs/10_术语表.md`](docs/10_术语表.md)
- 传感器规则 → [`docs/11_传感器规则.md`](docs/11_传感器规则.md)
- 军语规范 → [`docs/12_军语规范.md`](docs/12_军语规范.md)
- 命令与轨道机动 → [`docs/13_命令与轨道机动.md`](docs/13_命令与轨道机动.md)
- 通信与中继 → [`docs/14_通信与中继.md`](docs/14_通信与中继.md)
- 第一关文本 → [`docs/15_第一关文本.md`](docs/15_第一关文本.md)
- 舰级与识别 → [`docs/16_舰级与识别.md`](docs/16_舰级与识别.md)
- 文本审批流程 → [`docs/17_文本审批流程.md`](docs/17_文本审批流程.md)
- 目标与节奏 → [`docs/18_目标与节奏.md`](docs/18_目标与节奏.md)
- 通信格式与批号 → [`docs/19_通信格式与批号.md`](docs/19_通信格式与批号.md)
- 港群与站点 → [`docs/20_港群与站点.md`](docs/20_港群与站点.md)
- D2 正典纲要 → [`docs/21_D2正典纲要.md`](docs/21_D2正典纲要.md)
- Demo 文本清单 → [`docs/23_Demo文本清单.md`](docs/23_Demo文本清单.md)
- 音频设计 → [`docs/28_音频设计.md`](docs/28_音频设计.md)
- 启动 CG → [`docs/29_启动CG.md`](docs/29_启动CG.md)
- 独立 Demo 打包 → [`docs/30_独立Demo打包.md`](docs/30_独立Demo打包.md)
- 系统完成度复核与开发任务队列 → [`docs/40_系统完成度复核与开发任务队列.md`](docs/40_系统完成度复核与开发任务队列.md)
- V17 测试矩阵与回归说明 → [`game_v17/docs/test_matrix.md`](game_v17/docs/test_matrix.md)

## 目录

```
docs/     设计与技术文档（含 docs/40 审计与任务队列）
game_v17/ Godot 4.7.2 当前主线（V17 / Phase 0 模拟器优先）
game_v15/ V1.5 UI 旧主线留档
game/     Godot V2 参考（地月 / 自动压平 / 自由旋转）
game_v1/  Godot V1 留档（薄荷绿 / 地球弧）
mockups/  各版成图与动效 GIF
data/     数据表（舰船、部件、传感器，JSON）
tools/    本地工具链（gitignored；Godot 4.7.2 console 可执行文件放这里）
```

## 参考坐标

| 作品 | 我们借什么 |
| --- | --- |
| Nebulous: Fleet Command | 雷达与电子战的信息密度，"看不见才是常态" |
| Highfleet | 界面即玩法，仪表化的仪式感 |
| 离轨（独立游戏） | 小团队也能做出强风格与强手感 |

## 当前状态

**Phase 0（模拟器优先基线）进行中。** 当前实现主线是 `game_v17/`，Godot **4.7.2**，
主场景 `res://main_menu.tscn`；`game_v15/`、`game_v16/` 为历史留档。

构建剖面（定义见 `game_v17/framework/content/build_profiles.json`）：

| 剖面 | 用途 | 启动方式 |
| --- | --- | --- |
| `full`（默认） | 剧情本体：序章 / 触发 / 报告，系统全开 | `godot --path game_v17` |
| `orbital_sim` | 正式轨道作战模拟器：无剧情，核心系统 + traffic/port/refit，无作弊项 | `$env:DSH_BUILD='orbital_sim'; godot --path game_v17` |
| `sandbox` | 开发/测试沙盒：同模拟器系统 + 便利项 | `$env:DSH_BUILD='sandbox'; godot --path game_v17` |
| `combat_sim`（deprecated） | 旧作战模拟器兼容剖面 | `$env:DSH_BUILD='combat_sim'; godot --path game_v17` |

`orbital_sim` / `sandbox` 启动后由主菜单自动跳到 `res://v1_hud.tscn`。
Godot 可执行文件放 `tools/godot/Godot_v4.7.2-stable_win64_console.exe`（`tools/` 已被 gitignore）；
也可用 `GODOT_BIN` 或 PATH 中的 `godot`。

## 测试与回归

一条命令跑全部 headless probe 与各剖面 boot smoke（Windows / PowerShell 7+）：

```powershell
pwsh ./run_tests.ps1            # 全矩阵；结果写入 .test-results/<run-id>/
pwsh ./run_tests.ps1 -List      # 只列出矩阵
pwsh ./run_tests.ps1 -Category profile
```

Linux / macOS（需 `pwsh`）：`./run_tests.sh -List`、`./run_tests.sh -Ci`。

Godot 发现顺序：`-GodotBin` → `$env:GODOT_BIN` → `tools/godot/Godot*console.exe` → PATH `godot`/`godot4`。
分类、输出格式、环境隔离、如何新增用例等细节见
[`game_v17/docs/test_matrix.md`](game_v17/docs/test_matrix.md)；当前真实矩阵结果以该文档与每次运行的
`.test-results/<run-id>/summary.json` 为准，**不引用历史 PASS 数**。
GitHub Actions 配置见 [`.github/workflows/tests.yml`](.github/workflows/tests.yml)
（本地无法执行，状态 NOT RUN/未验证）。

审计与任务队列：[`docs/40_系统完成度复核与开发任务队列.md`](docs/40_系统完成度复核与开发任务队列.md)。

## 与 DIIT 项目的关系

`D:\DIIT技术展示` 里已经完成的部分会迁移过来：

- 线框渲染管线（投影 / 遮挡剔除 / 深度排序 / 材质）
- 共形 HUD、接触记忆、识别状态机
- 后处理（衍射色散 / 抖动 / 扫描线）
- 自动化截图与回归脚本

迁移清单见计划书第 14 章。

## Demo

- `game_v17/` — **当前主线**：V17 模拟器优先，主场景 `main_menu`（剖面见上）
- `game_v15/` — V1.5 UI 留档：V1 版式 + 薄荷绿 + 基准弧 + V2 冷启动/像素/硬切/传感器下拉
- `game/` — V2 参考：地月立体态势、自动压平、自由旋转的代码库
- `game_v1/` — V1 留档：薄荷绿、实体地球弧
- `mockups/` — V1.5 / V2 / V1 成图与动效 GIF
- `mockups/ghost-track-demo.mp4` — 含启动 CG、主菜单、航行准备、战术态势、决策/报告/END 与音频的 47 s demo
- `ghost-track-v15-demo.zip` — V1.5 工程 + 成图打包




