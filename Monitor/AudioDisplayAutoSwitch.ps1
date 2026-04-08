Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "AudioEndpointTools.ps1")

$configPath = Join-Path $scriptRoot "config.json"

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing config file: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$monitorSwitcherExe = [string]$config.monitorSwitcherExe
$pcProfilePath = [string]$config.profiles.pc
$tvProfilePath = [string]$config.profiles.tv
$tvEndpointId = [string]$config.audio.tvEndpointId
$pollMs = [int]$config.audio.pollMs
$debounceCount = [int]$config.audio.debounceCount
$cooldownSeconds = [int]$config.audio.cooldownSeconds
$enforceStateOnStart = [bool]$config.behavior.enforceStateOnStart
$logPath = [string]$config.logging.path
$maxLogSizeMb = [int]$config.logging.maxSizeMb

if ([string]::IsNullOrWhiteSpace($monitorSwitcherExe) -or -not (Test-Path -LiteralPath $monitorSwitcherExe)) {
    throw "MonitorSwitcher executable not found: $monitorSwitcherExe"
}

if (-not (Test-Path -LiteralPath $pcProfilePath)) {
    throw "PC profile missing: $pcProfilePath"
}

if ([string]::IsNullOrWhiteSpace($tvEndpointId)) {
    throw "audio.tvEndpointId is empty in config.json"
}

$logDir = Split-Path -Parent $logPath
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Rotate-LogIfNeeded {
    param(
        [string]$Path,
        [int]$MaxSizeMb
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $maxBytes = $MaxSizeMb * 1MB
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt $maxBytes) {
        return
    }

    $archive = "$Path.old"
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }

    Move-Item -LiteralPath $Path -Destination $archive -Force
}

function Write-Log {
    param(
        [string]$Message
    )

    Rotate-LogIfNeeded -Path $logPath -MaxSizeMb $maxLogSizeMb
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $logPath -Value "$timestamp  $Message"
}

function Get-ModeFromEndpointId {
    param(
        [string]$EndpointId
    )

    if ([string]::Equals($EndpointId, $tvEndpointId, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "tv"
    }

    return "pc"
}

function Invoke-MonitorProfile {
    param(
        [ValidateSet("pc", "tv")]
        [string]$Mode
    )

    $profilePath = if ($Mode -eq "tv") { $tvProfilePath } else { $pcProfilePath }

    if (-not (Test-Path -LiteralPath $profilePath)) {
        Write-Log "Profile missing for mode '$Mode': $profilePath"
        return $false
    }

    $args = "-load:$profilePath"
    $process = Start-Process -FilePath $monitorSwitcherExe -ArgumentList $args -PassThru -Wait -WindowStyle Hidden

    if ($process.ExitCode -ne 0) {
        Write-Log "MonitorSwitcher exited with code $($process.ExitCode) for mode '$Mode'"
        return $false
    }

    Write-Log "Applied display mode '$Mode'"
    return $true
}

Write-Log "Watcher started. Poll=${pollMs}ms Debounce=${debounceCount} Cooldown=${cooldownSeconds}s"

if (-not (Test-Path -LiteralPath $tvProfilePath)) {
    Write-Log "TV profile does not exist yet: $tvProfilePath"
}

$candidateEndpointId = $null
$candidateCount = 0
$stableEndpointId = $null
$stableEndpointName = $null
$lastApplyTime = [datetime]::MinValue

while ($true) {
    try {
        $defaultEndpoint = Get-DefaultRenderAudioEndpoint

        if ($null -eq $defaultEndpoint -or [string]::IsNullOrWhiteSpace($defaultEndpoint.Id)) {
            Write-Log "No default render endpoint detected"
            Start-Sleep -Milliseconds $pollMs
            continue
        }

        $currentEndpointId = [string]$defaultEndpoint.Id

        if ($candidateEndpointId -ne $currentEndpointId) {
            $candidateEndpointId = $currentEndpointId
            $candidateCount = 1
        }
        else {
            $candidateCount++
        }

        if ($candidateCount -lt $debounceCount) {
            Start-Sleep -Milliseconds $pollMs
            continue
        }

        if ($stableEndpointId -eq $candidateEndpointId) {
            Start-Sleep -Milliseconds $pollMs
            continue
        }

        $oldEndpointId = $stableEndpointId
        $newEndpointId = $candidateEndpointId

        $oldMode = if ($null -eq $oldEndpointId) { "unknown" } else { Get-ModeFromEndpointId -EndpointId $oldEndpointId }
        $newMode = Get-ModeFromEndpointId -EndpointId $newEndpointId

        $oldName = if ($null -eq $stableEndpointId) { "<none>" } else { [string]$stableEndpointName }
        $newName = [string]$defaultEndpoint.Name

        Write-Log "Audio stable change: '$oldMode' -> '$newMode' | '$oldName' -> '$newName'"

        $stableEndpointId = $newEndpointId
        $stableEndpointName = $newName

        $shouldApply = $false
        if ($oldMode -eq "unknown") {
            $shouldApply = $enforceStateOnStart
        }
        elseif ($oldMode -eq "pc" -and $newMode -eq "tv") {
            $shouldApply = $true
        }
        elseif ($oldMode -eq "tv" -and $newMode -eq "pc") {
            $shouldApply = $true
        }

        if (-not $shouldApply) {
            Write-Log "No display action required"
            Start-Sleep -Milliseconds $pollMs
            continue
        }

        $elapsedSeconds = ([datetime]::UtcNow - $lastApplyTime).TotalSeconds
        if ($elapsedSeconds -lt $cooldownSeconds) {
            $remainingMs = [math]::Ceiling(($cooldownSeconds - $elapsedSeconds) * 1000)
            if ($remainingMs -gt 0) {
                Start-Sleep -Milliseconds $remainingMs
            }
        }

        if (Invoke-MonitorProfile -Mode $newMode) {
            $lastApplyTime = [datetime]::UtcNow
        }
    }
    catch {
        Write-Log "Error: $($_.Exception.Message)"
    }

    Start-Sleep -Milliseconds $pollMs
}
