#!/usr/bin/env bash
# tmux-agent-pane-picker 入口：tpm / run-shell 在 tmux 启动时执行。
# 设 option 默认值、记录插件目录（@agent_plugin_dir）、装 prefix+<list_key> 绑定。
# tpm 通过 glob 执行插件目录下所有 *.tmux（命名遵循社区惯例，如 resurrect.tmux）。
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh" || {
  # source 失败兜底：tpm 用 >/dev/null 2>&1 吞输出，display-message 走 tmux message
  # 机制（非 stdout），能绕过重定向打到状态栏，避免子系统静默失活。
  tmux display-message "tmux-agent-pane-picker: helpers 加载失败" 2>/dev/null
  exit 1
}

# 让 hooks 命令能自适应 install 路径（manual / tpm 均可）
tmux set-option -g @agent_plugin_dir "$CURRENT_DIR"

# option 默认值（用户可在 source 本文件前 set 覆盖）
list_key="$(get_tmux_option @agent_list_key '/')"
width="$(get_tmux_option @agent_popup_width '85%')"
height="$(get_tmux_option @agent_popup_height '80%')"

# 装 popup 绑定（unbind 防与既有冲突）
tmux unbind-key "$list_key" 2>/dev/null
tmux bind-key "$list_key" display-popup -w "$width" -h "$height" \
  -E "$CURRENT_DIR/scripts/pane-picker.sh"
