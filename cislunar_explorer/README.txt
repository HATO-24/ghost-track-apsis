CISLUNAR EXPLORER — 地月系技术演示
================================

独立 Godot 4.7.2 技术 demo；V1 终端线框风格。

模型：地球中心惯性帧 + 月球圆轨道 + CR3BP L1–L5 数值驻点；
GEO 环、月球同步环、月球低轨/极轨站、地球港/月球港。
HUD 标注 EARTH-MOON CIRCULAR MODEL / CR3BP L-POINTS，非 JPL 星历。

控制：
  左键拖拽 旋转          右键/中键 平移        滚轮 缩放
  1 地球  2 月球  3 L1  4 选中焦点
  TAB 循环对象  F 循环焦点  R 重置
  SPACE 暂停/播放  -/= 时间倍率 1×/10×/100×/1000×
  ESC 退出

数据：sim/cislunar_model.sample(t)，坐标 km；1 scene unit=1000 km。
