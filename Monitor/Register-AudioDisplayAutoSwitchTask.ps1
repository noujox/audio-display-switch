param(
    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcherScript = Join-Path $scriptRoot "AudioDisplayAutoSwitch.ps1"

if (-not (Test-Path -LiteralPath $watcherScript)) {
    throw "Watcher script not found: $watcherScript"
}

$taskName = "AudioDisplayAutoSwitch"
$actionArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherScript`""

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

$registeredVia = ""

try {
    $principal = New-ScheduledTaskPrincipal -UserId "$env:UserDomain\$env:UserName" -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Auto switch monitor profile from default audio output" `
        -Force `
        -ErrorAction Stop | Out-Null

    $registeredVia = "Task Scheduler"
}
catch {
    $startupDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    $startupCmdPath = Join-Path $startupDir "AudioDisplayAutoSwitch.cmd"
    $startupCmd = @"
@echo off
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$watcherScript"
"@
    $startupCmd = $startupCmd + "`r`n"
    Set-Content -LiteralPath $startupCmdPath -Value $startupCmd -Encoding ASCII
    $registeredVia = "Startup folder"
    Write-Warning "Could not register scheduled task. Fallback created: $startupCmdPath"
}

if ($RunNow) {
    if ($registeredVia -eq "Task Scheduler") {
        Start-ScheduledTask -TaskName $taskName
    }
    else {
        Start-Process -FilePath "powershell.exe" -ArgumentList $actionArgs -WindowStyle Hidden
    }
}

Write-Host "Auto-start registered via: $registeredVia"
