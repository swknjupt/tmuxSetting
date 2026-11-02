# claude code 完成提醒（待补充）

方案方向：通过 hooks（`Stop` = 回合结束，`Notification` = 需要输入/授权）在
`~/.claude/settings.json` 中挂脚本，经 pane tty 写入 **标题 + 裸 BEL**
（统一信号协议见总览 [README.md](README.md)）。

> 具体配置与脚本待补充。接入后请按总览的通用验证清单验收。
