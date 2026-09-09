# Codex Tray Manager

一个面向 Windows 的非官方托盘管理器，用于统一启动、切换、重启和关闭多个相互隔离的 Codex 桌面实例。

> This is an unofficial community tool and is not affiliated with or endorsed by OpenAI.

需要 Windows 10/11、PowerShell 7，以及一个或多个能够启动隔离 Codex 实例的 PowerShell 脚本。管理器通过每个实例唯一的 `--user-data-dir` 参数识别进程归属。

## 快速开始

```powershell
git clone https://github.com/son-gladyso/codex-tray-manager.git
cd codex-tray-manager
Copy-Item manager.settings.example.json manager.settings.json
notepad manager.settings.json
pwsh -NoProfile -File .\CodexTrayManager.ps1 -ValidateOnly
```

验证通过后双击 `Start Codex Tray Manager.cmd`。退出管理器不会关闭 Codex。

## 日常操作

- 统一管理配置中的 Codex 实例（编号范围 4–25），运行中的实例置顶。
- 同一实例可合并管理普通版和 UI 试点版。关闭处理两版；重启恢复之前运行的版本；都未运行时默认启动普通版。
- “启动 / 切换到前台”：启动后验证主进程；已有窗口时尝试恢复并核验前台状态。后台存在但没有窗口时会如实提示。
- “关闭（含应用后台）”：先请求窗口正常退出，最多等待 3 秒，再逐个结束经过身份核验的残留应用进程。
- “查看进程与关闭检查”：查看应用进程和待检查子任务的名称、PID、创建时间。
- “应急关闭（中断全部子任务）”：二次确认后结束所有已发现、可核验身份的子任务，包括更新脚本。只在明确要中断这些任务时使用。
- “关闭所有 Codex”：逐实例汇总结果；失败不影响后续实例处理。完整详情可从“查看最近操作结果”查看。

## 更新脚本与其他子任务

普通关闭和重启遇到无法确认用途的子任务时，会在发送关闭请求之前拦截并列出 PID。
更新脚本、终端、MCP 服务等不能仅凭父子关系都当作应用后台。当前确认的后台包括
同一应用目录的 Electron 进程、直接由 Electron 启动的 app-server，以及同目录的 code-mode host。
其余进程需要检查，不能根据名称包含 update 或 powershell 就推断用途。

**本版没有实现独立更新执行器或自动接管接口。** 拦截不等于接管，也不保证脚本一定能在
应用退出后继续执行。已脱离实例进程树的更新脚本无法由管理器自动识别；这类更新未完成前不要点重启。
请先核对具体脚本与执行方式，避免新旧脚本同时更新。应急关闭明确会中断仍在实例树内的任务。

## 更快的刷新与更稳妥的关闭

- Windows 原生快照获取进程关系和创建时间；只有发现新的应用身份时才查询启动参数。
- 参数缓存以 PID + 创建时间为键，进程退出即清理；父 PID 重用不会继承旧归属。
- 建立共享的进程、父子和用户目录索引；常规状态刷新不枚举窗口。
- 窗口查询、进程刷新、关闭等待和启动验证在独立工作线程执行；界面不再同步等待。
- 默认菜单关闭时每 10 秒刷新，菜单打开时每 2 秒刷新；打开菜单、点击刷新及操作完成后及时刷新。
- 关闭时保留已核验进程的句柄，追踪主进程退出后出现的孤立后台；最后检查全部已知目标。
- 不再调用 `taskkill /T`。每次强制结束均在同一个进程句柄上核验创建时间并执行终止。
- 操作期间禁用重复操作；权限错误、未完成关闭、启动超时和前台切换失败均有反馈。
- 单个启动脚本缺失不会阻止整个托盘启动。缺失的版本仍会在被启动时给出具体错误。

进程快照有时间边界；管理器启动前已经孤立且没有配置标记的后台，不能自动证明归属。
已观察的归属保留在当前管理器会话中，不跨管理器重启推断。Windows 也可能限制抢占前台，
因此切换失败会提示而非宣称成功。

## 配置与诊断

复制 `manager.settings.example.json` 为 `manager.settings.json`，再填写实例目录、各版本启动脚本/用户数据目录、图标及刷新和启动超时。本机配置已被 Git 忽略，不会随提交公开。至少配置一个实例；修改后重新启动管理器生效。配置会检查编号、版本、绝对路径和目录重复。
启动脚本、应用归档、登录、Codex 配置与工作区均不由管理器修改。

“打开诊断日志”进入 `logs`。`manager.jsonl` 保存操作结果、错误和耗时，超过 2 MB 滚动为
`manager.previous.jsonl`。日志不记录完整进程命令行或登录凭据。
配置/依赖导致的启动失败记录在 `startup-error.log`，并显示错误提示。

## 验证

```powershell
# 模拟回归，不关闭真实应用
pwsh -NoProfile -File .\tests\Test-CodexTrayManager.ps1

# 含临时进程、临时窗口的行为验证
pwsh -NoProfile -STA -File .\tests\Test-CodexTrayManager.ps1 -Integration

# 人为延迟后台工作，确认 UI 定时器仍能响应；自动退出
pwsh -NoProfile -STA -File .\CodexTrayManager.ps1 -SmokeTestSeconds 18 -SmokeWorkerDelaySeconds 3

# 完整刷新性能采样，须在具备本机进程查询权限的 PowerShell 中执行
pwsh -NoProfile -File .\tests\Measure-CodexTrayManager.ps1 -ModulePath "$PWD\CodexTrayManager.Core.psm1" -Iterations 20
```

## 缓存加固

缓存淘汰提前到身份查询之前，避免查询部分成功后抛错时跳过清理。每轮复用后台线程前清空
错误、警告等诊断流。主日志保留当前文件和一份轮换文件；启动错误日志超过 256 KB 后也轮换，
只保留一份上一文件。日志阈值允许最后一条记录带来小幅超出。

连续 1000 次部分失败与进程身份变化的回归场景中，旧逻辑积累 1000 条，新逻辑最多 1 条当前记录，
全部退出后为 0。

## 安全边界

普通关闭遇到无法确认用途的子任务时会拦截。菜单中的“应急关闭”会在二次确认后中断该实例树内所有已发现的任务，应仅在明确需要中断更新、终端或其他工作时使用。

## 许可证

本仓库目前未附带开源许可证。代码公开可见，但在添加许可证前不授予复制、修改或再分发权利。
