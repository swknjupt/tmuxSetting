# tmux 常用快捷键速查

> 默认前缀键（prefix）为 `C-b`（按住 `Ctrl` + `b`，松开后再按后续键）。
> 下文用 `prefix` 表示先按 `C-b`，再用 `|` 分隔的按键表示可选写法。

## 目录

- [会话管理](#会话管理)
- [窗口管理](#窗口管理)
- [窗格（Pane）管理](#窗格pane管理)
- [复制模式](#复制模式)
- [其他常用](#其他常用)
- [命令行（: 提示符）](#命令行-提示符)
- [本仓库自定义快捷键](#本仓库自定义快捷键)

---

## 会话管理

| 快捷键 | 说明 |
|---|---|
| `prefix d` | 分离（detach）当前会话，回到原 shell |
| `prefix s` | 交互式列出所有会话并切换 |
| `prefix $` | 重命名当前会话 |
| `prefix (` | 切换到上一个会话 |
| `prefix )` | 切换到下一个会话 |
| `prefix L` | 切换到"最近使用"的会话 |
| `prefix X`（3.2+） | 关闭当前会话（带确认） |

```bash
# shell 中常用
tmux new -s work        # 新建名为 work 的会话
tmux ls                 # 列出会话
tmux a -t work          # 接回 work 会话
tmux a -t               # 接回最近使用的会话
tmux kill-session -t work
tmux kill-server        # 关闭所有会话
```

## 窗口管理

| 快捷键 | 说明 |
|---|---|
| `prefix c` | 新建窗口 |
| `prefix ,` | 重命名当前窗口 |
| `prefix w` | 交互式列出所有窗口并切换 |
| `prefix n` / `prefix p` | 下一个 / 上一个窗口 |
| `prefix 数字` | 按编号切换窗口（0–9） |
| `prefix '` | 输入编号切换窗口 |
| `prefix &` | 关闭当前窗口（带确认） |
| `prefix .` | 修改当前窗口编号（可移动到其他会话） |
| `prefix l` | 切换到上一次使用的窗口 |

## 窗格（Pane）管理

### 创建与布局

| 快捷键 | 说明 |
|---|---|
| `prefix %` | 左右分屏 |
| `prefix "` | 上下分屏 |
| `prefix z` | 当前窗格全屏 / 还原（zoom） |
| `prefix x` | 关闭当前窗格（带确认） |
| `prefix !` | 将当前窗格拆为独立窗口 |
| `prefix Space` | 循环切换布局（even-horizontal / tiled 等） |
| `prefix Alt+1~5` | 直接切换到指定布局 |
| `prefix {` / `prefix }` | 与前 / 后一个窗格交换位置 |

### 切换与调整

| 快捷键 | 说明 |
|---|---|
| `prefix 方向键` | 按方向切换到相邻窗格 |
| `prefix o` | 按顺序切换到下一个窗格 |
| `prefix q` | 显示窗格编号，快速按数字跳转 |
| `prefix Ctrl+方向键` | 按一个单元格调整边框大小 |
| `prefix Alt+方向键` | 按五个单元格调整边框大小 |
| `prefix ;` | 跳转到上一个活跃的窗格 |

## 复制模式

| 快捷键 | 说明 |
|---|---|
| `prefix [` | 进入复制模式（可翻页浏览回滚缓冲区） |
| `prefix PgUp` | 进入复制模式并向上翻页 |
| `q` | 退出复制模式 |
| `v` | 开始选择（vi 模式） |
| `y` | 复制所选内容并退出 |
| `Enter` | 复制所选内容并退出（emacs 模式） |
| `prefix ]` | 粘贴最近一次复制的内容 |
| `prefix =` | 交互式选择粘贴缓冲区 |
| `g` / `G` | 跳到顶部 / 底部（vi 模式） |
| `/` | 向下搜索（vi 模式，`?` 向上） |
| `n` / `N` | 下一个 / 上一个搜索结果 |

> 提示：在 `~/.tmux.conf` 中设置 `setw -g mode-keys vi` 可让复制模式默认使用 vi 快捷键。

## 其他常用

| 快捷键 | 说明 |
|---|---|
| `prefix t` | 显示时钟（本仓库脚本已覆盖为状态面板） |
| `prefix ?` | 列出全部快捷键 |
| `prefix :` | 打开命令提示符 |
| `prefix r` | 常见自定义：重载配置（需自行绑定） |
| `prefix [` 后 `C-b` 再按 | 复制模式内继续滚动 |

```bash
# 重载配置（shell 或 prefix : 中均可）
tmux source-file ~/.tmux.conf
```

## 命令行（`prefix :` 提示符）

| 命令 | 说明 |
|---|---|
| `split-window -h` | 左右分屏（等价 `prefix %`） |
| `resize-pane -U 5` | 当前窗格向上扩大 5 行（-D/-L/-R 类似） |
| `swap-window -t 2` | 将当前窗口移到 2 号位 |
| `move-window -s 0 -t 3` | 移动窗口 0 到 3 |
| `set -g mouse on` | 临时开启鼠标支持（滚动/点击/拖拽分屏） |
| `display-popup -E htop` | 弹窗运行命令（3.2+） |
| `kill-pane` / `kill-window` | 关闭窗格 / 窗口 |

> 建议在 `~/.tmux.conf` 中加上 `set -g mouse on`，鼠标滚轮即可翻页、点击切窗格、拖边框调大小。

## 本仓库自定义快捷键

通过 `tmuxSetting.sh` 安装后额外获得：

| 快捷键 | 说明 |
|---|---|
| `prefix t` | 弹出全局 pane 监控面板（tmux 3.2+，覆盖内置时钟）：树状展示 会话→窗口→pane 的 ✅ done / 🤖 agent / ⏳ running / idle 状态，1 秒自动刷新，按任意键关闭 |

> AI agent pane（opencode / claude / codex 等）按前台命令自动归入 🤖 agent 分区，不会被误显示为 idle 或陈旧的 ✅ done。默认白名单：`opencode claude codex gemini aider crush droid`；可用 `TPN_AGENT_CMDS` 扩展（如 `tmux set-environment -g TPN_AGENT_CMDS "opencode node"` 后重开面板）。node/bun 默认不在名单内，以免 dev server 被误判为 agent。

其余行为无需快捷键：在 pane 中跑超过阈值的命令（默认 5s）结束后，该 pane 边框显示 `✅ done`；若在后台 window，状态栏出现 `!` 标记并响铃，切过去后自动清除。
