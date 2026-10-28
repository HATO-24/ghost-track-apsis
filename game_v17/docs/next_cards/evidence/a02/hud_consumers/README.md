# JC-A02 PR69 第二轮：两处实际 HUD 消费者收尾证据

| 文件 | 内容 |
|---|---|
| targeted-summary.json / *.log.txt | 卡指定 7 项专项全 PASS；jc_identity_pipeline **122/0**（新增真实 HUD 空映射路径与显示消费断言） |
| phase0-summary.json / phaseA-summary.json | 6/6、3/3 |
| full-summary.json | 完整 strict **89 = 82 PASS / 7 历史 FAIL，new_fail=0、drift=0、complete=true** |

R3：真实 radar→sensor 映射→实际 HUD 式 combat 空映射行→合法人工 friend→combat_identity(真实航迹键) 解析 friend 并在 request_fire 后投影；预填字段/实体键兼容正例保留。
R4：TTL 过期后 ident_view.identity=unknown+last_known_identity=friend+warn+EXPIRED 标签；普通 contacts 行同样消费有效性。不重做 TTL 算法、不强制 stale 一律 unknown。
