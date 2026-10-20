# 独立 Demo 打包

> P8c。Windows x86_64 独立导出；不依赖 Godot 编辑器或外部工程目录。

## 1　产物

| 文件 | 说明 |
| --- | --- |
| `build/GHOST_TRACK_APSIS_demo.exe` | 双击运行；内嵌 PCK、场景、脚本、音频与 `data/scenario_l1.json` |
| `build/GHOST_TRACK_APSIS_demo.zip` | 分发包（exe + 运行说明 + 音频授权说明） |
| `build/README_DEMO.txt` | 运行/操作/音频说明 |
| `build/LICENSES.md` | 主菜单曲来源与程序化音效说明 |

## 2　重建

前置：Godot 4.7.2 stable + Windows 导出模板。

```powershell
$godot = "D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path "D:\GHOST TRACK_APSIS\game_v15" `
  --export-release "Windows Desktop" "D:\GHOST_TRACK_APSIS\build\GHOST_TRACK_APSIS_demo.exe"
```

导出预设：`game_v15/export_presets.cfg`；`export_filter="all_resources"`，`include_filter="*.json,*.md,audio/*.wav"`，`binary_format/embed_pck=true`。

## 3　已验证

- 独立运行：`AUDIO OK files=36`，`MAIN READY`，轨道/潮汐自检通过。
- 数据路径：`SCENARIO res://data/scenario_l1.json preview=true`（不读外部 `D:\...` 数据）。
- 音频：导出后 WAV 走 Godot 导入资源（`AudioDirector._load_wav` 优先 `load()`，原始 PCM 解析仅作编辑器回退）。
- 截图：`mockups/p8-standalone-final2.png`（导出 exe 运行态）。

## 4　已知

- 主菜单曲为项目方提供，公开分发前需确认授权；`build/LICENSES.md` 有记录。
- 未做代码签名；Windows SmartScreen 可能提示“未知发布者”。
- 未做安装器；zip 解压即可运行。
- 游戏内无音乐，只有设备底噪与交互/系统/警报音效。
