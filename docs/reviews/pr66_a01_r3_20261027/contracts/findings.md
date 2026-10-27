# PR66 第三轮：两项旧 probe 的契约映射与等强度修正

日期：2026-10-27（Asia/Shanghai）。候选：`8b4cf990021bafe0f5b2945039c850b5c985cf5a`。本分项只读审查两项剩余探针及当前消费者，不修改生产代码、正式测试、baseline或GitHub。旧发射十组另原样复跑，没有新增反例范围。

## 1. 依据与本轮实际结果来源

56 R2 `docs/56_Astra_开发需求_交6Sol.md:71` 明确：EntityCatalog承载静态真值；合成视图注明来源；玩家contacts/track服从证据与可见性；调整断言需逐项映射及等强度负例，保留丢失、错误归属、静默friend回退和真值泄露检查。`:83–88`进一步区分无噪声几何与观测误差、稳定内部ID与匿名显示、内部唯一物理真值与分方情报。

根代理本轮实际运行，日志在 `.test-results/sol-a01-r3/targeted/20261027-003909-8b4cf990/logs/`：

- `integration.a1_entity_metadata_authority`：**342/7**。
- `integration.a0_world_physics_sync`：**94/3**。
- 另A01 **63/0**、integration-authority **65/0**、save-roundtrip **41/0**。这些是根运行，本分项已核对两失败probe的原始FAIL行，未重复执行。

**不能将这十个FAIL全部归为旧测试误判。** 元数据probe的7项中，4项是旧source/display-ID等式、1项是无观测信号被要求可见；另2项是真实HUD文本泄露，必须保留红灯并修消费者。world-sync的3项则均来自旧玩家plot全真值假设。

## 2. 元数据probe：保留内部权威与匿名化强度，追溯到正确owner

当前 `shell_binder.gd:563–577` 的正常refresh已选择 `_build_contacts_from_intel(_intel_owner())`；`:606–655`从该owner的`intel_view`构造contacts，使用匿名 `TRACK-nnn`，另保留内部`track_id`/`entity_id`及`intel_owner_id`。因此 `a1_entity_metadata_authority_probe.gd:648–649` 强制 `display_source==track` 和 `display_id==track_id` 不再成立；本轮内部track_id恰为`harmattan`/`l1_station`，恢复这个等式反而会将内部目标名放进显示。

| 当前断言/行为 | 等强度修正要求 |
|---|---|
| `display_source==track` | 在正常A01路径明确预期`intel_view`，同时验证row.intel_owner_id等于Binder可信本舰owner、row.track_id能在**该owner**的intel_view.tracks.id中找到，内容/时间与该证据一致。不能只改成`source in [track,intel_view,...]`而不追溯owner |
| `display_id==track_id` | 改为显示ID是安全匿名标签、无实体名/batch/class/side等未获证据真值；内部track_id/entity_id另按授权观测与合法映射核对。不得要求把显示ID写回内部ID，也不能因匿名化删除真实选择/通信/传感器引用 |
| `contacts非空`及按7个scenario实体查contacts | 完整7实体的metadata/ballistics内部权威检查保留。玩家contacts的期望集合另从当前owner视图导出；owner无观测时允许空，但必须增加**确有合法观测时出现对应contact**的正例，不能靠空结果跳过所有显示断言 |
| 只检查安全字段/`source`标签 | 增加三个owner已知集合不同的对照；盟军独有且未共享的数据不得进玩家contacts/list/selected；合法到达接收方后才可出现。将同一合法观测保持不变而实际变更隐藏真值，玩家视图仍不变。前置断言证明内部真值确已变化，避免空钩子自比较 |
| HUD操作内部目标与显示文本 | 保留`:570–603`对comms/ident/optical内部target、internal_track_id不变的检查，保留`:607–618`对实际文本无真值和使用安全显示的检查。内部可用稳定ID不等于允许将其渲染给玩家 |

无需改静态真值的存放位置，不要求把catalog静态字段复制到PhysicsWorld或玩家track。facility_registry例外若保留，应仍有明确公开注册表来源和对应记录；不能把无owner证据的全局实体通过“设施例外”补回contacts。

### 2.1 两个HUD光学FAIL是实际实现缺陷，不能放宽测试

本轮日志实际为：

```text
HUD optical_entity contains no truth: harmattan
text=ENTITY/TRACK TRACK-001 · TRACK harmattan
HUD optical_entity contains no truth: l1_station
text=ENTITY/TRACK TRACK-002 · TRACK l1_station
```

`game_v17/scripts/ui/v1_hud.gd:643–649` 的 `_optical_entity_line`虽使用安全display_id作为第一段，却又将`tr.track_id`或`row.track_id`拼成`TRACK <tid>`，被实际界面调用（`:2564`）和`hud_target_texts`使用。这会泄露新的内部ID。

**最小收尾**：该人类可见标签使用安全显示标识/已获证据，而内部路由ID仍保留在非显示字段和操作调用中。保留两条`contains no truth`负例，修后还要证明内部track_id/entity_id未被改写。不能将`harmattan/l1_station`加入允许文本，也不能放宽`_contains_truth`来换绿。

