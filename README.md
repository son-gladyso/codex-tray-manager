# Codex Tray Manager

[简体中文](README.md) · [English](docs/i18n/README.en.md) · [日本語](docs/i18n/README.ja.md) · [한국어](docs/i18n/README.ko.md) · [Español](docs/i18n/README.es.md) · [Français](docs/i18n/README.fr.md) · [Deutsch](docs/i18n/README.de.md) · [Português (Brasil)](docs/i18n/README.pt-BR.md) · [Русский](docs/i18n/README.ru.md) · [繁體中文](docs/i18n/README.zh-TW.md)

*其他语言版本可能滞后于本页。*

> 你开了 6 个隔离的 Codex 实例。其中一个窗口不见了，任务管理器里有 14 个 `Codex.exe`，还有个 PowerShell 不知道是不是正在跑的更新脚本。你想关掉第 7 号——但不想顺手把别的东西也杀了。
>
> **一个托盘图标管住所有实例：找到窗口、看清后台，再决定怎么关。** 拿不准用途的进程，它会拦下来先问你，而不是一刀切。

> This is an unofficial community tool and is not affiliated with or endorsed by OpenAI.

Windows 10/11 · PowerShell 7 · MIT 许可。管理**已有的**隔离实例，不负责创建账号、迁移聊天或替你搭隔离环境。

---

## 👋 给人读的部分

### 它解决的痛点

- 多个实例没有统一的运行状态和入口。
- 窗口被隐藏、或只剩无窗口后台时，找不回来。
- 点了关闭，Electron、app-server 之类的后台却还在。
- 直接结束整个进程树，可能误杀正在等应用退出的更新脚本或终端。
- 多版本实例重启后，记不起原来跑的是哪个版本组合。

### 它能做什么

- **一个菜单看全部**：按 JSON 配置生成实例菜单（编号 4–25），运行中的置顶。
- **真的启动了才算成功**：启动后核验主进程稳定运行，不看脚本返回值就报喜。
- **把窗口找回来**：枚举隐藏的 Electron 顶层窗口，恢复到前台并核验结果；只剩后台时如实告诉你。
- **干净地关**：先请求窗口正常退出（最多等 3 秒），再逐一清理**核验过身份**的残留应用进程。
- **不误杀**：进程身份 = PID + 创建时间，PID 被复用也不会认错。用途不明的子任务会拦截普通关闭，并列出名称、PID、创建时间。
- **双版本**：同一实例可合并管理 `Standard` 和 `UICanary`，重启时恢复之前在跑的版本。
- **托盘不卡**：状态刷新、关闭等待都在后台线程；菜单关闭时每 10 秒刷新，打开时每 2 秒。
- **有据可查**：自动轮换的 JSONL 诊断日志，不记录完整命令行或登录凭据。

### 快速开始

准备三样东西：

1. Windows 10/11 + **PowerShell 7（`pwsh`）**——旧版 Windows PowerShell 不行。
2. 能独立启动目标 Codex 的 PowerShell 脚本（脚本自己都起不来的话，先修脚本）。
3. 每个版本的**绝对**脚本路径和**唯一**用户数据目录（管理器靠 `--user-data-dir` 认领进程；示例里的 `D:\codex4` 别照抄）。

