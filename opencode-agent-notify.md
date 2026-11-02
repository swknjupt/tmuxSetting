# opencode agent 场景的完成提醒方案

> 背景：`tmuxSetting.sh` 的提醒链路（zsh hook → pane 标题 + BEL → `!` + 响铃 + prefix+t 面板）只能感知 **shell 命令边界**。opencode 这类 TUI agent 的"一轮问答结束、等待输入"发生在**单条命令内部**，hook 无法感知——必须由 opencode 侧发信号。本文整理三种方法。

## 方法对比总览

| | ① 原生 attention 配置 | ② 现成插件 opencode-bell | ③ 自写插件 tpn-notify |
|---|---|---|---|
| 成本 | 改一行配置 | 改一行配置（npm 包） | ~30 行 JS 文件 |
| 经过 tmux 链路 | ❌ | ✅ | ✅ |
| pane 粒度定位（`!` 标记） | ❌ | ✅ + 响铃 | ✅ + 响铃 |
| 进 prefix+t 面板 done 区 | ❌ | ❌ | ✅ |
| 跨 session 桌面通知 | ✅ | ❌ | ❌ |
| 维护负担 | 无（跟版本走） | 无（第三方） | 自己持有（可随时改） |

三者不互斥，可组合：**③ 为主 + ① 桌面兜底** 是体验最完整的组合。

---

## 方法一：opencode 原生 attention 配置（与 tmux 无关）

opencode 自身行为：事件结束时**直接发系统桌面通知 + 播放系统音频**，不经过 tmux（无 pane 标题、无 `!`、面板不显示）。

```jsonc
// ~/.config/opencode/opencode.json
{
  "attention": {
    "notifications": true,   // 系统桌面通知(通常仅终端未聚焦时)
    "sound": true            // 系统音频提示音(自带音效包, 可自定义 wav)
  }
}
```

- **优点**：零代码；声音走系统音频，不受终端模拟器 bell 静音影响；通知发到桌面，**跨 session 也兜底**。
- **缺点**：只知道"opencode 完成了"，**不知道是哪个 window/pane**；焦点判定依赖焦点事件穿透 tmux（建议 `~/.tmux.conf` 加 `set -g focus-events on`），实际可能不稳定。

---

## 方法二：现成插件 opencode-bell（BEL → `!` + 响铃）

社区插件（npm：`opencode-bell`，MIT），监听事件后向 stdout 写 BEL → 复用 tmux 现有链路：后台 window 置 `!` + 终端响铃。

```jsonc
// ~/.config/opencode/opencode.json
{
  "plugin": ["opencode-bell@0.3.0"]
}
```

可选环境变量：

| 变量 | 默认 | 说明 |
|---|---|---|
| `OPENCODE_BELL_EVENTS` | 四事件全开 | `permission.asked,question.asked,session.idle,session.error` 逗号分隔挑选 |
| `OPENCODE_BELL_OUTPUTS` | `bell` | 加 `osc` 可附带 OSC 9 桌面通知（终端需支持） |
| `OPENCODE_BELL_DEBOUNCE` | `1200` | 同类事件防抖毫秒数 |

- **优点**：不写代码，5 分钟可用，自带防抖。
- **缺点**：只发 BEL 不写 pane 标题 → **面板 done 区不会出现条目**，感知靠状态栏 `!` 和响铃。

---

## 方法三：自写极简插件 tpn-notify（完整整合，推荐）

在②的基础上**同时写 pane 标题**，格式对齐面板解析规则（`✅ done` 前缀进待认领区、尾部 `HH:MM:SS` 供倒序排序），实现与 shell 长命令完全一致的体验。

```js
// ~/.config/opencode/plugins/tpn-notify.js
// tmux-pane-notify 联动: 一轮问答结束/需要输入时
//   1) 写 pane 标题 "✅ done opencode HH:MM:SS" → 面板 done(待认领)区, 按时间倒序
//   2) 发裸 BEL → tmux 后台 window 置 '!' + 终端响铃
// 生效: 放入 ~/.config/opencode/plugins/ 后重启 opencode (全局对所有项目生效)

export const TpnNotifyPlugin = async () => {
  let last = 0
  const notify = () => {
    const now = Date.now()
    if (now - last < 1200) return // 防抖: 1.2s 内多个事件合并
    last = now
    const d = new Date()
    const p = (n) => String(n).padStart(2, "0")
    const ts = `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
    process.stdout.write(`\x1b]2;✅ done opencode ${ts}\x07`) // OSC2: pane 标题
    process.stdout.write("\x07") // 裸 BEL: 必须独立于 OSC, tmux 才置 '!' 并响铃
  }
  return {
    event: async ({ event }) => {
      if (
        event.type === "session.idle" ||     // 一轮问答结束, 等待输入
        event.type === "question.asked" ||   // 向你提问
        event.type === "permission.asked" || // 请求工具授权
        event.type === "session.error"       // 出错
      ) {
        notify()
      }
    },
  }
}
```

**安装**：文件放入 `~/.config/opencode/plugins/`（全局）或项目 `.opencode/plugins/`，重启 opencode。

**达成效果**：

```
一轮问答结束(你在别的 window/会话忙别的)
 ├─ pane 边框:     ✅ done opencode 15:08:01
 ├─ prefix+t 面板: 进入 "✅ done (待认领)" 区, 按完成时间倒序
 ├─ 状态栏:        该 window 出现 '!' (切过去后消失)
 └─ 终端:          响铃
```

**已知小瑕疵**：

- 完成时若你正盯着该 pane 也会响一声（插件不知 pane 是否被查看）；
- 退出 opencode 回 shell 时，hook 会按整场会话时长再记一次 done（"二次提醒"，既有 hook 行为，暂不改动）。

---

## 与 tmux-pane-notify 三层机制的关系

| 层 | 机制 | agent 场景是否覆盖 |
|---|---|---|
| ① pane 边框标题 | zsh hook 写标题 | ❌ hook 只在 shell 边界触发 |
| ② BEL → `!` + 响铃 | hook 发裸 BEL | ❌ 同上 → **本文三法补齐** |
| ③ prefix+t 面板 | `list-panes -a` 聚合 + 前台命令识别 🤖 分区 | 显示已覆盖；**推送靠本文三法** |

## 验证清单

装好后（重启 opencode）：在 pane 里发一个简单问题 → 切到别的 window →

- [ ] 一轮回答结束时响铃 + 该 window 状态栏出现 `!`
- [ ] pane 边框显示 `✅ done opencode HH:MM:SS`
- [ ] prefix+t 面板 done（待认领）区出现该 pane，按时间倒序
- [ ] （方法一）收到桌面通知/系统音
