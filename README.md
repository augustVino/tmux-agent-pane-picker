# tmux-agent-pane-picker

在 tmux 里管理多个 AI coding agent（Claude Code、Codex、……）—— 一个 popup 列出所有 pane，实时显示每个 agent 的状态（`working` / `waiting` / `idle`），右侧预览，回车精确跳转。

## 解决什么痛点

同时开多个 agent 跑不同项目时（一个 session 多个 window、一个 window 多个 pane），无法一眼看出**哪个 agent 在等你授权、哪个已空闲、哪个还在忙**，必须逐个 pane 翻看。本工具把所有 agent 的状态摊到一个 popup 里，按紧急度排序——需要你的永远浮在最上面。

## 工作原理

helpers + 三个脚本（state/pane-picker/prune-dead）+ 入口（`agent-pane-picker.tmux`）+ 各 agent 的 hooks，状态全部存在 tmux 的 **pane 级 user option** 上（无外部存储、无守护进程）：

```
入口加载 → set @agent_plugin_dir + option 默认 + 装 prefix+<list_key>
                                        │
agent 运行 → hooks 调 state.sh → 写 pane 级 @agent_state / @agent_state_at
                                        │
prefix+<list_key> → display-popup pane-picker.sh → prune-dead 清幽灵
                                        → list-panes 读 @agent_state
                                        → fzf：状态色 + 优先排序 + 右侧 capture-pane 预览
                                        → 选中：select-pane → select-window → switch-client 三层跳转
```

| 脚本                     | 职责                                                                                               |
| ------------------------ | -------------------------------------------------------------------------------------------------- |
| `scripts/helpers.sh`     | 公共函数：`get_tmux_option` / `tmux_dir` / `agent_processes` / `state_field`（各脚本 source 复用） |
| `scripts/state.sh`       | agent 的 hooks 调用，把状态写到当前 pane（`-p -t "$TMUX_PANE"`）                                   |
| `scripts/pane-picker.sh` | popup 内的 fzf 选择器：枚举 + 着色排序 + 预览 + 三层跳转                                           |
| `scripts/prune-dead.sh`  | 活性检测：展示前遍历每个有状态 pane 的 shell 子孙树找 agent，找不到则清状态（清幽灵）              |
| `agent-pane-picker.tmux` | tpm / `run-shell` 入口：设 `@agent_plugin_dir`、option 默认值、装 `bind-key`                       |

**为什么是 pane 级而非 session 级**：一个 session 里可能有多个 pane 各跑一个 agent；session 级状态会「最后一写覆盖」，状态失真。pane 级让每个 agent 的状态独立，且 pane 关闭时状态自动随 pane 消失，无脏数据。

## 接入要求

| 依赖 | 版本  | 用途                                                                           |
| ---- | ----- | ------------------------------------------------------------------------------ |
| tmux | ≥ 3.2 | `display-popup`（3.2 引入）；pane option `set-option -p`（3.0 引入）           |
| fzf  | 任意  | picker UI                                                                      |
| jq   | 任意  | `state.sh` 解析 hook stdin；缺失则降级（不报错，沿用参数）                     |
| bash | ≥ 3.2 | 四个脚本 + 入口（state/pane-picker/prune-dead/helpers；macOS 自带 3.2 已兼容） |

平台：macOS、Linux。

## 安装

### 方式一：tpm

```tmux
set -g @plugin 'augustVino/tmux-agent-pane-picker'
```

`prefix` + `I` 安装。tpm 通过 glob 执行插件目录下所有 `*.tmux`，入口文件名遵循社区惯例即可（同 resurrect.tmux）。

### 方式二：manual（自用 / 开发，改源码即时生效）

```tmux
run-shell ~/Documents/github/tmux-agent-pane-picker/agent-pane-picker.tmux
```

两种方式均无需手改 hooks 路径——入口加载时把安装路径写入 `@agent_plugin_dir`，hooks 命令读取它（见下「@agent_plugin_dir 机制」）。

> 插件路径勿含空格/单引号（fzf reload 用单引号包裹路径）。默认 `~/Documents/github` 与 tpm 的 `~/.tmux/plugins` 均无此问题。

## @agent_plugin_dir 机制

hooks 配置在 agent 自身的 settings（如 `~/.claude/settings.json`），插件无法自动改写。原先硬编码 `$HOME/.config/tmux/scripts/state.sh`。本插件入口加载时把真实安装路径写入 global option `@agent_plugin_dir`，hooks 命令读取它：

```
d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n "$d" ] && "$d/scripts/state.sh" <state> || true
```

→ manual 与 tpm 共用同一份 hooks 配置。tmux 外运行或插件未加载时 `$d` 为空，`|| true` 兜底，state.sh 自身 `[ -z "$TMUX_PANE" ] && exit 0` 无副作用。

> **状态是 pane 级单写者**（M2）：`@agent_state` 存在 pane option 上，一个 pane 一个状态。多 agent 请分 pane 运行（Claude Code 子 agent 默认独立 pane）。同 pane 起多个 agent 会互相覆盖状态（可能 working 覆盖 waiting 丢失紧急信号），属非默认场景。

## 接入一个 agent

