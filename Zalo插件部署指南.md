# Hermes Zalo 插件部署指南

本文档用于在当前 Windows 机器上部署 `hermes-zalo-plugin`，把本地 Hermes Agent 连接到个人 Zalo 账号。

> 注意：本插件使用 `zca-js` 的非官方 Zalo 个人账号 API。建议使用备用 Zalo 账号，避免主账号因自动化行为被限流或锁定。

## 1. 当前部署目标

- 插件源码目录：`D:\Workspaces\AI\hermes-zalo-plugin`
- Hermes home：`C:\Users\Administrator\AppData\Local\hermes`
- Hermes CLI：`C:\Users\Administrator\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe`
- Zalo bridge 地址：`http://127.0.0.1:8787`
- Zalo bridge 运行方式：Windows 计划任务 `HermesZaloPlugin`
- Hermes gateway 运行方式：Windows 计划任务 `Hermes_Gateway`，通过 `C:\Users\Administrator\AppData\Local\hermes\gateway-service\Hermes_Gateway_hidden.ps1` 隐藏启动
- Zalo 登录数据目录：`C:\Users\Administrator\.hermes-zalo`
- Zalo bridge 日志：`C:\Users\Administrator\.hermes-zalo\bridge.log`、`bridge.err.log`

## 2. 前置检查

在 PowerShell 中执行：

```powershell
node -v
npm -v
hermes version
```

要求：

- Node.js 版本不低于 18。
- npm 可用。
- `hermes` 命令可用。

当前机器已验证：

- 默认 Node.js：`v22.16.0`
- Zalo 登录与后台 bridge：`v20.19.0`
- npm：`10.9.2`
- Hermes：`v0.17.0`

当前机器需要通过 `127.0.0.1:7890` 代理访问部分 Zalo Web 域名。Node.js 默认 `fetch` 不会自动使用 Windows 系统代理，所以本部署使用 `scripts/register-node-proxy.mjs` 预加载 `undici` 代理，再启动登录诊断或 bridge。

## 3. 安装 Zalo bridge 和 Hermes 插件

进入项目目录，并显式指定 Hermes home：

```powershell
cd D:\Workspaces\AI\hermes-zalo-plugin
$env:HERMES_HOME = "$env:LOCALAPPDATA\hermes"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

安装依赖并启动安装流程：

```powershell
npm ci
.\install.ps1
```

安装流程会执行：

1. 安装 Node 依赖。
2. 通过 QR 登录 Zalo。
3. 将登录凭据保存到 `C:\Users\Administrator\.hermes-zalo\credentials.json`。
4. 注册 Windows 计划任务 `HermesZaloPlugin`。
5. 将 `hermes-plugin\` 复制到 `C:\Users\Administrator\AppData\Local\hermes\plugins\zalo`。
6. 在 Hermes `config.yaml` 中启用 `zalo-platform`。

如果只想重装后台任务和 Hermes 插件，不重新扫码：

```powershell
.\install.ps1 --service-only
```

如果 Windows `schtasks` 因脚本路径参数解析失败导致计划任务没有创建，可用 PowerShell 原生命令手动注册：

```powershell
$taskName = "HermesZaloPlugin"
$cwd = "D:\Workspaces\AI\hermes-zalo-plugin"
$script = Join-Path $cwd "scripts\run-bridge-hidden.ps1"
$powerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$action = New-ScheduledTaskAction -Execute $powerShell -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script) -WorkingDirectory $cwd
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Hermes Zalo Plugin bridge (hidden background)" -Force
```

后台任务会通过 `scripts\run-bridge-hidden.ps1` 启动 Node 20，并把输出写入：

```powershell
$env:USERPROFILE\.hermes-zalo\bridge.log
$env:USERPROFILE\.hermes-zalo\bridge.err.log
```

> 注意：Node 20 的 `--import` 在 Windows 上不要写 `D:\...` 绝对路径，否则会报 `ERR_UNSUPPORTED_ESM_URL_SCHEME`。wrapper 内部依赖项目工作目录，所以使用 `./scripts/register-node-proxy.mjs` 相对路径。

`run-bridge-hidden.ps1` 会守护 Node bridge：如果 bridge 以非 0 退出，会等待 5 秒后自动重启；如果 bridge 正常退出码为 0，则 wrapper 也会停止。

计划任务 `HermesZaloPlugin` 应保持无执行时间上限：

```powershell
Get-ScheduledTask -TaskName HermesZaloPlugin | Select-Object -ExpandProperty Settings | Format-List ExecutionTimeLimit
```

期望值是 `PT0S`。如果不是，可重新设置：

```powershell
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Set-ScheduledTask -TaskName HermesZaloPlugin -Settings $settings
```

如果需要强制重新扫码登录：

```powershell
.\install.ps1 --relogin
```

## 4. 启动并验证 Zalo bridge

启动计划任务：

```powershell
schtasks /Run /TN HermesZaloPlugin
Start-Sleep 3
```

验证 bridge 健康状态：

```powershell
Invoke-RestMethod http://127.0.0.1:8787/health | ConvertTo-Json -Depth 5
```

期望看到：

```json
{
  "ok": true,
  "loggedIn": true,
  "sessionDead": false
}
```

如果 `loggedIn` 为 `false`，打开 QR 图片并扫码：

```powershell
Start-Process "$env:USERPROFILE\.hermes-zalo\qr.png"
```

扫码确认后再次验证 `/health`。

## 5. 安装 Hermes adapter 依赖

Zalo adapter 通过 `aiohttp` 连接本地 bridge：

```powershell
& "$env:LOCALAPPDATA\hermes\hermes-agent\venv\Scripts\python.exe" -m pip install aiohttp
```

## 6. 配置 Hermes 连接 Zalo

执行 Hermes 网关配置向导：

```powershell
hermes gateway setup
```

选择 `Zalo` 后，推荐配置如下：

| 配置项 | 推荐值 |
| --- | --- |
| Bridge URL | `http://127.0.0.1:8787` |
| Bridge token | 留空，除非 bridge 设置了 `ZALO_PLUGIN_TOKEN` |
| Allowed users | 可先留空，表示允许所有私聊用户 |
| Allowed threads/groups | 按向导搜索选择；不选群通常表示不响应群聊 |
| Group mode | `mention` |
| Action groups | `read,send,interact` |
| Destructive actions | `false` |

