#!/usr/bin/env bash
# 轻量断言（无框架）：source helpers 后校验纯函数输出。
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/scripts/helpers.sh"

fail=0
assert_eq() { # <desc> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: [$2] != [$3]"; fail=1; fi
}

# state_field：只校验 rank（cut -f1，排序语义）。
# 不校验状态词（cut -f2）：state_field 输出含原始 ANSI 转义字节（\033[33m...），
# 字节级不等且颜色属审美硬编码，由端到端 popup 验收覆盖。
assert_eq "state_field waiting rank" "$(state_field waiting | cut -f1)" "0"
assert_eq "state_field idle rank"    "$(state_field idle | cut -f1)"    "1"
assert_eq "state_field working rank" "$(state_field working | cut -f1)" "2"
assert_eq "state_field unknown rank" "$(state_field xxx | cut -f1)"     "3"

# tmux_dir：返回插件根（helpers.sh 在 scripts/ 下，根在上一级）
assert_eq "tmux_dir = 插件根" "$(tmux_dir)" "$DIR"

# agent_processes：仅断言非空（默认 claude codex 或用户自定义）。
# 不硬编码 "claude codex"：detached tmux server 上若有人 set @agent_processes，返回值会变，
# 硬编码会导致环境耦合 flaky。非空即说明函数工作。
ap="$(agent_processes)"
[ -n "$ap" ] && echo "ok   - agent_processes 非空: $ap" || { echo "FAIL - agent_processes 空"; fail=1; }

exit $fail
