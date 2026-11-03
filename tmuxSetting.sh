#!/usr/bin/env bash
# tmux-pane-notify 一键配置
# 功能: pane 边框实时显示状态; 命令耗时 >= 阈值时, 该 pane 标题变为 "✅ done",
#       并发送裸 BEL: 后台 window 在状态栏出现 '!' 标记(切过去才消失) + 终端响铃。
#       注: 完成时若该 window 正被查看, tmux 按设计不置位 '!'(边框标题仍显示 ✅)
#       监控面板按前台命令识别 AI agent(opencode 等), 归入 🤖 agent 分区(不被误显示为 idle)
#       Codex 通过 lifecycle hooks 实现回合级 done, 同一 window 的多个 pane 独立提醒
# 依赖: zsh + tmux (3.0a+); tmux 3.2+ 额外获得 prefix+t 全局状态面板(覆盖内置时钟);
#       Codex 回合提醒需要支持 lifecycle hooks 的 Codex(未安装时自动跳过)
# 用法: bash tmuxSetting.sh             安装/升级(幂等)
#       bash tmuxSetting.sh --uninstall 卸载(移除本工具标记块、hooks 与面板目录)
# 幂等: 重复执行会移除旧配置块后重新写入(支持升级); 首次安装自动备份原文件

set -euo pipefail

MARK="# >>> tmux-pane-notify >>>"
END_MARK="# <<< tmux-pane-notify <<<"
CODEX_MARK="# >>> tmux-pane-notify codex hooks >>>"
CODEX_END_MARK="# <<< tmux-pane-notify codex hooks <<<"
LEGACY_CODEX_MARK="# >>> tmux-pane-notify codex >>>"
LEGACY_CODEX_END_MARK="# <<< tmux-pane-notify codex <<<"
MIN_SEC="${TPN_MIN_SEC:-5}"
ACTION="install"
case "${1:-}" in
  --uninstall|uninstall|-u) ACTION="uninstall" ;;
  "") ;;
  *) echo "未知参数: $1 (仅支持 --uninstall)"; exit 1 ;;
esac

warn() { printf '\033[33m[warn]\033[0m %s\n' "$1"; }

TMUX_SOCKET=()
[[ -n "${TMUX:-}" ]] && TMUX_SOCKET=(-S "${TMUX%%,*}")
tmux_current() { tmux "${TMUX_SOCKET[@]}" "$@"; }

strip_marked_block() {  # $1=文件 $2=起始标记 $3=结束标记
  local file="$1" start="$2" end="$3"
  [[ -f "$file" ]] || return 0
  grep -qF "$start" "$file" || return 0
  awk -v s="$start" -v e="$end" '$0 ~ s, $0 ~ e {next} 1' "$file" > "$file.tpn.tmp"
  mv "$file.tpn.tmp" "$file"
}

strip_block() { strip_marked_block "$1" "$MARK" "$END_MARK"; }

has_codex_block() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  grep -qF -e "$CODEX_MARK" -e "$LEGACY_CODEX_MARK" "$file"
}

strip_codex_blocks() {
  local file="$1"
  strip_marked_block "$file" "$CODEX_MARK" "$CODEX_END_MARK"
  strip_marked_block "$file" "$LEGACY_CODEX_MARK" "$LEGACY_CODEX_END_MARK"
}

backup_on_first() {  # $1=原文件 $2=备份路径; 仅"首次安装"(无标记)且备份不存在时备份, 升级永不覆盖旧备份
  local file="$1" bak="$2"
  [[ -f "$file" ]] || { echo "[info] $file 不存在, 将新建(卸载时会一并删除)"; return 0; }
  grep -qF "$MARK" "$file" && return 0
  [[ -f "$bak" ]] && return 0
  cp "$file" "$bak"
  echo "[ ok ] 首次安装: 已备份 $file → $bak"
}

backup_once() {  # $1=原文件 $2=备份路径; 已安装路径也确保补齐首次备份
  local file="$1" bak="$2"
  [[ -f "$file" ]] || return 0
  [[ -f "$bak" ]] && return 0
  cp "$file" "$bak"
  echo "[ ok ] 已备份 $file → $bak"
}

