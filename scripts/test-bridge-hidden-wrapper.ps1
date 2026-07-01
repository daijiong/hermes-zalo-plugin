$ErrorActionPreference = "Stop"

$ScriptPath = Join-Path $PSScriptRoot "run-bridge-hidden.ps1"
$Source = Get-Content -LiteralPath $ScriptPath -Raw

if ($Source -notmatch 'while\s*\(\s*\$true\s*\)') {
  throw "run-bridge-hidden.ps1 must supervise node in a loop"
}

if ($Source -notmatch "bridge node exited") {
  throw "run-bridge-hidden.ps1 must log node exit before retrying"
}

if ($Source -notmatch 'if\s*\(\s*\$exitCode\s*-eq\s*0\s*\)') {
  throw "run-bridge-hidden.ps1 must stop on clean node exit"
}

if ($Source -notmatch 'try\s*\{') {
  throw "run-bridge-hidden.ps1 must wrap the supervisor in try/catch"
}

if ($Source -notmatch 'catch\s*\{') {
  throw "run-bridge-hidden.ps1 must catch script-level failures"
}

if ($Source -notmatch 'supervisor failed') {
  throw "run-bridge-hidden.ps1 must log script-level failures"
}

"Bridge hidden wrapper checks OK"
