# JC-A01 证据（执行基线 main 3045311 / 冻结 G0=K0=9d0f3b4）

| 文件 | 内容 |
|---|---|
| `red.stdout.txt` | **实现前红例**（授权门缺失、plot 直出真值、无 owner 隔离） |
| `red.stderr.txt` | 对应 stderr |
| `green.stdout.txt` | 实现后 `JC-A01 AUTHORITY INTEL PROBE RESULT: PASS=31 FAIL=0` |
| `jc_authority_intel.log.txt` | 经 runner 的矩阵运行日志（31/0） |
| `full-summary.json` | 全量回归摘要：88 = 81 PASS / 7 历史 FAIL，baseline new_fail=0 |

说明：红例在无球体运行态的会话下部分表现为 `no_physics_state`；但**授权门缺失**本身由
探针断言记录（未知 shooter 未返回授权拒绝原因、legacy 无锚点校验），修复后转为授权语义拒绝。