detect_conf_tmux() {  # 冲突检测: 已有同名 tmux 选项(仅首次安装提示)
  [[ -f "$HOME/.tmux.conf" ]] || return 0
  grep -qF "$MARK" "$HOME/.tmux.conf" && return 0
  local body opt line
  body=$(awk -v s="$MARK" -v e="$END_MARK" '$0 ~ s, $0 ~ e {next} 1' "$HOME/.tmux.conf")
  for opt in pane-border-status pane-border-format monitor-activity visual-activity visual-bell; do
    line=$(grep -m1 -E "^[[:space:]]*(set(-option)?[[:space:]]+-g[[:space:]]+)?${opt}[[:space:]]" <<< "$body" || true)
    [[ -n "$line" ]] && warn "检测到已有设置将被覆盖: ${line}  ← 本工具会在文件末尾设同名选项(后写生效)"
  done
  return 0
}

detect_conf_zsh() {  # 冲突检测: 标题写入权之争(仅首次安装提示)
  [[ -f "$HOME/.zshrc" ]] || return 0
  grep -qF "$MARK" "$HOME/.zshrc" && return 0
  local hits
  hits=$(grep -nE '\\e\](0|2);|\\033\](0|2);|powerlevel10k|set-title|precmd.*title' "$HOME/.zshrc" 2>/dev/null | grep -vF "$MARK" | head -3 || true)
  [[ -n "$hits" ]] && warn "检测到可能写终端标题的配置(会与 pane 标题争抢, 症状: 标题闪烁/✅ 被冲掉):
$hits"
  return 0
}

