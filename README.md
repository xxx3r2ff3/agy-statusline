# agy-statusline

适用于 Google Antigravity CLI (`agy`) 的状态栏脚本。Windows 使用原生 PowerShell（无需额外运行时），Linux / macOS 使用 Bash + `jq` + `awk`（兼容 macOS 自带 Bash 3.2 与 BSD 工具链，无需 Python 或 Node.js）。

---

## 功能特性

- **状态与上下文**：实时显示 Agent 状态、当前模型、工作目录与 Git 分支（非 Git 目录安全回退；Git 目录支持脏工作区 `*` 标记）。
- **一致口径的上下文统计**：`Ctx` 使用与 `used_percentage` 一致的当前活跃窗口占用（`used / window_size (pct%)`），避免长会话中累计值超过窗口上限导致数字与百分比矛盾。
- **会话遥测指标**：按增量字节偏移解析 `transcript_path`（原生 JSON 解析 + 本地缓存，兼容 `/antigravity/` 到 `/antigravity-cli/` 路径回退）：
  - `Turns: N (Compact: M)`：`Turns` 统计用户交互轮次（`USER_INPUT`）；`Compact` 统计上下文压缩次数（`CHECKPOINT` / `COMPACT` 优先，避免与骤降启发式重复计数）。
  - `Cache: pct% (tok)`：最近一次请求的提示词缓存命中率与缓存读取 Token。
  - `ΣTok`：从 `transcript_path` 统计的全会话累计 Token（读取不到或未提供 transcript 时自动省略，不回退到失真数值）。
  - `Avg: ~tok/s`：最近 10 个带工具调用的 `PLANNER_RESPONSE -> GENERIC` 步骤平均吞吐估算（包含思考与调度耗时，非纯解码速度，不含 TTFT）。
- **附加统计**：按需展示 `artifacts`、`subagents`、`tasks`、`sandbox`（默认自动隐藏零值项）。
- **套餐与配额监控**：显示订阅计划（`plan`）以及 5 小时 / 7 天滚动配额进度条与重置时间。
- **自适应布局与防溢出截断**：根据 `terminal_width` 切换宽屏、中屏、窄屏排版，并按 ANSI 剥离后的终端可见列宽强制截断超长行，避免终端折行。

---

## 布局预览

### 宽屏（`>= 120` 列）

```text
● READY / Gemini 4 Hydrogen (High) / agy-statusline (main*)  │  Ctx: 136.4k/1.05M (13.0%) [██░░░░░░░░░░░░░]
Turns: 29 (Compact: 0) │ Cache: 98.0% (105.3k) │ ΣTok: 2.02M │ Avg: ~164 tok/s
plan: Google AI Pro
gemini 5h ●●●●●●●●○○  82% ⟳ 05:31
gemini 7d ●●○○○○○○○○  24% ⟳ nov 25, 00:31
```

### 中屏（`100 ~ 119` 列）

```text
╭─ ● READY / Gemini 4 Hydrogen (High) / agy-statusline (main*)
├─ Ctx: 136.4k/1.05M (13.0%) [█░░░░░░░]
╰─ Turns: 29 (Compact: 0) · Cache: 98.0% (105.3k) · ΣTok: 2.02M · Avg: ~164 tok/s
plan: Google AI Pro
gemini 5h ●●●●●●●●○○  82% ⟳ 05:31
gemini 7d ●●○○○○○○○○  24% ⟳ nov 25, 00:31
```

### 窄屏（`< 100` 列）

```text
╭─ ● READY / Gemini 4 Hydrogen (High)
├─ agy-statusline (main*)
├─ Ctx: 136.4k/1.05M (13.0%) [█░░░░░░░]
╰─ Turns: 29 (Compact: 0) · Cache: 98.0% (105.3k) · ΣTok: 2.02M · Avg: ~164 tok/s
plan: Google AI Pro
gemini 5h ●●●●●●●●○○  82% ⟳ 05:31
gemini 7d ●●○○○○○○○○  24% ⟳ nov 25, 00:31
```

---

## 状态徽章

| `agent_state` | 显示徽章     |
| ------------- | ------------ |
| `idle`        | `● READY`    |
| `thinking`    | `◆ THINKING` |
| `working`     | `⚙ WORKING`  |
| `tool_use`    | `🔧 TOOL`    |
| 其他状态      | `⏳ <STATE>` |

---

## 安装与卸载

### 1. 克隆仓库

```bash
git clone https://github.com/xxx3r2ff3/agy-statusline.git
cd agy-statusline
```

### 2. 安装

**Windows（PowerShell）：**

```powershell
./bin/install.ps1
```

**Linux / macOS（Bash）：**

```bash
chmod +x bin/install.sh bin/statusline.sh
./bin/install.sh
```

安装脚本会将状态栏脚本与默认配置复制到 `~/.gemini/`，并在更新 `~/.gemini/antigravity-cli/settings.json` 前将你原有的 `statusLine` 配置备份到 `~/.gemini/statusline.prev.json`。安装后重启 `agy` 即可生效。

### 3. 卸载

- Windows：`./bin/uninstall.ps1`
- Linux / macOS：`./bin/uninstall.sh`

卸载脚本会移除状态栏脚本，并自动从 `~/.gemini/statusline.prev.json` 恢复安装前的 `statusLine` 配置（若安装前本无该配置则移除之）。

---

## 配置项

可在 `~/.gemini/statusline.json` 中自定义显示开关（参考 [statusline.json.example](statusline.json.example)）：

```json
{
  "show_quota": true,
  "show_additional_stats": true,
  "hide_zero_stats": true,
  "show_state_indicator": true
}
```

| 配置项                  | 默认值 | 说明                                              |
| ----------------------- | ------ | ------------------------------------------------- |
| `show_quota`            | `true` | 是否显示 5 小时与 7 天配额进度条                  |
| `show_additional_stats` | `true` | 是否显示 `artifacts`、`subagents`、`tasks`、`sandbox` |
| `hide_zero_stats`       | `true` | 为 `true` 时隐藏数值为 `0`（或关闭）的附加统计项  |
| `show_state_indicator`  | `true` | 是否显示状态徽章（`READY` / `WORKING` 等）        |

---

## 运行依赖

| 平台          | 依赖                                       |
| ------------- | ------------------------------------------ |
| Windows       | PowerShell 5.1+（无外部依赖）              |
| Linux / macOS | `bash`（3.2+）、`jq`、`awk`（兼容 GNU/BSD） |

---

## 本地测试与代码检查

### Linux / macOS

```bash
./tests/test_sh.sh
./tasks/format.sh
./tasks/lint.sh
```

### Windows

```powershell
./tests/test_ps1.ps1
./tasks/format.ps1
./tasks/lint.ps1
```

---

## 致谢与来源（Credits）

- 基于 [`dersual/my-agy-statusline`](https://github.com/dersual/my-agy-statusline) 衍生修改
- [`Ranteck/agy-statusline`](https://github.com/Ranteck/agy-statusline)（滚动配额展示思路）
- [`google-antigravity/antigravity-cli`](https://github.com/google-antigravity/antigravity-cli/tree/main/examples/statusline)（官方 statusline 示例结构）
