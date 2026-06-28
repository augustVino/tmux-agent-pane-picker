#!/usr/bin/env bash
# 记录 agent（Claude Code / Codex / 任意带状态 hooks 的 agent）状态到当前 pane（供 prefix+/ popup 读取）。
# 用法（由 agent 的 hooks 调用）：state.sh <working|waiting|idle>
#
# hooks 继承 agent 进程环境，故 agent 在 tmux 内运行时 $TMUX_PANE 已设置；
# 非 tmux 环境下为空，本脚本静默退出（hook 全局安全，不影响普通终端里的 agent）。
#
# Claude Code 的 PreToolUse 经 stdin 传入 hook JSON：若 tool_name == AskUserQuestion，
# 状态覆写为 waiting。这是「单 hook 内串行判定」，刻意规避「两条 matcher hook 并行
# 竞写 @agent_state」的竞态（官方：同 event 多 matcher hook 并行、顺序非确定）。
# 其它 agent（如 Codex）的 PreToolUse tool_name 为 Bash/apply_patch/MCP，不命中，
# 沿用 $1；其 waiting 由各自 hooks（如 Codex 的 PermissionRequest）传 $1=waiting。
# @agent_state_at 供未来「几分钟前」展示或同 rank 时间排序，picker 当前不读取。
[ -z "$TMUX_PANE" ] && exit 0

state="${1:-idle}"
if ! [ -t 0 ]; then                                                # stdin 非终端（hook 注入 JSON）才读
  tool_name="$(jq -r '.tool_name // empty' 2>/dev/null)"           # jq 缺失/解析失败 → 空
  [ "$tool_name" = "AskUserQuestion" ] && state="waiting"
fi

tmux set-option -p -t "$TMUX_PANE" @agent_state    "$state"        2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @agent_state_at "$(date +%s)"   2>/dev/null || true
exit 0
