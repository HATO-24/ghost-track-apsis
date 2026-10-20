# 07 命令、通信与 ROE

> 状态：权威。依赖：`06`/`09`。命令/通信必须是事件，不是 UI 直接改状态。

## 1 命令模型

### 1.1 状态机

```text
DRAFT
→ ISSUED
→ TRANSMITTING
→ DELIVERED
→ QUEUED / PENDING_EFFECT
→ AUTHORIZED (如需要)
→ EXECUTING
→ DONE / ABORTED / REJECTED / STALE
```

命令带：

```text
order_id, issuer_id, target_id(s), action, params,
issued_t, deliver_t, exec_t, expire_t,
authority/ROE check, status, reason,
text_key, result
```

### 1.2 命令类型

- 导航：设目的地、申请离港、申请变轨窗口、点火、入港、并轨、对接、加注、船坞。
- 传感器：开关机、模式、凝视、IFF、ELINT 监听、可见光灯语。
- 舰队：编队、跟随、保持、撤离、拖曳、救援。
- 战斗：跟踪、解算、瞄准、发射、点防御、电子战。
- 损管：维修、封堵、断电、撤离。
- 剧情/行动：取证、派遣穿梭机、调度遥测、谈判。

命令定义数据驱动，代码不写死具体关卡命令。

### 1.3 延迟/待生效/撤销

- 命令在 `deliver_t` 到达目标；需要授权/中继时增加延迟。
- UI 显示 `待生效`/命令幽灵；可在 `exec_t` 前撤销。
- 过期命令进入 `STALE`，不执行。
- 失败原因必须可见。

## 2 通信模型

### 2.1 节点/链路

```text
CommsNode: entity, type, antenna, power, encryption, status
Link: a, b, mode(LD/LR/RDO/IR/VIS), latency, bandwidth,
      packet_loss, jam, occlusion, range, route
```

- 链路随实体运动/遮挡变化；
- 中继舰改变路径和延迟；
- 干扰/欺骗影响投递；
- 通信加密只给元数据，不解密内容（COMINT）。

### 2.2 投递

- 发送 → 路由 → 延迟 → 投递/失败；
- 失败原因：无路由/遮挡/干扰/超距/设备损坏/权限；
- 投递事件进入 EventBus；
- 命令服务订阅投递事件，再进入队列。

### 2.3 通信文本

标准格式：

```text
[from 至 to]-[LD/LR/RDO/IR/VIS]-[内容]
```

发送者/接收者/模式由**上下文自动生成**，不能硬编码。

## 3 独立命令事件文本库

正确。需要独立文本库，不是把对话写进 UI。

### 3.1 数据结构

```text
event_id, text_key, speaker_role, listener_role,
mode, channel, prerequisites, priority, cooldown,
variants, localization
```

运行时：

- 由命令/通信事件选择 `text_key`；
- `from/to` 从实际实体/角色解析；
- 支持多语言；
- 同一事件可有多模板（首次/重复/失败/紧张度）；
- 不允许重复使用同一句造成机械感；文本库按角色/关系/情境分组。

### 3.2 示例

```text
ORDER_ISSUED → "[{from} 至 {to}]-[{mode}]-[{content}]"
DELIVERY_DELAYED → "[{from} 至 {to}]-[{mode}]-[链路延迟，预计 {delay}s 后送达。]"
ORDER_REJECTED → "[{from} 至 {to}]-[{mode}]-[{reason_text}]"
```

## 4 ROE

序章后解锁，四档：

| 档位 | 名称 | 跟踪 | 解算 | 发射 | 点防御 |
| --- | --- | --- | --- | --- | --- |
| 仅防御 | WPN DEFEND | 被动/威胁源 | 直接威胁自动 | 需确认 | 自动 |
| 仅自卫 | WPN HOLD | 被动为主 | 逐次确认 | 逐次确认 | 自动 |
| 火控管制 | WPN TIGHT | 疑似威胁自动 | 敌对自动 | 一次确认 | 自动 |
| 火控自由 | WPN FREE | 敌对自动 | 敌对自动 | 手动确认 | 自动 |

### 三级授权

```text
TRACK：允许主动雷达/TWS 跟踪
SOLUTION：允许火控解算/瞄准
FIRE：允许发射
```

授权范围：单目标/武器组/单舰/全舰队；持续 N 秒或直到目标摧毁。

自动降级：

- 目标身份变中立/友军进入射界/弹药不足/传感器损坏/链路丢失；
- 自动降级到 TIGHT/HOLD，并在 UI 提示。

## 5 UI 呈现

- 顶栏 ROE 状态独立醒目。
- 未开火原因：目标牌显示锁图标 + `ROE HOLD`/`Awaiting Auth`。
- 雷达状态：静默待机→主动照射 ACTIVE。
- 命令队列显示发送者/接收者/模式/延迟/状态。
- 通信流按时间/来源过滤；动态文本不得闪烁/重复。

## 6 验收

- 命令全状态可复现；
- 同一秒多命令顺序稳定；
- 延迟/中断/撤销/过期；
- 通信动态文本正确替换 from/to/mode；
- ROE 四档行为与三级授权可测试；
- 自动降级可追溯；
- 存档恢复在途命令/通信。
