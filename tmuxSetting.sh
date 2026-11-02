#!/usr/bin/env bash
# tmux-pane-notify 一键配置
# 功能: pane 边框实时显示状态; 命令耗时 >= 阈值时, 该 pane 标题变为 "✅ done",
#       并发送裸 BEL: 后台 window 在状态栏出现 '!' 标记(切过去才消失) + 终端响铃。
#       注: 完成时若该 window 正被查看, tmux 按设计不置位 '!'(边框标题仍显示 ✅)
# 依赖: zsh + tmux (3.0a+); tmux 3.2+ 额外获得 prefix+t 全局状态面板(覆盖内置时钟)
# 用法: bash tmuxSetting.sh             安装/升级(幂等)
#       bash tmuxSetting.sh --uninstall 卸载(只移除标记块与面板目录, 其余配置保留)
# 幂等: 重复执行会移除旧配置块后重新写入(支持升级); 首次安装自动备份原文件

set -euo pipefail

MARK="# >>> tmux-pane-notify >>>"
END_MARK="# <<< tmux-pane-notify <<<"
MIN_SEC="${TPN_MIN_SEC:-5}"
ACTION="install"
case "${1:-}" in
  --uninstall|uninstall|-u) ACTION="uninstall" ;;
  "") ;;
  *) echo "未知参数: $1 (仅支持 --uninstall)"; exit 1 ;;
esac

warn() { printf '\033[33m[warn]\033[0m %s\n' "$1"; }

strip_block() {  # 从文件移除标记块(存在才处理)
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -qF "$MARK" "$file" || return 0
  awk -v s="$MARK" -v e="$END_MARK" '$0 ~ s, $0 ~ e {next} 1' "$file" > "$file.tpn.tmp"
  mv "$file.tpn.tmp" "$file"
}