配置完成后启动 Hermes gateway：

```powershell
hermes gateway
```

当前 Windows 机器已经安装过 Hermes gateway 计划任务，也可以用后台方式启动和检查：

```powershell
hermes gateway start
hermes gateway status
hermes logs --since 5m
```

本机的 `Hermes_Gateway` 计划任务已改为隐藏后台启动，不再直接执行 `Hermes_Gateway.cmd`，因此正常情况下不会留下黑色 `cmd.exe` 窗口。

本次自动部署也可以不跑交互向导，直接在 `C:\Users\Administrator\AppData\Local\hermes\.env` 写入最小配置：

```powershell
ZALO_PLUGIN_URL=http://127.0.0.1:8787
ZALO_PLUGIN_TOKEN=
ZALO_ALLOWED_USERS=
ZALO_ALLOWED_THREADS=
ZALO_GROUP_MODE=off
ZALO_LOG_IDS=true
ZALO_ALLOWED_ACTION_GROUPS=read,send,interact
ZALO_ALLOW_DESTRUCTIVE=false
ZALO_ALLOWED_ACTIONS=
ZALO_DENIED_ACTIONS=
```

其中 `ZALO_GROUP_MODE=off` 表示先只启用私聊，不响应群聊；需要群聊时可改为 `mention`。

## 7. 控制哪些 Zalo 消息交给 Hermes

默认最小配置中：

```powershell
ZALO_ALLOWED_USERS=
ZALO_ALLOWED_THREADS=
ZALO_GROUP_MODE=off
```

含义是：

- 私聊：允许所有私聊用户触发 Hermes。
- 群聊：不处理群消息。
- 自己发出的消息：adapter 会忽略，不会让 Hermes 处理自己的消息。

如果不想让 Hermes 接管所有 Zalo 私聊，推荐改成白名单模式，只允许指定联系人或指定会话触发 Hermes。

### 只允许指定联系人

先让允许接管的联系人给当前 Zalo 账号发一条私聊消息，然后查看日志：

```powershell
hermes logs --since 10m
```

找到类似日志：

```text
Zalo inbound: uid=123456 name='Alice' threadId=123456 type=dm
```

把 `uid` 写入 `C:\Users\Administrator\AppData\Local\hermes\.env`：

