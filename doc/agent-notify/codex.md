# Codex 回合完成提醒

> 统一信号协议见总览 [README.md](README.md)。Codex 集成由 `tmuxSetting.sh`
> 自动配置，支持同一 window 中运行多个 Codex pane。

## 工作方式

`bash tmuxSetting.sh` 会生成 `~/.tmux-pane-notify/codex-notify.sh`，并向
`~/.codex/config.toml` 写入带标记的内联 hooks：

| Codex 事件 | pane 标题 | 提醒 |
|---|---|---|
| `UserPromptSubmit` | 状态设为 `working`，标题设为 `⏳ codex` | 不响铃，面板切回 🤖 agent |
| `Stop` | 状态设为 `done`，记录 `HH:MM:SS` | 独立 BEL；后台 window 显示 `!` |
| `Interrupt` | 状态恢复为 `working` | 不发送完成提醒 |

辅助脚本使用 Codex 进程继承的 `TMUX_PANE` 定位当前 pane，不按命令名广播。
Codex hooks 在 workspace-write 沙箱内运行，不能直接连接 tmux socket。辅助脚本
因此先把状态写入 `/tmp/tmux-pane-notify-<uid>/`；zsh 在启动 Codex 时拉起 pane
watcher，由沙箱外进程同步 `@tpn_state` / `@tpn_done_at`、边框和 BEL。
zsh 同时导出 `TPN_CODEX_TMUX` / `TPN_CODEX_PANE`，供 hook 在 `TMUX` 环境变量
被清理时恢复 pane 上下文。watcher 使用 `setsid`（或 `nohup`）脱离启动它的 shell。
tmux shell 中的 `codex` 函数会自动追加 `--no-daemon`。共享的 app-server daemon
运行在 tmux 之外，无法获知 pane；`--no-daemon` 让 hook 与当前 TUI 保持在同一进程树。

Codex 自身默认会更新终端标题（`tui.terminal_title`），可能覆盖辅助脚本写入的
`✅ done`。面板会直接读取状态文件并优先使用用户变量，所以 Codex 更新标题不会
影响 done 状态，也无需关闭 Codex 的动态标题。

## 安装步骤

1. 在 tmux pane 中运行 `bash tmuxSetting.sh`。
2. 执行 `exec zsh`（或重开 pane），然后重启 Codex；watcher 会在 Codex 启动时拉起。
3. 首次出现 hook 信任提示时，信任 `UserPromptSubmit`、`Stop` 和 `Interrupt`。
4. 用 `prefix+t` 打开面板，确认 Codex pane 出现在 🤖 agent 区。

安装器会先备份已有的 `~/.codex/config.toml` 为 `.tpn.bak`，并自动迁移旧的
`notify` 标记块。若 `~/.codex/hooks.json` 已存在，安装器会中止 Codex 配置，
避免同一配置层混用 `hooks.json` 和内联 hooks。

## 多 Pane 验证

1. 在一个 window 中开三个 pane，分别运行 `codex`。
2. 分别提交问题，确认三个 pane 都在 🤖 agent 区。
3. 等第一个回答结束：只有对应 pane 进入 done 区，并显示 `✅ done codex HH:MM:SS`。
4. 等另外两个回答结束：done 区按时间分别列出三个 pane。
5. 在其中一个 done pane 提交新问题：该 pane 恢复为运行中，其他 pane 保持 done。
6. 退出 Codex：zsh 不再把整段 Codex 会话重复记成第二个 done。

tmux 的 `!` 是 **window 级**标记。同一 window 有三个 pane 完成时只会有一个
`!`；pane 区分依靠标题和 `prefix+t` 面板。

## 故障排查

- done 不出现：确认 Codex hooks 已被信任，且进程由 tmux pane 启动。
- done 不切回运行中：重新检查 `UserPromptSubmit` hook 的信任状态。
- 无标题或 BEL：确认 `TMUX`、`TMUX_PANE` 已传给 Codex 及其 hook 子进程。
- Codex 更新标题但面板仍显示 done：属于正常行为，状态已与标题解耦。
- 面板 done 正常但边框不更新：执行 `exec zsh` 后重启 Codex，确认 watcher 已启动。
- 完全无 done：检查 `/tmp/tmux-pane-notify-<uid>/hook.log` 是否有
  `unresolved-tmux` 或 `state-write-failed`。
- tmux 内请直接输入 `codex`并使用安装后的 shell 函数；`command codex` 会绕过
  `--no-daemon` 包装。
- 安装提示 `hooks.json` 冲突：将本工具的三个 hooks 合并到该文件，或移除空文件后重跑安装。

参考：[OpenAI Codex Hooks 官方文档](https://developers.openai.com/codex/hooks)。

卸载运行 `bash tmuxSetting.sh --uninstall`，只移除本工具的标记块、
`codex-notify.sh`、watcher、状态目录和面板目录，其他 Codex 配置保持不变。
