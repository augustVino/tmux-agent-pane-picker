#!/usr/bin/env bash
# tmux-agent-pane-picker 公共函数（各脚本 source 复用，消除重复样板）。

# get_tmux_option <name> <default>
# 读 global option，空/未设则输出 default。
get_tmux_option() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$value" ]; then printf '%s' "$value"; else printf '%s' "$2"; fi
}

# tmux_dir：插件根目录绝对路径（本文件在 scripts/ 下，根在上一级）。
# BASH_SOURCE[0] 始终指向 helpers.sh 自身，故无论谁调用都稳定返回插件根。
tmux_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# agent_processes：agent comm 名单（global option @agent_processes 覆盖，默认 claude codex）。
agent_processes() {
  local p
  p="$(tmux show-option -gv @agent_processes 2>/dev/null)"
  if [ -n "$p" ]; then printf '%s' "$p"; else printf '%s' "claude codex"; fi
}

# state_field <state>：输出 "rank\t<彩色圆点 状态词>"。
# rank 升序：waiting→idle→working→普通(-)；颜色硬编码（审美偏好，不 option 化）。
state_field() {
  case "$1" in
    waiting) printf '0\t\033[33m●\033[0m waiting' ;;  # 黄：等你授权/回答
    idle)    printf '1\t\033[32m●\033[0m idle   ' ;;  # 绿：待命
    working) printf '2\t\033[31m●\033[0m working' ;;  # 红：忙
    *)       printf '3\t\033[90m●\033[0m -      ' ;;  # 灰：普通 shell pane（无状态）
  esac
}