```powershell
ZALO_ALLOWED_USERS=123456
ZALO_ALLOWED_THREADS=
```

多个用户用英文逗号分隔：

```powershell
ZALO_ALLOWED_USERS=123456,789012
```

保存后重启 Hermes gateway：

```powershell
hermes gateway restart
```

这样不在 `ZALO_ALLOWED_USERS` 里的联系人发消息，Hermes 会忽略。

### 只允许指定会话

如果希望按会话限制，而不是按联系人限制，可使用 `threadId`：

```powershell
ZALO_ALLOWED_USERS=
ZALO_ALLOWED_THREADS=123456
```

多个会话同样用英文逗号分隔。私聊和群聊都可以通过 `threadId` 控制。

### 临时停用 Zalo 接管

如果只是临时不让 Hermes 处理任何 Zalo 消息，可以停掉 Zalo bridge：

```powershell
Stop-ScheduledTask -TaskName HermesZaloPlugin
```

恢复时重新启动：

```powershell
schtasks /Run /TN HermesZaloPlugin
```

## 8. 使用方式

- 私聊：用另一个 Zalo 账号给“扫码登录的 Zalo 账号”发消息。
- 群聊：把扫码登录的 Zalo 账号拉进群；若 `ZALO_GROUP_MODE=mention`，需要 @ 它或回复它的消息才会触发 Hermes。
- 图片、文件、语音：插件支持 Zalo 到 Hermes 的媒体接收，也支持 Hermes 向 Zalo 发送图片、文件和音频附件；公网音频 URL 可作为 Zalo voice 发送。

## 9. 常用维护命令

前台启动 bridge，适合临时排错，会显示一个 Node 控制台窗口：

```powershell
cd D:\Workspaces\AI\hermes-zalo-plugin
& "$env:LOCALAPPDATA\nvm\v20.19.0\node.exe" --import ./scripts/register-node-proxy.mjs ./server.js
```

后台启动 bridge：

```powershell
schtasks /Run /TN HermesZaloPlugin
```

查看 bridge 状态：

```powershell
Invoke-RestMethod http://127.0.0.1:8787/health | ConvertTo-Json -Depth 5
```

查看 bridge 后台日志：

```powershell
Get-Content "$env:USERPROFILE\.hermes-zalo\bridge.log" -Tail 80
Get-Content "$env:USERPROFILE\.hermes-zalo\bridge.err.log" -Tail 80
```

查看 Windows 计划任务：

```powershell
schtasks /Query /TN HermesZaloPlugin /FO LIST
schtasks /Query /TN Hermes_Gateway /FO LIST
```

查看 Hermes gateway 状态与日志：

```powershell
hermes gateway status
hermes logs --since 5m
```

`Get-ScheduledTaskInfo` 返回的 `LastTaskResult=267009` 通常表示任务正在运行；只要 `/health` 可访问，就说明 bridge 已启动。

停止并移除后台任务，保留登录凭据：

```powershell
node uninstall.mjs
```

停止并移除后台任务，同时删除 Zalo 登录凭据：

```powershell
node uninstall.mjs --purge
```

重新扫码登录：

```powershell
.\install.ps1 --relogin
```

重新安装后台任务和 Hermes 插件：

```powershell
.\install.ps1 --service-only
```

## 10. 常见问题

### `/health` 显示 `loggedIn:false`

说明 bridge 运行了，但 Zalo 尚未登录或凭据失效。执行：

```powershell
.\install.ps1 --relogin
```

然后扫码确认。

### 扫码显示无效 QR Code

优先按“二维码过期或界面缓存”处理：

1. Zalo QR 登录码大约 100 秒过期。
2. Codex 或图片查看器可能缓存同名 `qr.png`，导致看到的是旧码。
3. 重新启动登录流程后，把当前 `qr.png` 复制成带时间戳的新文件再扫码：

```powershell
cd D:\Workspaces\AI\hermes-zalo-plugin
node login.mjs --force

# 另开一个 PowerShell，在 QR 生成后复制当前图片：
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item "$env:USERPROFILE\.hermes-zalo\qr.png" "$env:USERPROFILE\.hermes-zalo\qr-$stamp.png" -Force
Start-Process "$env:USERPROFILE\.hermes-zalo\qr-$stamp.png"
```

扫码时必须在手机端点击确认登录。如果日志显示 `QR scanned by ...` 后仍失败：