**核心**：让 agent 在生命周期事件里调 `state.sh <working|waiting|idle>`。脚本不关心是哪个 agent——只要它提供 hooks、并按下表把事件映射到状态即可。

### 状态机

| 状态      | 含义            | 颜色 / 排序                   |
| --------- | --------------- | ----------------------------- |
| `waiting` | 等你授权 / 回答 | 🟡 黄，rank 0（浮顶）         |
| `idle`    | 一轮结束，待命  | 🟢 绿，rank 1                 |
| `working` | 正在忙          | 🔴 红，rank 2（agent 区）     |
| （无）    | 普通 shell pane | ⚪ 灰，rank 3（无状态，沉底） |

排序：先按状态分组 `waiting → idle → working → 普通 shell`（**有状态 agent 在前，无状态 shell 沉底**）；**同组内按 `@agent_state_at` 降序**——最近变化的最在前。需要你的、且刚发生变化的状态，浮在最上面。

### Claude Code 接入

`~/.claude/settings.json` 的 `hooks`（追加到各事件数组，勿覆盖已有条目）：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" idle || true"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" working || true"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" working || true"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" waiting || true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" idle || true"
          }
        ]
      }
    ]
  }
}
```

> **状态机说明**：
>
> - `waiting`（黄）= `permission_prompt`（授权）+ `AskUserQuestion`（PreToolUse 经 state.sh stdin 分流，单 hook 串行避竞态）。
> - `idle`（绿）= `Stop`（正常完成）+ `idle_prompt`（**兜底 ESC 中断**——官方确认 Stop 在用户中断时不触发，补 idle_prompt→idle 作回落；但文档未明确 ESC 是否触发 idle_prompt，需实测，不保证自愈）。
> - `UserPromptSubmit`/`Stop` 不支持 matcher，配 `"matcher": ""` 被静默忽略（等价每次触发），保留与社区惯例一致。
> - **known gap**（M1）：AskUserQuestion 回答后 / 权限拒绝后的「思考期」可能短暂误显 waiting——Claude Code 无 UserResponse 事件，固有限制，留 future work。

### Codex 接入

`~/.codex/hooks.json`（[Codex hooks 文档](https://developers.openai.com/codex/hooks)）：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" idle || true"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" working || true"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash|apply_patch",
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" working || true"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" waiting || true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n \"$d\" ] && \"$d/scripts/state.sh\" idle || true"
          }
        ]
      }
    ]
  }
}
```

> Codex 的「等用户」是 `PermissionRequest`（权限审批请求），映射到 `waiting`。Codex 没有 `AskUserQuestion`，`state.sh` 的 stdin 分流对它无害（其 PreToolUse 的 `tool_name` 是 `Bash`/`apply_patch`/MCP，不命中，沿用参数）。

### 接入其它 agent

只要该 agent 能在「开始忙 / 等用户 / 结束」三个时机各跑一行命令，就能接（路径自适应，无需硬编码）：

```bash
d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n "$d" ] && "$d/scripts/state.sh" working   # 开始处理 / 调用工具
d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n "$d" ] && "$d/scripts/state.sh" waiting   # 需要用户授权或回答
d=$(tmux show-option -gv @agent_plugin_dir 2>/dev/null); [ -n "$d" ] && "$d/scripts/state.sh" idle      # 一轮结束，待命
```

## 用法

按 `prefix + /`（默认 `C-a /`）打开 popup：

- `↑` / `↓` 选择，输入即过滤（session 名 / window 名 / 路径 / 状态词）
- 右侧实时预览选中 pane 的屏幕（`capture-pane`，选中即刷新）
- `enter` 跳转：切到目标 session → window → pane，**不 zoom**（想全屏自按 `prefix + z`）
- `esc` 取消

每行三列显示：`状态色点  session:windowName.pane  路径(~)`——windowName 融入第二列（sessionName 后），所有 pane（含普通 shell）都有；普通 pane 默认 windowName 是 shell 名，可用 `rename-window`（`prefix + ,`）设成项目名。

## 活性检测（prune-dead）

`Ctrl+C`/崩溃/`kill` 不触发退出 hook → 状态卡死成"幽灵"。`prune-dead.sh` 展示前对每个有状态 pane 独立遍历其 shell 子孙树找 agent，找不到则清除。daemon（不在 pane 子孙树）不参与，Ctrl+C 正确清幽灵。名单 `@agent_processes`（默认 `claude codex`），按 comm basename 精确匹配；wrapper/npm 全局装（comm=node）需扩展：`tmux set-option -g @agent_processes "claude codex mycc"`。

## 跨平台

纯 POSIX + tmux + bash + jq + fzf，无 macOS / Linux 专属调用。`#{pane_current_path}` 在 macOS 走 libproc、Linux 走 `/proc/<pid>/cwd`，均可靠；同 window 多 pane 不同路径互不混淆。

## 自定义

- **popup 尺寸 / 切换键**：`tmux set -g @agent_popup_width 90%`、`@agent_popup_height 90%`、`@agent_list_key /`（在 source 入口前 set）。
- **agent 名单**：`tmux set -g @agent_processes "claude codex mycc"`。
- **状态文案 / 颜色**：改 `scripts/helpers.sh` 的 `state_field`。

## License

MIT
