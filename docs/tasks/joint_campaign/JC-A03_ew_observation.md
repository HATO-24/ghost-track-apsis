# JC-A03：EW实际影响观测、航迹与火控

状态：WAIT A2；交付A3。公共规则见[总队列](../../59_联合战役Demo_R2_范围与下一批任务卡.md)。

## 1. 目标与缺口

C55的EW effect接口没有真实Sensor/Comms消费者，CombatService解算质量主要由武器精度与距离决定。把EW接进实际观测及火控，必须在相同真值、相同合法输入下看到可解释的作战差异，而非只多一个HUD状态。

## 2. 基线、依赖与范围

以已审A2/K0的40位SHA开工。范围为EW→Sensor/延迟队列→TrackTable→实际火控质量消费，以及小范围Session时序/存档接入。Comms属于A04，友军AI属B2；真实RF/光学传播研究仍为#53。不要做另一个直接写敌身份或损伤的EW系统。

## 3. 权威与数值契约

EWService写干扰运行态和抽象effect，Sensor采样并应用一次，TrackTable按owner融合，CombatService消费操作性测量质量/误差。同tick先取得规定时刻effect再生成观测；当前Session sensors先于EW，须明确调整采样顺序或提供等价时刻查询，不能双步进EW。

保留采样几何/observed_t，延迟只改变received_t与投递，不用后来的真值重新生成旧观测。`.t`等既有单调入口如何兼容由K0明确。队列按稳定次序投递并保存，质量[0,1]。以当前模型fixture：原质量1、仅noise_jam=0.5时confidence乘数0.7，误差≤1e-9；实际delay与`observation_effect`返回值一致，误差≤1e-6s。内部`_iw`也可能增加delay，不能只硬编码3s。

不能让TrackTable历史max质量吞掉当前干扰退化；区分历史证据与当前measurement quality，火控实际消费后者。冻结fixture中质量→可解算/需更久/射击误差等实际规则与阈值；不能只改显示数值。EW不直接赋阵营/权限/伤害；欺骗若生成候选证据，必须留在被影响owner并走普通验证融合，不自动成确认目标。

## 4. 实施与提交拆分

1. 红例：同seed与同观测条件开/关EW，真实Sensor与火控输出仍无差异；记录既有effect数值作为对照。
2. 接观测适配、稳定延迟队列、capture/delivery双时间及质量语义，保留未受影响链路与EW=0原行为。
3. 让实际火控消费已授权航迹质量/误差，明确不足时的拒绝/降级原因；不能拉真值补全不确定性。
4. 接保存/恢复及Session顺序，按服务、队列、消费者、集成证据分提交。只新增真实存在的运行态，不预置空AI/目标段。

## 5. 验收

EW关/开/到期/错误observer或频段、噪声/已支持的欺骗/诱饵渠道分别测；正常航迹不会被其他owner干扰篡改。检查同tick只应用一次、延迟期间不提前显示、重复消息不重复融合、旧观测不换成当前真值、质量确实影响火控结果。未支持的效果明确标限制，不以返回effect字典算已接入。

旧seed/旧档EW=0兼容；在途观测真实文件恢复并继续至少10tick，同seed队列/ID/质量/实际解算一致。无有效航迹返回不可用，不回退系统真值。几何与数值容差按公共契约，不放宽已有精度。

## 6. 命令与证据

注册`integration.jc_ew_observation`：

```powershell
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_ew_observation|ew_probe|sensor_service|track_table_probe|combat_probe|a0_(sensor_persistence|integration_authority|save_roundtrip))' -List
pwsh -NoProfile -File ./run_tests.ps1 -Only '(jc_ew_observation|ew_probe|sensor_service|track_table_probe|combat_probe|a0_(sensor_persistence|integration_authority|save_roundtrip))' -Ci -ResultsDir .test-results/jc-r2/JC-A03/targeted
```

加C回归；保留一组固定seed开/关对照，列effect采样时刻、原始/最终质量、observed/received时间、TrackTable及火控结果、恢复后10tick、退出码与断言。日志标记抽象近似模型，不声称真实RF已验证。

## 7. 旧失败

旧7失败逐项保留/解释；不以削弱默认传感器、关闭正常授权、修改baseline或删除不利观测消除失败。若#46相关航迹显示由本卡真正修复，附原case绿证据后独立调整。

## 8. 交付与复核

A3交付实际消费者表、时序/质量/延迟契约、红绿对照、保存继续证据与未支持效果清单。独立审查追踪从effect到真实观测/火控的完整链，并尝试更换owner/观测时间绕过约束。
