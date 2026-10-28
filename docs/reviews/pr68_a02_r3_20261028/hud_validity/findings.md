# PR68 R4 普通 HUD 有效性复核

- Head: `755ab5ed629165656a566427523b01045775fc0f`
- Godot 4.7.2；诊断使用headless模式；复现时将本目录diag.gd解析为绝对路径，再传给 `--headless --path game_v17 --script <绝对脚本路径>`
- 时间：2026-10-28 17:13:12.246–17:13:15.472 Asia/Shanghai（UTC 09:13:12.246–09:13:15.472）；exit 0。
- 仅跑 t=0 有效正例、TTL5 到 t=11 失效对照及一个 stale 维度样本。没有跑 R5、正式 probe、完整 HUD 渲染或全量测试。

## 结果

有效正例 t=0：Binder `ident_view.identity=friend`；普通 contact 为 `identity=friend, side=friend, type=friendly`，`last_known_identity=friend`。

失效对照 t=11：操作性记录保留 `identity=friend` 和 `identity_state=state=expired`，同时 `validity=expired, effective_identity=unknown`。`Binder.ident_view` 返回 `identity=unknown, validity=expired, last_known_identity=friend, warn=true, tag="EXPIRED·— 0.32"`。普通 contact 返回 `identity=unknown, side=unknown, type=unknown, validity=expired, last_known_identity=friend`；其 `ident` 子项也为 unknown，并带 EXPIRED 标签和告警。火控读数为 `identity=unknown`，同时保留 `last_known_identity=friend`。

stale 样本：`identity_state=state=valid`、`validity=stale`、`valid=false`、`effective_identity=friend`；`ident_view.identity=friend` 并保留历史 friend。各字段反映评估态与时效的不同维度，没有将 stale 强制改为 unknown。

## 实际 HUD 读者核对

- 普通联系人路径由 [shell_binder.gd](https://github.com/HATO-24/ghost-track-apsis/blob/755ab5ed629165656a566427523b01045775fc0f/game_v17/scripts/ui/shell_binder.gd) 的 `_build_contacts_from_intel`（607 起）按 validity 改写 identity/side/type，并保留 last-known；把 `ident_view` 投影到 `row.ident`。过期后的三项变 unknown，身份历史留在 `last_known_identity`。
- [v1_hud.gd](https://github.com/HATO-24/ghost-track-apsis/blob/755ab5ed629165656a566427523b01045775fc0f/game_v17/scripts/ui/v1_hud.gd) 的普通 contact 绘制（949–967）根据 `type` 选行高、根据 side/type 选颜色，并直接绘制 `c.ident.tag`；`ident.warn` 会用红色。当前过期行因而绘制 unknown 类型和 EXPIRED 告警标签，不会以 friend 的有效标签显示。
- 识别详情绘制（3651、3699）从 `binder.ident_view` 读取 `identity`，再以大写值和对应身份颜色绘制；过期时读到 unknown，而不是原 friend。

## 产物

`diag.gd`、`result.json`、`run.log` 和 `run-meta.txt` 均在本目录。Godot 进程 exit 0；退出时仍输出 82 个 ObjectDB instances leaked 与 22 个 resources still in use。此次没有修改生产脚本或正式 probe；未清理引擎生成的 `.uid` 元数据。
