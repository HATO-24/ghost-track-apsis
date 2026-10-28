# 原R4实际HUD读者定位

候选：4a658699868b8d046ec5472f9c4b9ea204af6be9。动态字段见time/result.json；本项不增加生产代码，不声称真实渲染截图。

- TTL5，真实tick到11：operational effective_identity=unknown/valid=false；Binder.ident_view仍identity=friend，同时带validity=expired、effective_identity=unknown。
- shell_binder.gd:2015–2019与2027–2032新增有效性字段，后续identity仍取a.identity。
- v1_hud.gd:3651取binder.ident_view；3655取iv.identity；3699直接绘制其大写文字并按原identity着色。未读取validity/effective_identity。
- _build_contacts_from_intel仍从owner track的原identity得到联系人side/type，并把ident_view.identity放入行ident；新增有效性没有进入该普通显示决定。

因此保留raw历史值本身没有被判错；缺口是普通读者缺少有效值接入或明确失效区分。可选择显示有效unknown，或按已批准文案清楚标为最后已知/已失效，保留历史字段。此项不要求重排UI或修改已经转绿的火控TTL规则。
