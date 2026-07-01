$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Node20 = Join-Path $env:LOCALAPPDATA "nvm\v20.19.0\node.exe"

if (!(Test-Path -LiteralPath $Node20)) {
  $Node20 = (Get-Command node).Source
}

$LogDir = Join-Path $env:USERPROFILE ".hermes-zalo"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$OutLog = Join-Path $LogDir "bridge.log"
$ErrLog = Join-Path $LogDir "bridge.err.log"
$RestartDelaySeconds = 5

Set-Location $ProjectRoot

try {
  while ($true) {
    $startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $OutLog -Value "[$startedAt] starting bridge node"

    & $Node20 --import ./scripts/register-node-proxy.mjs ./server.js 1>> $OutLog 2>> $ErrLog
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 1 }

    $stoppedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($exitCode -eq 0) {
      Add-Content -LiteralPath $OutLog -Value "[$stoppedAt] bridge node exited cleanly; supervisor stopping"
      exit 0
    }

    Add-Content -LiteralPath $ErrLog -Value "[$stoppedAt] bridge node exited with code $exitCode; restarting in $RestartDelaySeconds seconds"
    Start-Sleep -Seconds $RestartDelaySeconds
  }
} catch {
  $failedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -LiteralPath $ErrLog -Value "[$failedAt] supervisor failed: $($_.Exception.Message)"
  Add-Content -LiteralPath $ErrLog -Value ($_.ScriptStackTrace | Out-String)
  exit 1
}