### 2.2 SIGNAL旧断言要换成“无证据不显示”，再保留匿名显示正对照

`a1_entity_metadata_authority_probe.gd:319–347`只是`signal_upsert_target`登记含真值元数据的目标，随后refresh就要求玩家contact存在。登记世界/服务目标本身不是该owner收到观测；正常A01隔离下不出现是正确负例。

修正为：此注册操作**不产生玩家可见contact/selected/plot**；然后用受支持的合法owner观测/到达入口建立一个明确已知对象，验证实际contact/HUD匿名显示仍不含signal目标的TRUTH名称、batch、class、side，并保留内部目标引用。若没有本阶段信号到达运行链，可用已支持的合法观测作消费者正对照，同时保留信号formatter的隔离fixture；应注明证据范围，不能将“没有观测”的目标重新补入玩家列表。无需新增AI或EW消费者。

## 3. world-physics probe：内部运动学权威继续严格，玩家plot另验情报边界

旧probe `a0_world_physics_sync_probe.gd:308–329`要求Binder玩家plot：source=physics、至少全部7真值实体、harmattan坐标等于**当前**physics减apsis。本轮plot source=intel、0行，三个FAIL都来自这一个旧假设；不应要求生产代码退回全真值UI。

`shell_binder.gd:1612–1632`已委托当前owner的`session.plot_positions(owner)`，无情报即空，不回退physics；`authority_intel.gd:380–391`从owner已获得航迹的pos_km/last_observed_t生成plot。这与56 R2分方可见性相符，但也需要新的有效正例证明不是永远返回空。

**内部对照保留原强度：**

- 原真实入口、scenario实体完整清点、PhysicsWorld/WorldState存在性；
- boot及10次tick后内部snapshot/world副本与PhysicsWorld位置/速度同刻一致；原bary_rot、km、km/s、位置`1e-9 km`、速度`1e-12 km/s`、时刻`1e-6 s`不放宽；
- updated/mismatched同步语义、真实移动不再停在seed旧值；
- save/load的内部几何一致、save不推进时间；手写world不反向覆盖physics、tick边界副本自愈、重复snapshot确定性。

这部分可继续用受信测试读取内部`physics_state/physics_positions/snapshot`作oracle；不是把内部snapshot强塞给玩家。若步骤5仍需要“内部消费者来自physics”的断言，可核对内部ballistics/geometry读取与同tickphysics，别用玩家Binder plot代替。

**玩家plot新正负对照：**

1. 明确可信本舰owner，取得该owner的intel_view作为可见集合来源；每个plot点必须能映射到该owner已获得且包含位置的观测航迹，位置/observed_t与它一致。source=intel是该路径的精确预期，不是允许随意标source字符串。
2. 无观测owner为空；仅盟军知道的对象不因物理世界或全局TrackTable存在就进入玩家plot；输入非法/未到达/未授权共享不得造成玩家可见变化。
3. 对一个合法无噪声观测固定pos_km和observed_t，证明接收后玩家plot确实出现/更新，再实际移动隐藏目标的当前physics而不提供新观测，plot仍保留已知采样内容；内部world↔physics对照应随真实运动更新。之后只有合法新观测到达才更新玩家plot。
4. 玩家几何比较依据观测数据/显式坐标变换，不能用当前truth代替旧观测，也不把旧`physics-apsis`相对坐标公式硬套到当前owner plot。若UI决定使用相对坐标，需声明参考点来源/时间并从获准数据推导。有噪声观测按误差模型，不要求航迹逐位等于truth。

上述替换同时堵住“UI全知”和“UI永远空”的两种退化，保持内部物理精度与单向权威原门槛。

## 4. 返修证据要求

在原#58/PR66内逐条列出旧断言→新契约→新正例/负例→实际结果，不另开功能卡；metadata/HUD源与worldsync断言变更分别附diff说明。不要将这两项新FAIL写入7项历史baseline，不删probe、不从matrix移走、不将source集合放宽充当唯一修复。A1的两个实际光学文本泄露先修真实消费者，再更新不再适用的ID/source断言。

执行两个probe并保留新计数/原日志，再做C回归。断言数可因等强度新正负例增加而改变，但应说明变更；不能自动刷新期望数字消红。A01的63/0不替代这两个消费者回归。

## 5. 原发射十组复跑：保持绿，不再返工

本分项原样执行 `../fire/fire_context_audit.gd`，退出0；完整JSON/log在同目录fire。

- 合法control：正常TIGHT、真实FIRE授权、有限8枚导弹，实际成功，库存8→7、1弹体、1成功事件。
- 其余9组：未知/敌/盟/其他本方无运行态、敌actor、错controller、错fleet、legacy带敌actor、第二舰配置runtime=true，均被拒绝，库存8→8、0弹体、0成功事件。
- 原请求来源、配置bool借旗舰账本反例保持关闭。成功context字段现有；本分项不重新开展恢复强校验或扩大新变体，不因此宣告整个A01已放行。

全程没有修改正式生产或测试文件，也未写GitHub。
