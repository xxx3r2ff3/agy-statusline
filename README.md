# agy-statusline

适用于 Google Antigravity CLI (`agy`) 的状态栏脚本。Windows 使用原生 PowerShell，Linux / macOS 使用 Bash + `jq` + `awk`，无需 Python 或 Node.js 运行时。

---

## 功能特性

- **状态与上下文**：实时显示 Agent 状态、当前模型、项目目录与 Git 分支（含未提交变更 `*` 标记）。
- **上下文 Token 统计**：显示当前已用/最大上下文容量及百分比进度条（`Ctx: 136.4k/1.05M (9.8%) [█▒·············]`）。
- **会话遥测指标**：自动读取当前会话 `transcript_path`，统计并展示：
  - `Turns: N (Compact: M)`：对话轮次与上下文压缩次数
  - `Cache: pct% (tok)`：最近一次请求的缓存命中率与缓存读取 Token
  - `ΣTok`：当前会话累计消耗总 Token
  - `Avg: ~tok/s`：最近回复的平均生成速度
- **附加统计**：按需展示 `artifacts`、`subagents`、`tasks`、`sandbox`（默认自动隐藏零值项）。
- **套餐与配额监控**：显示订阅计划（`plan`）以及 5 小时 / 7 天滚动力学配额进度条与重置时间。
- **自适应布局**：根据 `terminal_width` 自动切换宽屏、中屏、窄屏三种排版。

---

## 布局预览

### 宽屏（`>= 120` 列）

主信息与上下文条占第一行，遥测与附加统计占第二行，下方展示套餐与配额：

```text
● READY / Gemini 4 Hydrogen (High) / agy-statusline (main*)  │  Ctx: 136.4k/1.05M (9.8%) [█▒·············]
Turns: 29 (Compact: 0) │ Cache: 98.0% (105.3k) │ ΣTok: 2.02M │ Avg: ~164 tok/s
plan: Google AI Pro
gemini 5h ●●●●●●●●○○  82% ⟳ 05:31
gemini 7d ●●○○○○○○○○  24% ⟳ nov 25, 00:31
```

### 中屏（`100 ~ 119` 列）

两行圆角边框布局：

```text
╭─ ● READY / Gemini 4 Hydrogen (High) / agy-statusline (main*)
╰─ Ctx: 136.4k/1.05M (9.8%) [█▒·············] · Turns: 29 (Compact: 0) · Cache: 98.0% (105.3k) · ΣTok: 2.02M · Avg: ~164 tok/s
plan: Google AI Pro
gemini 5h ●●●●●●●●○○  82% ⟳ 05:31
gemini 7d ●●○○○○○○○○  24% ⟳ nov 25, 00:31
```

### 窄屏（`< 100` 列）

四行拆分布局，避免窄终端下信息错位：

```text
╭─ ● READY / Gemini 4 Hydrogen (High)
├─ agy-statusline (main*)
├─ Ctx: 136.4k/1.05M (9.8%) [█▒·············]
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

安装脚本会将状态栏脚本与默认配置复制到 `~/.gemini/`，并自动更新 `~/.gemini/antigravity-cli/settings.json` 中的 `statusLine` 配置。安装后重启 `agy` 即可生效。

### 3. 卸载

- Windows：`./bin/uninstall.ps1`
- Linux / macOS：`./bin/uninstall.sh`

---

## 配置项

可在 `~/.gemini/statusline.json` 中自定义显示开关（安装时默认生成，也可参考 [statusline.json.example](statusline.json.example)）：

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

| 平台          | 依赖                                |
| ------------- | ----------------------------------- |
| Windows       | PowerShell 5.1+（无额外外部依赖）   |
| Linux / macOS | `bash`、`jq`、`awk`（兼容 GNU/BSD） |

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
