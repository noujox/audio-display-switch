Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
    [switch]$RemoveData
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

$taskName = "AudioDisplayAutoSwitch"
$startupCmd = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)) "AudioDisplayAutoSwitch.cmd"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)) "Cambiar TV-7.1.lnk"
$startMenuShortcut = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)) "Cambiar TV-7.1.lnk"

try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    Write-Host "Removed scheduled task: $taskName"
}
catch {
    Write-Host "Scheduled task not removed (not present or no permission)."
}

if (Test-Path -LiteralPath $startupCmd) {
    Remove-Item -LiteralPath $startupCmd -Force
    Write-Host "Removed startup fallback: $startupCmd"
}

foreach ($path in @($desktopShortcut, $startMenuShortcut)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        Write-Host "Removed shortcut: $path"
    }
}

if ($RemoveData) {
    $logsDir = Join-Path $scriptRoot "logs"
    $profilesDir = Join-Path $scriptRoot "profiles"
    $configPath = Join-Path $scriptRoot "config.json"

    if (Test-Path -LiteralPath $logsDir) {
        Remove-Item -LiteralPath $logsDir -Recurse -Force
        Write-Host "Removed logs: $logsDir"
    }

    if (Test-Path -LiteralPath $profilesDir) {
        Remove-Item -LiteralPath $profilesDir -Recurse -Force
        Write-Host "Removed profiles: $profilesDir"
    }

    if (Test-Path -LiteralPath $configPath) {
        Remove-Item -LiteralPath $configPath -Force
        Write-Host "Removed config: $configPath"
    }
}

Write-Host "Uninstall complete."
