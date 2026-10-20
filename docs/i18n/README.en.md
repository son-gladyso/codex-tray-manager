# Codex Tray Manager

[简体中文](../../README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md)

**Multiple Codex instances, one tray entry. Find the window, understand what is running in the background, then decide how to close it.**

For users already running isolated launch scripts on Windows, Codex Tray Manager brings launching, switching, restarting, and closing together, reducing trips between the taskbar, scripts, and Task Manager. It manages existing instances; it does not create accounts, migrate chats, or set up an isolated environment for you.

> This is an unofficial community tool and is not affiliated with or endorsed by OpenAI.

Requires Windows 10/11, PowerShell 7, and one or more PowerShell scripts capable of launching isolated Codex instances. The manager identifies which instance a process belongs to using each instance's unique `--user-data-dir` argument.

[Quick start](#快速开始) · [Workflow](#先看一个典型使用流程) · [FAQ](#常见问题) · [Verification](#验证) · [Contributing](#一起改进)

<a id="它解决什么问题"></a>

## What problems does it solve?

When several isolated Codex desktop instances run on one Windows computer, users often have to switch between the taskbar, Task Manager, and multiple launch scripts. Hidden windows can be hard to find; a normal close may remove only the window and leave background processes running; terminating the entire process tree can accidentally kill update scripts waiting for the application to exit, terminals, or other tasks.

Codex Tray Manager provides a single tray entry and handles “the application's own background processes” separately from “child tasks whose purpose has not been confirmed.” Its main goals are to address:

- The lack of a unified status view and controls for multiple Codex instances.
- Difficulty locating and bringing hidden windows or windowless background processes to the foreground.
- Electron, app-server, and other background processes that may remain after a normal exit.
- Updates, terminals, or ongoing work interrupted by indiscriminately terminating a process tree.
- Difficulty restoring the previously running version combination when restarting multi-version instances.

<a id="功能概览"></a>

## Feature overview

- Builds instance menus dynamically from JSON configuration and moves running instances to the top.
- Verifies that the main process is running stably after launch, rather than reporting success solely from the launch script's return value.
- Enumerates hidden top-level Electron windows, attempts to restore and foreground them, and verifies the outcome.
- Requests a normal window exit first, then individually verifies and cleans up residual processes confirmed to belong to the application.
- Binds process identity to both PID and creation time to reduce the risk of acting on a reused PID.
- Blocks normal closing when child tasks of unknown purpose are found, displaying their names, PIDs, and creation times for inspection.
- Provides emergency closing with a second confirmation and bulk closing with per-instance result summaries.
- Supports `Standard` and `UICanary` versions, restoring the previously running versions on restart.
- Refreshes status and waits for closing on background threads to keep the tray menu responsive.
- Writes automatically rotated JSONL diagnostic logs without recording full process command lines or login credentials.

<a id="先看一个典型使用流程"></a>

## A typical workflow

1. Configure at least one isolated instance first; when configuring several, ensure each has a different user data directory.
2. Check which instances are running from the tray, then bring the required window to the foreground.
3. Before exiting, inspect the processes and close checks to distinguish application background processes from child tasks with unconfirmed purposes.
4. Use normal closing. If the check finds unconfirmed tasks, investigate first rather than bypassing the check with emergency closing.
5. Review recent operation results to confirm what actually completed.

This page does not yet include screenshots or recordings of the tray menu on a real machine. The above describes the workflow, not an already recorded demonstration, and does not imply that every launch script and Windows environment has been verified.

<a id="快速开始"></a>

## Quick start

Prepare three prerequisites:

- Windows 10/11 and PowerShell 7 (`pwsh`), not just the older Windows PowerShell.
- An existing PowerShell script that can launch the target Codex independently.
- Absolute launch script paths and unique user data directories for each version. Do not copy example paths such as `D:\codex4` unchanged.

If the launch script itself does not work yet, fix it before integrating it with the tray manager.

Regular users can download the portable Windows ZIP from [Releases](https://github.com/son-gladyso/codex-tray-manager/releases), extract it, copy `manager.settings.example.json` to `manager.settings.json`, and enter their local paths.

Developers can also clone the repository:

```powershell
git clone https://github.com/son-gladyso/codex-tray-manager.git
cd codex-tray-manager
Copy-Item manager.settings.example.json manager.settings.json
notepad manager.settings.json
pwsh -NoProfile -File .\CodexTrayManager.ps1 -ValidateOnly
```

After validation passes, double-click `Start Codex Tray Manager.cmd`. Exiting the manager does not close Codex.

**Your first success criterion:** the tray menu shows your configured instances and, after a status refresh, distinguishes running from stopped instances. Try “Bring to foreground” on a running, visible test instance, then check the operation result. Passing configuration validation does not mean that window switching or closing has passed real-machine acceptance testing. Familiarize yourself with the checks and result messages before trying to close instances.

<a id="日常操作"></a>

## Everyday operations

- Manage the configured Codex instances together (numbers 4–25), with running instances at the top.
- Manage the standard and UI canary versions together under one instance. Closing handles both; restarting restores the versions that were running; if neither is running, the standard version starts by default.
- “Launch / Bring to foreground”: verifies the main process after launch; if a window already exists, attempts to restore it and verifies foreground status. Reports honestly when background processes exist but no window is available.
- “Close (including application background processes)”: requests a normal window exit, waits up to 3 seconds, then terminates remaining application processes one by one after verifying their identities.
- “View processes and close checks”: shows the names, PIDs, and creation times of application processes and child tasks requiring inspection.
- “Emergency close (interrupt all child tasks)”: after a second confirmation, terminates all discovered child tasks whose identities can be verified, including update scripts. Use only when you explicitly intend to interrupt these tasks.
- “Close all Codex”: summarizes results per instance; failure on one does not prevent processing later instances. Full details are available under “View recent operation results.”

<a id="更新脚本与其他子任务"></a>

## Update scripts and other child tasks

If normal closing or restarting encounters child tasks whose purposes cannot be confirmed, it blocks before sending a close request and lists their PIDs.
Update scripts, terminals, MCP services, and similar processes cannot all be treated as application background processes merely because of parent-child relationships. Currently confirmed background processes include Electron processes in the same application directory, app-server launched directly by Electron, and code-mode host in the same directory. Other processes require inspection; their purpose cannot be inferred just because their name contains update or powershell.

**This version does not implement an independent update executor or an automatic handover interface.** Blocking is not taking over, nor does it guarantee that a script can continue after the application exits. Update scripts that have detached from the instance's process tree cannot be identified automatically by the manager; do not click restart until those updates finish. Check the specific script and how it runs first to avoid old and new scripts updating concurrently. Emergency closing explicitly interrupts tasks still within the instance tree.

<a id="更快的刷新与更稳妥的关闭"></a>

## Faster refreshes and safer closing

- Uses native Windows snapshots to obtain process relationships and creation times; launch arguments are queried only when a new application identity is discovered.
- Keys the argument cache by PID + creation time and removes entries when processes exit; reused parent PIDs do not inherit old ownership.
- Builds shared process, parent-child, and user-directory indexes; routine status refreshes do not enumerate windows.
- Runs window queries, process refreshes, close waits, and launch verification on separate worker threads; the interface no longer waits synchronously.
- By default, refreshes every 10 seconds with the menu closed and every 2 seconds with it open; also refreshes promptly on menu opening, manual refresh, and operation completion.
- Retains handles to verified processes while closing to track orphaned background processes appearing after the main process exits; checks all known targets at the end.
- No longer calls `taskkill /T`. Every forced termination verifies creation time and terminates using the same process handle.
- Disables duplicate actions while an operation is in progress; provides feedback for permission errors, incomplete closing, launch timeouts, and failed foreground switching.
- A missing launch script does not prevent the entire tray manager from starting. Attempting to launch the affected version still produces a specific error.

Process snapshots have temporal limits. Background processes already orphaned before the manager started and lacking configuration markers cannot have their ownership established automatically. Observed ownership is retained only in the current manager session and is not inferred across manager restarts. Windows may also restrict foreground activation, so failed switching is reported instead of being claimed as successful.

<a id="配置与诊断"></a>

## Configuration and diagnostics

Copy `manager.settings.example.json` to `manager.settings.json`, then enter instance directories, per-version launch scripts/user data directories, icons, refresh intervals, and launch timeouts. The default local configuration path is ignored by Git; still inspect the staging area before committing to avoid exposing private configuration that was already tracked, force-added, or saved elsewhere. Configure at least one instance; restart the manager for changes to take effect. Validation checks numbers, versions, absolute paths, and duplicate directories. The manager does not modify launch scripts, application archives, logins, Codex configuration, or workspaces.

“Open diagnostic logs” opens `logs`. `manager.jsonl` stores operation results, errors, and durations and rotates to `manager.previous.jsonl` when it exceeds 2 MB. Logs do not record full process command lines or login credentials. Startup failures caused by configuration or dependencies are recorded in `startup-error.log` and shown in an error message.

<a id="常见问题"></a>

## FAQ

**Can it create isolated instances or switch accounts for me?** No. Prepare your own launch scripts and separate user data directories first. The manager does not modify logins, Codex configuration, or workspaces.

**Does exiting the manager close my working instances too?** No. Exiting the tray manager and closing Codex instances are separate operations.

**Why was normal closing blocked?** Child tasks with unconfirmed purposes were found. Inspect their names, PIDs, and creation times first to determine whether they are updates, terminals, or other work. Do not use emergency closing simply to get rid of the warning.

**The menu says background processes are running. Why can I not find a window?** Only windowless background processes may remain, or Windows may have restricted foreground switching. Review the operation result: the existence of a process is not equivalent to an available window.

**Why have my configuration changes not taken effect?** Restart the manager after changing your local `manager.settings.json`. First use `-ValidateOnly` to check numbers, versions, and paths.

**Can update scripts automatically be handed over to the manager to continue running?** No. There is currently no independent update executor or handover interface. See [Update scripts and other child tasks](#更新脚本与其他子任务).

<a id="开发者从哪里读起"></a>

## Where developers should start

| File | Focus | Key checks when changing it |
| --- | --- | --- |
| `CodexTrayManager.ps1` | Tray entry and operation orchestration | Repeated clicks, background waits, error feedback, and menu responsiveness. |
| `CodexTrayManager.Core.psm1` | Shared management logic | Regression behavior for configuration, ownership, and operation results. |
| `CodexTrayManager.Native.cs` / `CodexTrayManager.Process.cs` | Native Windows process and window boundaries | Process identity, exit races, and permission failures, not only the happy path. |
| `manager.settings.example.json` | Configuration example | Use fictional paths and support single-instance and multi-version configurations. |
| `tests/` | Mocks, integration, and performance sampling | Distinguish passing mocks, temporary-process verification, and observations in everyday environments. |

<a id="验证"></a>

## Verification

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

<a id="缓存加固"></a>

## Cache hardening

Cache eviction now runs before identity queries, avoiding skipped cleanup when a query partially succeeds and then throws. Diagnostic streams such as errors and warnings are cleared before the background worker is reused each round. The main log retains the current file and one rotated file; the startup error log also rotates above 256 KB and retains only one previous file. The final record may push log size slightly above the threshold.

In a regression scenario involving 1000 consecutive partial failures and process identity changes, the old logic accumulated 1000 entries; the new logic retains at most 1 current entry, and 0 after all processes exit.

<a id="安全边界"></a>

## Safety boundaries

Normal closing is blocked when child tasks of unconfirmed purpose are encountered. After a second confirmation, the menu's “Emergency close” interrupts all discovered tasks within that instance tree. Use it only when you explicitly need to interrupt updates, terminals, or other work.

<a id="一起改进"></a>

## Contributing

Focused documentation fixes, issue reproductions, and regression tests are welcome. You do not need to know the whole project to start with a specific scenario:

- Improve messages for configuration errors, launch timeouts, or failed switching.
- Add regression tests for PID reuse, hidden windows, unknown child tasks, and similar cases.
- Check operation results across Windows environments and document versions and reproduction steps.
- Make quick-start and diagnostic steps easier to follow.

Read “Verification” and “Safety boundaries” first. For changes involving process ownership or closing logic, prioritize mocks and temporary-process tests rather than acting on everyday working instances by default. In a PR, explain the issue, changes, checks actually run, and anything still unverified. Discuss larger behavior changes in [Issues](https://github.com/son-gladyso/codex-tray-manager/issues) first.

Do not submit real configurations, account information, full command lines, or diagnostic screenshots containing private paths. Contributions must not “fix” failures by weakening identity checks, skipping confirmations, or forcibly terminating unknown tasks.

<a id="许可证"></a>

## License

This project uses the [MIT License](../../LICENSE). You may use, copy, modify, merge, publish, and distribute it, provided you retain the original copyright and permission notices. The software is provided “as is,” without warranty of any kind.