# ---------- 卸载 ----------
if [[ "$ACTION" == "uninstall" ]]; then
  echo "== 卸载 tmux-pane-notify =="
  for f in "$HOME/.tmux.conf" "$HOME/.zshrc"; do
    if grep -qF "$MARK" "$f" 2>/dev/null; then
      strip_block "$f"
      echo "[ ok ] 已移除 $f 中的配置块"
      # 安装时新建的文件(无备份且删块后为空) → 一并删除, 还原"不存在"状态
      if [[ ! -f "${f}.tpn.bak" ]] && ! grep -q '[^[:space:]]' "$f" 2>/dev/null; then
        rm -f "$f"
        echo "[ ok ] $f 为安装时新建, 已一并删除"
      fi
    else
      echo "[skip] $f 中无本工具配置块"
    fi
  done
  CODEX_CONF="$HOME/.codex/config.toml"
  if has_codex_block "$CODEX_CONF"; then
    strip_codex_blocks "$CODEX_CONF"
    echo "[ ok ] 已移除 $CODEX_CONF 中的 Codex hooks"
    if [[ ! -f "${CODEX_CONF}.tpn.bak" ]] && ! grep -q '[^[:space:]]' "$CODEX_CONF" 2>/dev/null; then
      rm -f "$CODEX_CONF"
      echo "[ ok ] $CODEX_CONF 为安装时新建, 已一并删除"
    fi
  else
    echo "[skip] $CODEX_CONF 中无本工具 Codex hooks"
  fi
  if [[ -d "$HOME/.tmux-pane-notify" ]]; then
    rm -rf "$HOME/.tmux-pane-notify"
    echo "[ ok ] 已删除 $HOME/.tmux-pane-notify/"
  fi
  STATE_DIR="/tmp/tmux-pane-notify-$(id -u)"
  if [[ -d "$STATE_DIR" ]]; then
    for pid_file in "$STATE_DIR"/*.watch.pid; do
      [[ -f "$pid_file" ]] || continue
      watcher_pid="$(<"$pid_file")"
      [[ "$watcher_pid" =~ ^[0-9]+$ ]] && kill "$watcher_pid" 2>/dev/null || true
    done
    rm -rf "$STATE_DIR"
    echo "[ ok ] 已删除 $STATE_DIR/"
  fi
  if tmux_current list-sessions >/dev/null 2>&1; then
    while IFS= read -r pane_id; do
      [[ -n "$pane_id" ]] || continue
      tmux_current set-option -p -u -t "$pane_id" @tpn_state 2>/dev/null || true
      tmux_current set-option -p -u -t "$pane_id" @tpn_done_at 2>/dev/null || true
    done < <(tmux_current list-panes -a -F '#{pane_id}' 2>/dev/null)
    tmux_current source-file "$HOME/.tmux.conf" 2>/dev/null && echo "[ ok ] tmux 配置已热加载"
    tmux_current unbind-key t 2>/dev/null || true
    tmux_current unbind-key T 2>/dev/null || true
    tmux_current set -g pane-border-status off 2>/dev/null || true
    echo "[info] 运行中 server 已解绑并尽量还原; 如曾有自定义同名选项, 重启 tmux server 后为完全干净状态"
  else
    echo "[info] tmux 未运行, 卸载即完全生效"
  fi
  echo
  echo "完成。备注:"
  echo "  - 已开 pane 里的 zsh hook 需 exec zsh 才会消失"
  echo "  - 首次安装的备份保留在 ~/.tmux.conf.tpn.bak / ~/.zshrc.tpn.bak / ~/.codex/config.toml.tpn.bak"
  echo "    (如需逐字节还原可手动 cp 回去; 确认无误后可自行删除)"
  exit 0
fi

# ---------- 安装/升级 ----------
[[ -n "${ZSH_VERSION:-}" ]] && { echo "请在 bash 下运行本脚本(它会写 .zshrc)"; exit 1; }
[[ -f "$HOME/.zshrc" ]] || { echo "未找到 ~/.zshrc"; exit 1; }

# Codex 配置使用内联 hooks；同一目录同时存在 hooks.json 时先拒绝，避免混用两种表示。
CODEX_INTEGRATION=0
if command -v codex >/dev/null 2>&1; then
  if [[ -f "$HOME/.codex/hooks.json" ]]; then
    echo "检测到 ~/.codex/hooks.json。为避免同时使用 hooks.json 与内联 hooks，安装已中止。"
    echo "请先将本工具的 UserPromptSubmit/Stop/Interrupt hooks 合并到 hooks.json，或移除该文件后重试。"
    exit 1
  fi
  CODEX_INTEGRATION=1
else
  echo "[info] 未检测到 codex，跳过 Codex hooks 配置"
fi

# 首次安装备份(升级路径不覆盖旧备份)
backup_on_first "$HOME/.tmux.conf" "$HOME/.tmux.conf.tpn.bak"
backup_on_first "$HOME/.zshrc"     "$HOME/.zshrc.tpn.bak"
if [[ "$CODEX_INTEGRATION" -eq 1 ]]; then
  backup_once "$HOME/.codex/config.toml" "$HOME/.codex/config.toml.tpn.bak"
fi

# 冲突检测(仅首次安装提示; 升级路径视为已接受)
detect_conf_tmux
detect_conf_zsh

# ---------- 1. tmux 配置 ----------
mkdir -p "$HOME/.tmux-pane-notify"
cat > "$HOME/.tmux-pane-notify/panel.sh" <<'EOF'
#!/usr/bin/env bash
# 全局 pane 实时监控面板 (tmux 3.2+ display-popup 内运行)
# 树状: 状态分区(✅ done / 🤖 agent / ⏳ running / idle) → 会话 → 窗口 → pane; 区内按完成时间倒序(新→旧)
# 1 秒自动刷新, 按任意键退出

C_G=$'\e[32m'; C_Y=$'\e[33m'; C_M=$'\e[35m'; C_C=$'\e[36m'; C_D=$'\e[2m'; C_R=$'\e[0m'
# AI agent 识别: pane 前台命令(pane_current_command)精确匹配白名单 → 🤖 agent 分区
# (✅ done 标题优先 → Codex 回合结束后进入待认领区, 而不是继续显示为运行中)
# 注: node/bun 等解释器名不进默认白名单, 以免把 dev server 误判为 agent;
#     node 系 CLI(gemini-cli 等前台命令显示为 node)可扩展: export TPN_AGENT_CMDS="opencode node"
AGENT_CMDS="${TPN_AGENT_CMDS:-opencode claude codex gemini aider crush droid}"
# socket 选择: TMUX env 优先(pane 内运行); 否则若仅存在一个 socket 则用之(兼容 -L); 最后默认
SOCK=()
[ -n "${TMUX:-}" ] && SOCK=(-S "${TMUX%%,*}")
if [ ${#SOCK[@]} -eq 0 ]; then
  d="/tmp/tmux-$(id -u)"
  [ "$(ls "$d" 2>/dev/null | wc -l)" -eq 1 ] && SOCK=(-S "$d/$(ls "$d")")
fi
t() { tmux "${SOCK[@]}" "$@"; }
STATE_DIR="/tmp/tmux-pane-notify-$(id -u)"

while true; do
  RECS=''; nd=0; nr=0; ni=0; na=0
  # pane_title 放最后：Codex 标题可能包含 '|'，不能放中间破坏字段解析。
  while IFS='|' read -r cmd sess win wname pidx act state done_at server_pid pane_id title; do
    [ -z "$sess" ] && continue
    state_file="$STATE_DIR/${server_pid}-${pane_id#%}.state"
    if [ -f "$state_file" ]; then
      IFS='|' read -r file_state file_done_at < "$state_file" || true
      case "$file_state" in
        done|working) state="$file_state"; done_at="$file_done_at" ;;
      esac
    fi
    st=''
    display="$title"
    is_agent=0
    for a in $AGENT_CMDS; do
      if [ "$cmd" = "$a" ]; then is_agent=1; break; fi
    done
    if [ "$state" = "done" ] && [ "$is_agent" -eq 1 ]; then
      st=done; nd=$((nd+1))
      display="✅ done codex ${done_at:-unknown}"
    elif [ "$is_agent" -eq 1 ]; then
      st=agent; na=$((na+1))
    else
      case "$title" in
        "✅ done"*) st=done; nd=$((nd+1)) ;;
        ⏳*)        st=run;  nr=$((nr+1)) ;;
        *)          st=idle; ni=$((ni+1)) ;;
      esac
    fi
    # 完成时间键: Codex 优先用 pane 用户变量，其他任务解析标题尾部。
    tk=0
    time_text="$title"
    [ "$state" = "done" ] && [ "$is_agent" -eq 1 ] && time_text="$done_at"
    [[ "$time_text" =~ ([0-9]{1,2}):([0-9]{2})(:([0-9]{2}))?[[:space:]]*$ ]] && \
      tk=$(( 10#${BASH_REMATCH[1]}*3600 + 10#${BASH_REMATCH[2]}*60 + 10#${BASH_REMATCH[4]:-0} ))
    RECS+="${st}|${sess}|${win}|${wname}|${tk}|${pidx}|${act}|${display}"$'\n'
  done < <(t list-panes -a -F '#{pane_current_command}|#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{?pane_active,▶,}|#{@tpn_state}|#{@tpn_done_at}|#{pid}|#{pane_id}|#{pane_title}' 2>/dev/null)

  printf '\e[H\e[2J'
  printf '%s tmux pane 监控  %s共%d | %s✅ done %d%s | %s🤖 agent %d%s | %s⏳ running %d%s | idle %d   %s%s\n\n' \
    "$C_D" "$C_R" $((nd+nr+ni+na)) "$C_G" "$nd" "$C_R" "$C_M" "$na" "$C_R" "$C_Y" "$nr" "$C_R" "$ni" "$(date +%H:%M:%S)" "$C_R"

  # 渲染状态分区: $1=state $2=标题 $3=颜色; 区内 会话→窗口→pane 树状, 完成时间倒序
  section() {
    local st="$1" label="$2" color="$3" sess win first=1
    local sessions wins
    sessions=$(printf '%s\n' "$RECS" | grep -F "${st}|" | awk -F'|' '{v=$5+0; k=$2; if(v>m[k])m[k]=v} END{for(k in m) printf "%d\t%s\n", m[k], k}' | sort -k1,1nr -k2,2 | cut -f2)
    [ -z "$sessions" ] && return 0
    printf '%s%s%s\n\n' "$color" "$label" "$C_R"
    while IFS= read -r sess; do
      [ -z "$sess" ] && continue
      printf ' ▾ %s%s%s\n' "$C_C" "$sess" "$C_R"
      wins=$(printf '%s\n' "$RECS" | grep -F "${st}|${sess}|" | awk -F'|' '{v=$5+0; k=$3; if(v>m[k])m[k]=v} END{for(k in m) printf "%d\t%s\n", m[k], k}' | sort -k1,1nr -k2,2 | cut -f2)
      while IFS= read -r win; do
        [ -z "$win" ] && continue
        wname=$(printf '%s\n' "$RECS" | grep -F "${st}|${sess}|${win}|" | head -1 | cut -d'|' -f4)
        printf '    ▾ %s[%s] %s%s\n' "$C_D" "$win" "$wname" "$C_R"
        while IFS='|' read -r st_ se wi wn tk pidx act title; do
          printf '        %s  %s%s%s' "$pidx" "$color" "$title" "$C_R"
          [ -n "$act" ] && printf ' %s▶%s' "$C_Y" "$C_R"
          printf '\n'
        done < <(printf '%s\n' "$RECS" | grep -F "${st}|${sess}|${win}|" | sort -t'|' -k5,5nr -k6,6n)
        printf '\n'
      done <<< "$wins"
    done <<< "$sessions"
  }

  section done  "✅ done (待认领)"  "$C_G"
  section agent "🤖 agent (运行中)" "$C_M"
  section run   "⏳ running"        "$C_Y"
  section idle  "idle"              "$C_D"

  printf '\n%s按任意键关闭 · 1s 自动刷新%s\n' "$C_D" "$C_R"
  read -t 1 -n 1 -s && exit 0
done
EOF
chmod +x "$HOME/.tmux-pane-notify/panel.sh"

if [[ "$CODEX_INTEGRATION" -eq 1 ]]; then
  cat > "$HOME/.tmux-pane-notify/codex-notify.sh" <<'EOF'
#!/usr/bin/env bash
# Codex lifecycle hook -> tmux pane 状态 + 标题 + BEL
# 用法: --turn-start | --turn-stop | --turn-interrupt
# 优先读取环境变量；缺失时从祖先进程环境或 zsh 写入的 PID 映射恢复。

set -euo pipefail
umask 077

MODE="${1:-}"
case "$MODE" in
  --turn-start|--turn-stop|--turn-interrupt) ;;
  *) exit 2 ;;
esac

# Stop hook 退出 0 时必须返回合法 JSON；无法提醒也不应打断 Codex。
finish_with_json() {
  [[ "$MODE" == "--turn-stop" ]] && printf '{}\n'
  exit 0
}

state_dir="/tmp/tmux-pane-notify-$(id -u)"
log_hook() {
  mkdir -p "$state_dir" 2>/dev/null || return 0
  printf '%s|%s|pid=%s|ppid=%s\n' \
    "$(date '+%F %T')" "$1" "$$" "$PPID" >> "$state_dir/hook.log" 2>/dev/null || true
}

TMUX="${TMUX:-${TPN_CODEX_TMUX:-}}"
TMUX_PANE="${TMUX_PANE:-${TPN_CODEX_PANE:-}}"

resolve_tmux_context() {
  local pid="$PPID" item stat_line map_file
  local -a stat_fields
  for _ in {1..16}; do
    [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] || break
    map_file="$state_dir/shell-$pid.map"
    if [[ -r "$map_file" ]]; then
      IFS='|' read -r TMUX TMUX_PANE < "$map_file" || true
      [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] && return 0
    fi
    if [[ -r "/proc/$pid/environ" ]]; then
      while IFS= read -r -d '' item; do
        case "$item" in
          TMUX=*) [[ -n "${TMUX:-}" ]] || TMUX="${item#TMUX=}" ;;
          TMUX_PANE=*) [[ -n "${TMUX_PANE:-}" ]] || TMUX_PANE="${item#TMUX_PANE=}" ;;
        esac
      done < "/proc/$pid/environ"
      [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] && return 0
    fi
    stat_line="$(<"/proc/$pid/stat")" 2>/dev/null || break
    stat_line="${stat_line##*) }"
    read -r -a stat_fields <<< "$stat_line"
    pid="${stat_fields[1]:-}"
  done
  return 1
}

if [[ -z "${TMUX:-}" || -z "${TMUX_PANE:-}" ]]; then
  resolve_tmux_context || {
    log_hook "event=$MODE unresolved-tmux"
    finish_with_json
  }
fi
SOCK=(-S "${TMUX%%,*}")
t() { tmux "${SOCK[@]}" "$@"; }
tmux_meta="${TMUX#*,}"
server_pid="${tmux_meta%%,*}"
state_file="$state_dir/${server_pid}-${TMUX_PANE#%}.state"

write_state() {
  local state="$1" done_at="$2" tmp
  mkdir -p "$state_dir" 2>/dev/null || return 1
  tmp="$state_file.$$.tmp"
  printf '%s|%s\n' "$state" "$done_at" > "$tmp" 2>/dev/null || return 1
  mv -f "$tmp" "$state_file" 2>/dev/null || {
    rm -f "$tmp"
    return 1
  }
}

set_pane_state() {
  t set-option -p -t "$TMUX_PANE" @tpn_state "$1" 2>/dev/null || true
}

clear_done_at() {
  t set-option -p -u -t "$TMUX_PANE" @tpn_done_at 2>/dev/null || true
}

case "$MODE" in
  --turn-start)
    write_state working "" || log_hook "event=$MODE state-write-failed"
    set_pane_state working
    clear_done_at
    title="⏳ codex"
    ;;
  --turn-stop)
    done_at="$(date +%H:%M:%S)"
    write_state done "$done_at" || log_hook "event=$MODE state-write-failed"
    t set-option -p -t "$TMUX_PANE" @tpn_done_at "$done_at" 2>/dev/null || true
    set_pane_state done
    title="✅ done codex $done_at"
    ;;
  --turn-interrupt)
    write_state working "" || log_hook "event=$MODE state-write-failed"
    set_pane_state working
    clear_done_at
    title="⏳ codex (interrupted)"
    ;;
esac

if ! t select-pane -t "$TMUX_PANE" -T "$title" 2>/dev/null; then
  finish_with_json
fi

if [[ "$MODE" == "--turn-stop" ]]; then
  tty="$(t display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null || true)"
  if [[ -n "$tty" ]]; then
    # 独立裸 BEL 才会计入 tmux 活动标记并触发终端响铃。
    printf '\a' > "$tty" 2>/dev/null || true
  fi
  printf '{}\n'
fi
exit 0
EOF
  chmod +x "$HOME/.tmux-pane-notify/codex-notify.sh"

  cat > "$HOME/.tmux-pane-notify/codex-notify-watch.sh" <<'EOF'
#!/usr/bin/env bash
# 在 Codex 沙箱外运行：读取 hook 写入的状态文件，再更新 tmux 选项、标题和 BEL。
# 用法: codex-notify-watch.sh <pane-id> <TMUX-value>

set -euo pipefail
umask 077

PANE_ID="${1:-}"
TMUX_VALUE="${2:-}"
[[ -n "$PANE_ID" && -n "$TMUX_VALUE" ]] || exit 0

SOCK=(-S "${TMUX_VALUE%%,*}")
t() { tmux "${SOCK[@]}" "$@"; }
tmux_meta="${TMUX_VALUE#*,}"
server_pid="${tmux_meta%%,*}"
state_dir="/tmp/tmux-pane-notify-$(id -u)"
state_file="$state_dir/${server_pid}-${PANE_ID#%}.state"
pid_file="$state_dir/${server_pid}-${PANE_ID#%}.watch.pid"
last=''

mkdir -p "$state_dir" 2>/dev/null || exit 0
printf '%s\n' "$$" > "$pid_file" 2>/dev/null || exit 0
cleanup() { rm -f "$state_file" "$pid_file"; }
trap cleanup EXIT INT TERM

while t display-message -p -t "$PANE_ID" '#{pane_id}' >/dev/null 2>&1; do
  if [[ -f "$state_file" ]]; then
    IFS='|' read -r state done_at < "$state_file" || true
    signature="$state|$done_at"
    if [[ "$signature" != "$last" ]]; then
      case "$state" in
        done)
          [[ "$done_at" =~ ^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$ ]] || done_at="unknown"
          if t set-option -p -t "$PANE_ID" @tpn_done_at "$done_at" 2>/dev/null &&
             t set-option -p -t "$PANE_ID" @tpn_state done 2>/dev/null; then
            last="$signature"
            t select-pane -t "$PANE_ID" -T "✅ done codex $done_at" 2>/dev/null || true
            tty="$(t display-message -p -t "$PANE_ID" '#{pane_tty}' 2>/dev/null || true)"
            [[ -n "$tty" ]] && printf '\a' > "$tty" 2>/dev/null || true
          fi
          ;;
        working)
          if t set-option -p -t "$PANE_ID" @tpn_state working 2>/dev/null &&
             t set-option -p -u -t "$PANE_ID" @tpn_done_at 2>/dev/null; then
            last="$signature"
            t select-pane -t "$PANE_ID" -T "⏳ codex" 2>/dev/null || true
          fi
          ;;
      esac
    fi
  fi
  sleep 0.2
done
EOF
  chmod +x "$HOME/.tmux-pane-notify/codex-notify-watch.sh"
fi

if grep -qF "$MARK" "$HOME/.tmux.conf" 2>/dev/null; then
  echo "[update] 刷新 ~/.tmux.conf 已有配置"
else
  echo "[ ok ] 追加配置到 ~/.tmux.conf"
fi
strip_block "$HOME/.tmux.conf"
cat >> "$HOME/.tmux.conf" <<EOF

$MARK
set -g pane-border-status top
# Codex done 存在 pane 用户变量中，避免被 Codex 自身更新的 pane_title 覆盖。
set -g pane-border-format "#{pane_index} #{?#{==:#{@tpn_state},done},✅ done codex #{@tpn_done_at},#{pane_title}}#{?pane_active, ▶,}"
set -g monitor-activity on
set -g visual-activity off
set -g visual-bell off
if-shell "tmux -V | grep -qE 'tmux (3\\.[2-9]|[4-9])'" \\
  "bind-key t display-popup -w 80% -h 60% -E ~/.tmux-pane-notify/panel.sh" ""
$END_MARK
EOF

# ---------- 3. Codex hooks ----------
if [[ "$CODEX_INTEGRATION" -eq 1 ]]; then
  mkdir -p "$HOME/.codex"
  if has_codex_block "$HOME/.codex/config.toml"; then
    echo "[update] 刷新 ~/.codex/config.toml Codex hooks"
  else
    echo "[ ok ] 追加 Codex hooks 到 ~/.codex/config.toml"
  fi
  strip_codex_blocks "$HOME/.codex/config.toml"
  cat >> "$HOME/.codex/config.toml" <<EOF

$CODEX_MARK
[[hooks.UserPromptSubmit]]

[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = 'bash "\$HOME/.tmux-pane-notify/codex-notify.sh" --turn-start'
timeout = 3

[[hooks.Stop]]

[[hooks.Stop.hooks]]
type = "command"
command = 'bash "\$HOME/.tmux-pane-notify/codex-notify.sh" --turn-stop'
timeout = 3

[[hooks.Interrupt]]

[[hooks.Interrupt.hooks]]
type = "command"
command = 'bash "\$HOME/.tmux-pane-notify/codex-notify.sh" --turn-interrupt'
timeout = 3
$CODEX_END_MARK
EOF
fi

# ---------- 4. zsh hook ----------
if grep -qF "$MARK" "$HOME/.zshrc"; then
  echo "[update] 刷新 ~/.zshrc 已有配置"
else
  echo "[ ok ] 追加配置到 ~/.zshrc"
fi
strip_block "$HOME/.zshrc"
cat >> "$HOME/.zshrc" <<EOF

$MARK
if [ -n "\$TMUX" ]; then
  autoload -Uz add-zsh-hook
  TMUX_PANE_NOTIFY_MIN_SEC=$MIN_SEC
  TPN_CODEX_MANAGED=$CODEX_INTEGRATION
  TPN_CODEX_WATCH_PID=''
  export TPN_CODEX_TMUX="\$TMUX"
  export TPN_CODEX_PANE="\$TMUX_PANE"
  TPN_CODEX_STATE_DIR="/tmp/tmux-pane-notify-\$(id -u)"
  TPN_CODEX_MAP_FILE="\$TPN_CODEX_STATE_DIR/shell-\$\$.map"
  if [[ "\$TPN_CODEX_MANAGED" == 1 ]]; then
    # 共享 app-server daemon 无法归属到具体 pane，tmux 内改用 pane 自带 app-server。
    codex() { command codex --no-daemon "\$@"; }
  fi
  # 设置 pane 标题。注意: 结尾 \a 只是 OSC 结束符, tmux 不会把它当响铃
  _tpn_title() { printf '\e]2;%s\a' "\$1" }
  _tpn_clear_codex_state() {
    local tmux_meta="\${TMUX#*,}"
    rm -f "\$TPN_CODEX_STATE_DIR/\${tmux_meta%%,*}-\${TMUX_PANE#%}.state"
    command tmux set-option -p -u -t "\$TMUX_PANE" @tpn_state 2>/dev/null
    command tmux set-option -p -u -t "\$TMUX_PANE" @tpn_done_at 2>/dev/null
  }
  _tpn_stop_codex_watch() {
    local tmux_meta="\${TMUX#*,}"
    local pid_file="\$TPN_CODEX_STATE_DIR/\${tmux_meta%%,*}-\${TMUX_PANE#%}.watch.pid"
    local pid="\${TPN_CODEX_WATCH_PID:-}"
    if [[ -f "\$pid_file" ]]; then
      pid="\$(<\$pid_file)"
    fi
    if [[ "\$pid" =~ ^[0-9]+\$ ]]; then
      kill "\$pid" 2>/dev/null
    fi
    rm -f "\$pid_file"
    TPN_CODEX_WATCH_PID=''
  }
  _tpn_preexec() {
    TPN_START=\$SECONDS
    TPN_CMD="\${1[(w)1]}"
    if [[ "\$TPN_CMD" == "codex" && "\$TPN_CODEX_MANAGED" == 1 ]]; then
      _tpn_stop_codex_watch
      _tpn_clear_codex_state
      command mkdir -p "\$TPN_CODEX_STATE_DIR"
      printf '%s|%s\n' "\$TMUX" "\$TMUX_PANE" > "\$TPN_CODEX_MAP_FILE"
      if command -v setsid >/dev/null 2>&1; then
        command setsid "\$HOME/.tmux-pane-notify/codex-notify-watch.sh" \\
          "\$TMUX_PANE" "\$TMUX" </dev/null >/dev/null 2>&1 &
      else
        command nohup "\$HOME/.tmux-pane-notify/codex-notify-watch.sh" \\
          "\$TMUX_PANE" "\$TMUX" </dev/null >/dev/null 2>&1 &
      fi
      TPN_CODEX_WATCH_PID=\$!
    fi
    _tpn_title "⏳ \$TPN_CMD"
  }
  _tpn_precmd() {
    if [[ -n "\${TPN_START:-}" ]]; then
      local dur=\$(( \$SECONDS - \$TPN_START ))
      if [[ "\$TPN_CMD" == "codex" && "\$TPN_CODEX_MANAGED" == 1 ]]; then
        # Codex 回合级提醒由 hooks 负责，退出 TUI 时不再把整段会话记作 done。
        _tpn_stop_codex_watch
        _tpn_clear_codex_state
        rm -f "\$TPN_CODEX_MAP_FILE"
        _tpn_title "zsh"
      elif (( dur >= \$TMUX_PANE_NOTIFY_MIN_SEC )); then
        _tpn_title "✅ done \$TPN_CMD (\${dur}s) \$(date +%H:%M:%S)"
        # 独立裸 BEL(必须在 OSC 之外): tmux 才会置位 '!' 标记并响铃 → 跨 window 提醒
        printf '\a'
      else
        _tpn_title "zsh"
      fi
      TPN_START=
    else
      _tpn_title "zsh"
    fi
  }
  add-zsh-hook preexec _tpn_preexec
  add-zsh-hook precmd _tpn_precmd
fi
$END_MARK
EOF

# ---------- 5. 热加载 tmux 配置 ----------
# 注意: tmux server 进程 comm 为 "tmux: server", pgrep -x tmux 匹配不到;
# 用 list-sessions 探测目标 socket，即使当前没有 attached client 也能识别 server。
if tmux_current list-sessions >/dev/null 2>&1; then
  tmux_current source-file "$HOME/.tmux.conf" 2>/dev/null && echo "[ ok ] tmux 配置已热加载" \
    || echo "[warn] tmux 热加载失败, 下次启动 tmux 时生效"
else
  echo "[info] tmux 未运行, 下次启动自动生效"
fi

echo
echo "完成。使用方式:"
echo "  1. 在 tmux 的 pane 里执行: exec zsh   (或重开一个 shell) 让 hook 生效"
echo "  2. 跑超过 ${MIN_SEC}s 的命令结束后: 该 pane 边框显示 '✅ done ...';"
echo "     若在后台 window, 状态栏该 window 出现 '!' 并响铃, 切过去后自动清除"
echo "  3. 阈值可在 ~/.zshrc 中改 TMUX_PANE_NOTIFY_MIN_SEC"
echo "  4. tmux 3.2+: 按 prefix+t 弹出全局 pane 状态面板 (覆盖内置时钟; AI agent pane 归入 🤖 分区)"
if [[ "$CODEX_INTEGRATION" -eq 1 ]]; then
  echo "  5. 重启 Codex 并在首次提示时信任 UserPromptSubmit / Stop / Interrupt hooks"
  echo "     Codex 每轮完成后面板显示 ✅ done；提交下一条问题时恢复 🤖 agent"
else
  echo "  5. 安装 Codex 后重新运行本脚本即可启用 Codex 回合级提醒"
fi
echo "  6. 卸载: bash $0 --uninstall  (移除标记块、Codex hooks 与面板)"
