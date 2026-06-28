#!/usr/bin/env bash
# prefix+/ popup：统一 agent pane 切换器。
# 列出所有 pane：agent pane（Claude Code / Codex / …）带状态色并优先排序，普通 shell pane 灰色照常列出。
# 右侧 capture-pane 预览（选中即刷新）；选中后 session→window→pane 三层定位，不 zoom。
set -uo pipefail
. "$(dirname "$0")/helpers.sh" || {
  tmux display-message "tmux-agent-pane-picker: helpers 加载失败" 2>/dev/null
  exit 1
}
DIR="$(tmux_dir)"

# 枚举所有 pane，输出 fzf 行。字段（输出用 \t 分隔）：
#   1 rank（隐藏）  2 state_at（隐藏，二级排序）  3 pane_id（隐藏）  4 coord=session:win.pane（隐藏，跳转）
#   5 <彩色dot 状态>（列1）  6 label=session:windowName.pane（列2）  7 path（列3）
# 排序：rank 升序（状态分组）→ state_at 数字降序（同组内最近变化的在前；普通 pane 无时间戳=0 排同组末）→ stable。
# coord 与 label 分离：显示用可读 windowName，跳转用编号 coord，互不影响——改 label 不破坏跳转。
# windowName 取自 tmux window name，所有 pane（含普通 shell）都有；普通 pane 默认是 shell 名，可 rename-window。
# ⚠️ 内部读取用 \x1f(unit separator) 分隔：非 whitespace，read 不合并连续分隔符，
#    修复 @agent_state 为空（普通 pane）时连续 tab 致字段错位、windowName 丢失。输出层用 \t。
emit_rows() {
  # 清除「agent 已死但 @agent_state 残留」的幽灵状态，再枚举
  "$DIR/scripts/prune-dead.sh" 2>/dev/null || true
  local fmt=$'#{pane_id}\x1f#{session_name}:#{window_index}.#{pane_index}\x1f#{@agent_state}\x1f#{@agent_state_at}\x1f#{session_name}:#{window_name}.#{pane_index}\x1f#{pane_current_path}'
  tmux list-panes -a -F "$fmt" 2>/dev/null |
    while IFS=$'\x1f' read -r pid coord state state_at label path; do
      [ -z "$pid" ] && continue
      sf="$(state_field "$state")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${sf%%$'\t'*}" "${state_at:-0}" "$pid" "$coord" "${sf#*$'\t'}" "$label" "${path/#$HOME/~}"
    done | sort -t$'\t' -k1,1n -k2,2nr -s
}

# --emit：仅输出行（供测试 / reload 使用）
[ "${1:-}" = '--emit' ] && { emit_rows; exit 0; }

# 缺 fzf 时友好提示并退出
if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-agent-pane-picker: 需要安装 fzf" 2>/dev/null
  exit 0
fi

# fzf 交互：三列显示字段 5(dot)/6(label)/7(path)，预览用字段 3(pane_id) capture，跳转解析字段 4(coord)
# Ctrl+R → reload 重跑 emit_rows：popup 打开期间列表是静态快照，按一下拉取最新 @agent_state
# （状态色+排序即时刷新，保留当前过滤词；仅 fzf 消费此键，不触及任何 pane/session，popup 关闭即失效）
# ⚠️ reload 用单引号包裹 $DIR 路径，故插件路径勿含空格/单引号（默认 ~/Documents/github 与 ~/.tmux/plugins 无此问题）
sel="$(emit_rows | fzf \
  --ansi --delimiter='\t' --with-nth=5,6,7 \
  --reverse --cycle \
  --header='Agent panes · enter: 跳转 · Ctrl+R 刷新 · 输入过滤' \
  --bind "ctrl-r:reload('$DIR/scripts/pane-picker.sh' --emit)" \
  --preview='tmux capture-pane -ept {3}' \
  --preview-window='right,55%,wrap')"

[ -z "$sel" ] && exit 0   # ESC / 无选中 → 取消

pid="$(printf '%s' "$sel" | cut -f3)"
coord="$(printf '%s' "$sel" | cut -f4)"
session="${coord%%:*}"
rest="${coord#*:}"
window="${rest%%.*}"

# 三层定位：先设目标 pane/window 为 active，再切 client 视角，避免切换瞬间闪烁到错误 window
tmux select-pane   -t "$pid"                  2>/dev/null
tmux select-window -t "${session}:${window}"  2>/dev/null
tmux switch-client -t "$session"              2>/dev/null
