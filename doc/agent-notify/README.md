# AI agent 完成提醒（按 agent 拆分）

> 背景：tmux-pane-notify 的提醒链路（zsh hook → pane 标题 + BEL → `!` + 响铃 + prefix+t 面板）
> 只能感知 **shell 命令边界**。opencode / claude code / codex 这类 TUI agent 的
> "一轮问答结束、等待输入"发生在单条命令内部，hook 无法感知——必须由 agent 侧发信号。

## 统一信号协议（所有 agent 通用）

agent 在"回合结束 / 需要输入"时做两件事：

1. **写 pane 标题**：`✅ done <agent名> HH:MM:SS`
   → 面板按 `✅ done` 前缀归入 done（待认领）区，按尾部 HH:MM:SS 倒序排序
2. **发裸 BEL**（必须独立于 OSC 序列之外）：tmux 才会置位 `!` 标记并响铃

注意事项：

- 防抖：同类事件 1.2s 内合并，避免连响
- 标题尾部必须是 `HH:MM(:SS)`，面板靠它解析完成时间

## 方法分层框架

| 层级 | 做法 | 经 tmux | pane 粒度（`!`） | 面板 done 区 |
|---|---|---|---|---|
| ① agent 原生通知 | 桌面通知 / 系统声音 | ❌ | ❌ | ❌ |
| ② 现成配置/插件只发 BEL | 复用 `!` + 响铃 | ✅ | ✅ | ❌ |
| ③ 自写集成（标题 + BEL） | 完整体验 | ✅ | ✅ | ✅ |

组合建议：**③ 为主 + ① 桌面兜底**。

## agent 支持矩阵

| agent | 回合结束信号 | 接入方式 | 文档 | 状态 |
|---|---|---|---|---|
| opencode | 插件事件 `session.idle` / `question.asked` / `permission.asked` / `session.error` | JS 插件 / opencode-bell / 原生 attention | [opencode.md](opencode.md) | ✅ 已整理 |
| claude code | hooks：`Stop`（回合结束）/ `Notification`（需输入） | `~/.claude/settings.json` 挂脚本（hook 进程不在 pane 前台，需经 pane tty 写入） | [claude-code.md](claude-code.md) | ⏳ 待补充 |
| codex | `notify` 外部程序（事件 `agent-turn-complete`） | `~/.codex/config.toml` | [codex.md](codex.md) | ⏳ 待补充 |
| 其他（gemini cli 等） | — | — | — | 待定 |

> 注：claude code / codex 的 hook / notify 进程**不在 pane 前台**，BEL 与标题需要先
> `tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}'` 找到 pane 的 tty 再写入；
> opencode 插件则直接写 stdout 即可。这正是按 agent 分文档的原因。

## 通用验证清单（任一 agent 接入后）

在该 agent 的 pane 里发一个简单任务 → 切到别的 window：

- [ ] 回合结束时响铃 + 该 window 状态栏出现 `!`
- [ ] pane 边框显示 `✅ done <agent名> HH:MM:SS`
- [ ] prefix+t 面板 done（待认领）区出现该 pane，按时间倒序
- [ ] （若配了①层）收到桌面通知/系统音