```text
Cannot get session, login failed
```

说明二维码已被识别，但 `zca-js` 没有从 Zalo 获取到 Web session。当前本机最终定位到的关键问题是：Node 直连 `https://jr.zaloapp.com/` 超时，而 PowerShell 通过系统代理可以访问；需要让 Node 显式走代理。

先确认代理预加载可用：

```powershell
cd D:\Workspaces\AI\hermes-zalo-plugin
& "$env:LOCALAPPDATA\nvm\v20.19.0\node.exe" --import ./scripts/register-node-proxy.mjs -e "fetch('https://jr.zaloapp.com/', { signal: AbortSignal.timeout(10000) }).then(r => console.log(r.status))"
```

期望输出包含：

```text
[node-proxy] using http://127.0.0.1:7890
404
```

然后用 Node 20 + 代理生成新的诊断二维码：

```powershell
$out = "$env:USERPROFILE\.hermes-zalo\login-node20-proxy-diagnostic.log"
$err = "$env:USERPROFILE\.hermes-zalo\login-node20-proxy-diagnostic.err.log"
Start-Process -FilePath "$env:LOCALAPPDATA\nvm\v20.19.0\node.exe" `
  -ArgumentList "--import ./scripts/register-node-proxy.mjs ./scripts/diagnose-login-node20.mjs" `
  -WorkingDirectory "D:\Workspaces\AI\hermes-zalo-plugin" `
  -RedirectStandardOutput $out `
  -RedirectStandardError $err
Start-Sleep 5
Copy-Item "$env:USERPROFILE\.hermes-zalo\qr-node20-diagnostic-live.png" "$env:USERPROFILE\.hermes-zalo\qr-node20-proxy-diagnostic.png" -Force
Start-Process "$env:USERPROFILE\.hermes-zalo\qr-node20-proxy-diagnostic.png"
```

扫码并在手机端确认后，检查是否生成凭据：

```powershell
Test-Path "$env:USERPROFILE\.hermes-zalo\credentials.json"
Get-Content "$env:USERPROFILE\.hermes-zalo\login-node20-proxy-diagnostic.log" -Tail 30
```

如果仍失败，再尝试：

- 在手机 Zalo 中确认是否允许网页登录/PC 登录。
- 使用备用 Zalo 账号重试。
- 确认手机端点了“确认/同意登录”，不是只扫码。
- 稍后重试，避免连续扫码触发风控。
- 关注 `zca-js` 新版本或登录相关 issue。

### `/health` 显示 `sessionDead:true`

说明账号可能在别处登录、cookie 过期或被 Zalo 踢下线。重新扫码：

```powershell
.\install.ps1 --relogin
```

### Hermes 收不到 Zalo 消息

按顺序检查：

```powershell
Invoke-RestMethod http://127.0.0.1:8787/health | ConvertTo-Json -Depth 5
Test-Path "$env:LOCALAPPDATA\hermes\plugins\zalo\adapter.py"
Select-String -Path "$env:LOCALAPPDATA\hermes\.env" -Pattern "ZALO_"
hermes gateway
```

重点确认：

- bridge 已运行并 `loggedIn=true`。
- Hermes 插件目录存在。
- `.env` 中有 `ZALO_PLUGIN_URL=http://127.0.0.1:8787`。
- 群聊场景下已按 `ZALO_GROUP_MODE` 规则 @ 或回复 bot。

### 日志里反复出现 `Zalo: SSE disconnected`

如果 Hermes 日志出现：

```text
Zalo: SSE disconnected (Cannot connect to host 127.0.0.1:8787 ...); reconnecting in 30.0s
```

含义是 Hermes gateway 仍在运行，但 Zalo bridge 没有在 `127.0.0.1:8787` 监听。先启动 bridge：

```powershell
schtasks /Run /TN HermesZaloPlugin
Start-Sleep 10
Invoke-RestMethod http://127.0.0.1:8787/health | ConvertTo-Json -Depth 5
```

恢复后应看到 `loggedIn=true`、`sessionDead=false`，并且 `sseClients` 至少为 `1`。如果仍失败，查看 bridge 日志：

```powershell
Get-Content "$env:USERPROFILE\.hermes-zalo\bridge.log" -Tail 80
Get-Content "$env:USERPROFILE\.hermes-zalo\bridge.err.log" -Tail 80
```