**普通用户**：从 [Releases](https://github.com/son-gladyso/codex-tray-manager/releases) 下载便携版 ZIP，解压，把 `manager.settings.example.json` 复制为 `manager.settings.json` 并填路径。

**开发者**：

```powershell
git clone https://github.com/son-gladyso/codex-tray-manager.git
cd codex-tray-manager
Copy-Item manager.settings.example.json manager.settings.json
notepad manager.settings.json
pwsh -NoProfile -File .\CodexTrayManager.ps1 -ValidateOnly
```

验证通过后双击 `Start Codex Tray Manager.cmd`。**退出管理器不会关闭 Codex。**

**第一次成功**：托盘显示你配置的实例，能区分运行 / 未运行；对一个可见的测试实例点"切换到前台"，再看操作结果。先熟悉检查和结果提示，再去碰关闭。

### 菜单里的几个按钮

| 操作 | 会发生什么 |
|---|---|
| 启动 / 切换到前台 | 没运行就启动并核验；有窗口就恢复并核验前台状态 |
| 关闭（含应用后台） | 正常退出请求 → 等待 ≤3 秒 → 清理核验过的残留应用进程 |
| 查看进程与关闭检查 | 列出应用进程和待检查子任务 |
| **应急关闭（中断全部子任务）** | 二次确认后结束实例树内所有可核验的子任务，**包括更新脚本**。只在你确实要中断它们时用 |
| 关闭所有 Codex | 逐实例处理并汇总，一个失败不影响下一个 |

### 关于更新脚本（请读一下）

普通关闭遇到用途不明的子任务，会在发出关闭请求**之前**拦截。目前认定为"应用自己的后台"的只有：同应用目录的 Electron 进程、Electron 直接启动的 app-server、同目录的 code-mode host。名字里带 update 或 powershell **不会**被当作依据。

**本版没有更新执行器，也没有接管接口。** 拦截 ≠ 接管，不保证脚本在应用退出后还能继续。已经脱离实例进程树的更新脚本识别不到——这类更新没完成前，别点重启。

### 常见问题

**能帮我创建隔离实例或切账号吗？** 不能。它不改登录、Codex 配置或工作区。
**普通关闭为什么被拦？** 有用途未确认的子任务。先看清是什么，别为了消掉提示就用应急关闭。
**显示在运行，却找不到窗口？** 可能只剩无窗口后台，或 Windows 限制了抢前台。进程存在 ≠ 窗口可用。
**改了配置没生效？** 重启管理器；先用 `-ValidateOnly` 检查。

### 配置与日志

配置会检查编号、版本、绝对路径和目录重复；至少一个实例；单个启动脚本缺失不会让整个托盘起不来。`manager.settings.json` 默认被 Git 忽略，但提交前仍请检查暂存区。

"打开诊断日志"进入 `logs/`：`manager.jsonl`（操作结果、错误、耗时，超过 2 MB 滚动为 `manager.previous.jsonl`）和 `startup-error.log`（超过 256 KB 轮换）。

### 参与改进

欢迎范围明确的文档修正、问题复现和回归测试：更清楚的错误提示、PID 复用 / 隐藏窗口 / 未知子任务的测试、不同 Windows 环境下的复现记录。大改动先开 [Issue](https://github.com/son-gladyso/codex-tray-manager/issues)。不要提交真实配置、账号资料、完整命令行或含私人路径的截图。

本页暂无托盘实机截图或录像。

### 许可证

[MIT License](LICENSE)。

---

## 🤖 给 AI 读的部分

**代码地图：**

| 文件 | 职责 | 改动时重点检查 |
| --- | --- | --- |
| `CodexTrayManager.ps1` | 托盘入口、菜单与操作编排 | 重复点击、后台等待、错误反馈、菜单响应 |
| `CodexTrayManager.Core.psm1` | 配置、归属判定、操作结果 | 回归行为 |
| `CodexTrayManager.Native.cs` / `CodexTrayManager.Process.cs` | 原生进程快照、窗口、终止 | 进程身份、退出竞态、权限失败 |
| `manager.settings.example.json` | 配置样例 | 虚构路径；兼容单实例与多版本 |
| `tests/` | 模拟、集成、性能采样 | 区分模拟通过 / 临时进程验证 / 日常环境观察 |

**安全不变量——不得为"修复失败"而放宽：**

- 进程身份始终是 PID + 创建时间；强制结束前在**同一句柄**上再次核验创建时间。不要重新引入 `taskkill /T`。
- 归属判定只认配置的 `--user-data-dir` 与已列明的三类后台；不能按进程名推断用途。不跨管理器重启推断归属。
- 用途不明的子任务必须拦截普通关闭；应急关闭必须保留二次确认。
- 前台切换失败要如实反馈，不能宣称成功。
- 管理器不修改启动脚本、应用归档、登录、Codex 配置或工作区。
- 日志不得写入完整命令行或凭据。
- 测试优先用模拟和临时进程，**不要默认操作用户的日常工作实例**。

**验证：**

```powershell
pwsh -NoProfile -File .\tests\Test-CodexTrayManager.ps1                    # 模拟回归，不关真实应用
pwsh -NoProfile -STA -File .\tests\Test-CodexTrayManager.ps1 -Integration  # 临时进程 / 临时窗口
pwsh -NoProfile -STA -File .\CodexTrayManager.ps1 -SmokeTestSeconds 18 -SmokeWorkerDelaySeconds 3   # UI 响应性冒烟，自动退出
pwsh -NoProfile -File .\tests\Measure-CodexTrayManager.ps1 -ModulePath "$PWD\CodexTrayManager.Core.psm1" -Iterations 20   # 刷新性能采样
```

**已知设计细节：** 缓存以 PID + 创建时间为键，淘汰在身份查询之前执行（1000 次部分失败回归中最多残留 1 条）；常规刷新不枚举窗口；只有发现新应用身份才查询启动参数。PR 中写清：问题、改动、实际运行的检查、未验证的情况。
