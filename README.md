# tmuxSetting

tmux-pane-notify 一键配置：在 tmux 中实现 pane 级命令完成提醒与全局状态监控。

## 功能

- **pane 边框实时状态**：每个 pane 顶部边框显示当前状态（空闲 / ⏳ running / ✅ done）
- **命令完成提醒**：命令耗时 ≥ 阈值（默认 5s）时，pane 标题变为 `✅ done <命令> (耗时)`，
  并发送裸 BEL —— 后台 window 在状态栏出现 `!` 标记（切过去才消失）+ 终端响铃
- **全局监控面板**（tmux 3.2+）：`prefix + t` 弹出树状面板（会话 → 窗口 → pane），
  按 ✅ done（待认领）/ 🤖 agent / ⏳ running / idle 分区，1 秒自动刷新
- **AI agent 识别**：pane 前台命令命中白名单（opencode / claude / codex 等）时归入 🤖 agent 分区，
  白名单可用环境变量 `TPN_AGENT_CMDS` 扩展（node/bun 不进默认名单，防止 dev server 误判）
- **安全与幂等**：首次安装自动备份原配置（`.tpn.bak`）；标记块幂等重写支持升级；冲突检测（已有同名 tmux 选项 / 标题写入配置）

## 安装 / 使用 / 卸载

```bash
bash tmuxSetting.sh             # 安装/升级(幂等)
bash tmuxSetting.sh --uninstall # 卸载(只移除标记块与面板目录, 其余配置保留)
```

安装后：

1. 在 tmux 的 pane 里执行 `exec zsh`（或重开 shell）让 hook 生效
2. 跑超过阈值的命令结束后即触发提醒；阈值在 `~/.zshrc` 中改 `TMUX_PANE_NOTIFY_MIN_SEC`
3. tmux 3.2+ 按 `prefix + t` 打开全局 pane 监控面板（覆盖内置时钟）
4. opencode 等 agent 的"一轮问答结束"推送增强方案见 [doc/agent-notify/](doc/agent-notify/README.md)

## 依赖

- zsh + tmux 3.0a+
- tmux 3.2+ 额外获得 prefix+t 监控面板（display-popup）

## 文档

- [doc/tmux-cheatsheet.md](doc/tmux-cheatsheet.md) — tmux 常用快捷键速查
- [doc/agent-notify/README.md](doc/agent-notify/README.md) — AI agent 完成提醒总览（按 agent 拆分）
  - [opencode.md](doc/agent-notify/opencode.md) — opencode（已整理）
  - [claude-code.md](doc/agent-notify/claude-code.md) — claude code（待补充）
  - [codex.md](doc/agent-notify/codex.md) — codex（待补充）