backup_on_first() {  # $1=原文件 $2=备份路径; 仅"首次安装"(无标记)且备份不存在时备份, 升级永不覆盖旧备份
  local file="$1" bak="$2"
  [[ -f "$file" ]] || { echo "[info] $file 不存在, 将新建(卸载时会一并删除)"; return 0; }
  grep -qF "$MARK" "$file" && return 0
  [[ -f "$bak" ]] && return 0
  cp "$file" "$bak"
  echo "[ ok ] 首次安装: 已备份 $file → $bak"
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
  if [[ -d "$HOME/.tmux-pane-notify" ]]; then
    rm -rf "$HOME/.tmux-pane-notify"
    echo "[ ok ] 已删除 $HOME/.tmux-pane-notify/"
  fi
  if tmux info >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf" 2>/dev/null && echo "[ ok ] tmux 配置已热加载"
    tmux unbind-key t 2>/dev/null || true
    tmux unbind-key T 2>/dev/null || true
    tmux set -g pane-border-status off 2>/dev/null || true
    echo "[info] 运行中 server 已解绑并尽量还原; 如曾有自定义同名选项, 重启 tmux server 后为完全干净状态"
  else
    echo "[info] tmux 未运行, 卸载即完全生效"
  fi
  echo
  echo "完成。备注:"
  echo "  - 已开 pane 里的 zsh hook 需 exec zsh 才会消失"
  echo "  - 首次安装的备份保留在 ~/.tmux.conf.tpn.bak / ~/.zshrc.tpn.bak"
  echo "    (如需逐字节还原可手动 cp 回去; 确认无误后可自行删除)"
  exit 0
fi

# ---------- 安装/升级 ----------
[[ -n "${ZSH_VERSION:-}" ]] && { echo "请在 bash 下运行本脚本(它会写 .zshrc)"; exit 1; }
[[ -f "$HOME/.zshrc" ]] || { echo "未找到 ~/.zshrc"; exit 1; }

# 首次安装备份(升级路径不覆盖旧备份)
backup_on_first "$HOME/.tmux.conf" "$HOME/.tmux.conf.tpn.bak"
backup_on_first "$HOME/.zshrc"     "$HOME/.zshrc.tpn.bak"

# 冲突检测(仅首次安装提示; 升级路径视为已接受)
detect_conf_tmux
detect_conf_zsh

# ---------- 1. tmux 配置 ----------
mkdir -p "$HOME/.tmux-pane-notify"
cat > "$HOME/.tmux-pane-notify/panel.sh" <<'EOF'
#!/usr/bin/env bash
# 全局 pane 实时监控面板 (tmux 3.2+ display-popup 内运行)
# 树状: 状态分区 → 会话 → 窗口 → pane; 区内按完成时间倒序(新→旧)
# 1 秒自动刷新, 按任意键退出

C_G=$'\e[32m'; C_Y=$'\e[33m'; C_D=$'\e[2m'; C_R=$'\e[0m'
# socket 选择: TMUX env 优先(pane 内运行); 否则若仅存在一个 socket 则用之(兼容 -L); 最后默认
SOCK=()
[ -n "${TMUX:-}" ] && SOCK=(-S "${TMUX%%,*}")
if [ ${#SOCK[@]} -eq 0 ]; then
  d="/tmp/tmux-$(id -u)"
  [ "$(ls "$d" 2>/dev/null | wc -l)" -eq 1 ] && SOCK=(-S "$d/$(ls "$d")")
fi
t() { tmux "${SOCK[@]}" "$@"; }

while true; do
  RECS=''; nd=0; nr=0; ni=0
  while IFS='|' read -r sess win wname pidx title act; do
    [ -z "$sess" ] && continue
    case "$title" in
      "✅ done"*) st=done; nd=$((nd+1)) ;;
      ⏳*)        st=run;  nr=$((nr+1)) ;;
      *)          st=idle; ni=$((ni+1)) ;;
    esac
    # 完成时间键: 解析标题尾部 HH:MM(:SS)?; 旧格式 HH:MM 秒位按 00
    tk=0
    [[ "$title" =~ ([0-9]{1,2}):([0-9]{2})(:([0-9]{2}))?[[:space:]]*$ ]] && \
      tk=$(( 10#${BASH_REMATCH[1]}*3600 + 10#${BASH_REMATCH[2]}*60 + 10#${BASH_REMATCH[4]:-0} ))
    RECS+="${st}|${sess}|${win}|${wname}|${tk}|${pidx}|${title}|${act}"$'\n'
  done < <(t list-panes -a -F '#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_title}|#{?pane_active,▶,}' 2>/dev/null)

  printf '\e[H\e[2J'
  printf '%s tmux pane 监控  %s共%d | %s✅ done %d%s | %s⏳ running %d%s | idle %d   %s%s\n\n' \
    "$C_D" "$C_R" $((nd+nr+ni)) "$C_G" "$nd" "$C_R" "$C_Y" "$nr" "$C_R" "$ni" "$(date +%H:%M:%S)" "$C_R"

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
        while IFS='|' read -r st_ se wi wn tk pidx title act; do
          printf '        %s  %s%s%s' "$pidx" "$color" "$title" "$C_R"
          [ -n "$act" ] && printf ' %s▶%s' "$C_Y" "$C_R"
          printf '\n'
        done < <(printf '%s\n' "$RECS" | grep -F "${st}|${sess}|${win}|" | sort -t'|' -k5,5nr -k6,6n)
        printf '\n'
      done <<< "$wins"
    done <<< "$sessions"
  }

  section done "✅ done (待认领)" "$C_G"
  section run  "⏳ running"        "$C_Y"
  section idle "idle"              "$C_D"

  printf '\n%s按任意键关闭 · 1s 自动刷新%s\n' "$C_D" "$C_R"
  read -t 1 -n 1 -s && exit 0
done
EOF
chmod +x "$HOME/.tmux-pane-notify/panel.sh"

if grep -qF "$MARK" "$HOME/.tmux.conf" 2>/dev/null; then
  echo "[update] 刷新 ~/.tmux.conf 已有配置"
else
  echo "[ ok ] 追加配置到 ~/.tmux.conf"
fi
strip_block "$HOME/.tmux.conf"
cat >> "$HOME/.tmux.conf" <<EOF

$MARK
set -g pane-border-status top
set -g pane-border-format "#{pane_index} #{pane_title}#{?pane_active, ▶,}"
set -g monitor-activity on
set -g visual-activity off
set -g visual-bell off
if-shell "tmux -V | grep -qE 'tmux (3\\.[2-9]|[4-9])'" \\
  "bind-key t display-popup -w 80% -h 60% -E ~/.tmux-pane-notify/panel.sh" ""
$END_MARK
EOF

# ---------- 2. zsh hook ----------
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
  # 设置 pane 标题。注意: 结尾 \a 只是 OSC 结束符, tmux 不会把它当响铃
  _tpn_title() { printf '\e]2;%s\a' "\$1" }
  _tpn_preexec() {
    TPN_START=\$SECONDS
    TPN_CMD="\${\${(z)1}[1]}"
    _tpn_title "⏳ \$TPN_CMD"
  }
  _tpn_precmd() {
    if [[ -n "\${TPN_START:-}" ]]; then
      local dur=\$(( \$SECONDS - \$TPN_START ))
      if (( dur >= \$TMUX_PANE_NOTIFY_MIN_SEC )); then
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

# ---------- 3. 热加载 tmux 配置 ----------
# 注意: tmux server 进程 comm 为 "tmux: server", pgrep -x tmux 匹配不到;
# 直接用 tmux info 探测 default socket(source-file 的目标) 是否可用
if tmux info >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf" 2>/dev/null && echo "[ ok ] tmux 配置已热加载" \
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
echo "  4. tmux 3.2+: 按 prefix+t 弹出全局 pane 状态面板 (覆盖内置时钟)"
echo "  5. 卸载: bash $0 --uninstall  (移除标记块与面板, 其余配置保留)"
