# GUI DEMO 02 — 地月指挥终端（自动压平版）

运行：

    "D:\GHOST TRACK_APSIS\tools\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\GHOST TRACK_APSIS\game"

操作：
- 鼠标拖动地图：自由旋转
- 滚轮：缩放。3D 下缩到 640,000 km 以上自动压平；压平下继续放大回到 3D
- R：翻转视角
- 点击地图上方 SENSOR 条：展开传感器阵列（6 个厂商模块）
- Space 暂停 / 1-4 时标 / Esc 退出

说明：
- 中心永远锁在旗舰 APSIS 上，不自由平移。
- 压平是自动的，没有手动 FLAT 按钮；右上角只显示 AUTO / 3D 或 AUTO / PLANAR。
- 厂商与系统名均为本项目设定：远地点船坞 / 铁砧重工 / 北辰光学 / 白霜仪器 / 静默通信 / 天平动船坞。
- 传感器目前只切换视觉图层，还没有接仿真数据。
- 启动约 1.7s 冷启动序列。

旧版留档：game_v1/（薄荷绿、地球轨道版），成图 mockups/gui-demo-01-v1.png。
备用副本：C:\gt_game

