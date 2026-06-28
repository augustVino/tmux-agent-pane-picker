#!/usr/bin/env bash
# 活性检测：清除「agent 已死但 @agent_state 残留」的 pane 状态。
# 正向 per-pane BFS（kids 索引）：对每个有 @agent_state 的 pane，沿 ppid→children 索引遍历其
# shell(#{pane_pid}) 子孙树找匹配名单的 agent；找不到则 unset 状态。O(总进程数)。
# 由 picker（emit_rows 前）调用。statusline 集成为 future work（暂无独立渲染脚本）。
#
# 用法：
#   prune-dead.sh          执行清理（unset @agent_state / @agent_state_at）
#   prune-dead.sh --list   dry-run：仅输出死 pane_id（供测试）
#
# 名单由 global option @agent_processes 指定（默认 "claude codex"，见 helpers.agent_processes），
# 按 comm basename 精确比对。正向算法不需 na==0 兜底：daemon（ppid=1 不在任何 pane 子孙树）
# 不参与，Ctrl+C 单杀/全杀都正确清。ps 失败时 np==0 → 不判（防全杀）。
set -uo pipefail
. "$(dirname "$0")/helpers.sh" || {
  tmux display-message "tmux-agent-pane-picker: helpers 加载失败" 2>/dev/null
  exit 1
}
DIR="$(tmux_dir)"

dry=0
[ "${1:-}" = "--list" ] && dry=1

procs="$(agent_processes)"

dead="$({
  ps -axo pid=,ppid=,comm= 2>/dev/null
  tmux list-panes -a -F $'P\t#{pane_id}\t#{@agent_state}\t#{pane_pid}' 2>/dev/null
} | awk -v names="$procs" '
  BEGIN { nn = split(names, nm, " ") }
  $1 == "P" {
    split($0, a, "\t")
    if (a[3] != "") { order[++n] = a[2]; shell_pid[a[2]] = a[4] }
    next
  }
  {
    if ($2 in kids) kids[$2] = kids[$2] SUBSEP $1; else kids[$2] = $1   # ppid→children 索引
    c = $3; sub(/^.*\//, "", c)
    comm_of[$1] = c
    np++
  }
  END {
    if (np == 0) exit                              # ps 失败/空 → 不判（防全杀）
    for (i = 1; i <= n; i++) {
      id = order[i]; root = shell_pid[id]
      if (!pane_alive(root)) print id
    }
  }
  function pane_alive(root, q, head, tail, cur, k, ka, nk, ch, seen) {
    if (!(root in comm_of)) return 0              # root 进程不存在 → 死
    head = 0; tail = 1; q[0] = root; seen[root] = 1
    while (head < tail) {
      cur = q[head++]
      if (cur in comm_of) for (k = 1; k <= nn; k++) if (comm_of[cur] == nm[k]) return 1
      if (cur in kids) {
        nk = split(kids[cur], ka, SUBSEP)
        for (k = 1; k <= nk; k++) { ch = ka[k]; if (!(ch in seen)) { seen[ch] = 1; q[tail++] = ch } }
      }
    }
    return 0
  }
')"

if [ "$dry" = "1" ]; then
  [ -n "$dead" ] && printf '%s\n' "$dead"
  exit 0
fi

for pid in $dead; do
  tmux set-option -p -u -t "$pid" @agent_state     2>/dev/null || true
  tmux set-option -p -u -t "$pid" @agent_state_at  2>/dev/null || true
done
exit 0
