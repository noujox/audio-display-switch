param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$audioToolsPath = Join-Path $scriptRoot "AudioEndpointTools.ps1"
if (-not (Test-Path -LiteralPath $audioToolsPath)) {
    throw "Audio tools not found: $audioToolsPath"
}

. $audioToolsPath

$configPath = Join-Path $scriptRoot "config.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Config file not found: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$monitorSwitcherExe = [string]$config.monitorSwitcherExe
$pcProfilePath = [string]$config.profiles.pc
$tvProfilePath = [string]$config.profiles.tv
$tvId = [string]$config.audio.tvEndpointId
$pcId = [string]$config.audio.pcEndpointId
$logPath = [string]$config.logging.path

if ([string]::IsNullOrWhiteSpace($tvId)) {
    throw "audio.tvEndpointId is empty in config.json"
}

if ([string]::IsNullOrWhiteSpace($pcId)) {
    throw "audio.pcEndpointId is empty in config.json"
}

if ([string]::IsNullOrWhiteSpace($monitorSwitcherExe) -or -not (Test-Path -LiteralPath $monitorSwitcherExe)) {
    throw "MonitorSwitcher executable not found: $monitorSwitcherExe"
}

if (-not (Test-Path -LiteralPath $pcProfilePath)) {
    throw "PC profile not found: $pcProfilePath"
}

if (-not (Test-Path -LiteralPath $tvProfilePath)) {
    throw "TV profile not found: $tvProfilePath"
}

function Write-Log {
    param(
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return
    }

    $logDir = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $logPath -Value "$timestamp  Toggle: $Message"
}

function Resolve-Endpoint {
    param(
        [string]$PreferredId,
        [string]$FallbackNamePattern
    )

    $endpoints = @(Get-RenderAudioEndpoints)
    $exact = $endpoints | Where-Object { [string]::Equals($_.Id, $PreferredId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($null -ne $exact) {
        return $exact
    }

    $fallback = $endpoints |
        Where-Object { $_.Name -match $FallbackNamePattern -and $_.State -in @("ACTIVE", "UNPLUGGED", "NOTPRESENT") } |
        Select-Object -First 1

    return $fallback
}

function Invoke-Profile {
    param(
        [ValidateSet("PC", "TV")]
        [string]$Mode
    )

    $profilePath = if ($Mode -eq "TV") { $tvProfilePath } else { $pcProfilePath }
    $args = "-load:$profilePath"

    $process = Start-Process -FilePath $monitorSwitcherExe -ArgumentList $args -PassThru -Wait -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "MonitorSwitcher exit code $($process.ExitCode) while applying $Mode"
    }
}

function Wait-EndpointCandidate {
    param(
        [string]$PreferredId,
        [string]$FallbackNamePattern,
        [int]$TimeoutSeconds = 8
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $endpoints = @(Get-RenderAudioEndpoints)

        $byId = $endpoints | Where-Object { [string]::Equals($_.Id, $PreferredId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if ($null -ne $byId -and $byId.State -in @("ACTIVE", "UNPLUGGED")) {
            return $byId
        }

        $fallback = $endpoints |
            Where-Object { $_.Name -match $FallbackNamePattern -and $_.State -in @("ACTIVE", "UNPLUGGED") } |
            Select-Object -First 1
        if ($null -ne $fallback) {
            return $fallback
        }

        if ($null -ne $byId) {
            return $byId
        }

        Start-Sleep -Milliseconds 500
    }
    while ((Get-Date) -lt $deadline)

    return (Resolve-Endpoint -PreferredId $PreferredId -FallbackNamePattern $FallbackNamePattern)
}

$mutex = New-Object System.Threading.Mutex($false, "Local\AudioDisplayAutoSwitch.Toggle")
$hasLock = $mutex.WaitOne(0)
if (-not $hasLock) {
    Write-Log "Skipped. Toggle already running"
    return
}

try {
    try {
        $current = Get-DefaultRenderAudioEndpoint
        if ($null -eq $current) {
            throw "No default render endpoint found"
        }

        $goToPc = [string]::Equals([string]$current.Id, $tvId, [System.StringComparison]::OrdinalIgnoreCase)

        if ($goToPc) {
            $mode = "PC"
            $endpoint = Resolve-Endpoint -PreferredId $pcId -FallbackNamePattern "7\.1\s*Surround|Surround"
        }
        else {
            $mode = "TV"
            $endpoint = Resolve-Endpoint -PreferredId $tvId -FallbackNamePattern "SONY\s*TV|\bTV\b|HDMI"
        }

        if ($DryRun) {
            $targetName = if ($null -eq $endpoint) { "<unresolved>" } else { [string]$endpoint.Name }
            Write-Host "DryRun: mode=$mode | '$($current.Name)' -> '$targetName'"
            Write-Log "DryRun mode=$mode | '$($current.Name)' -> '$targetName'"
            return
        }

        if ($mode -eq "TV") {
            Invoke-Profile -Mode "TV"
            Write-Log "Applied TV profile"

            $endpoint = Wait-EndpointCandidate -PreferredId $tvId -FallbackNamePattern "SONY\s*TV|\bTV\b|HDMI" -TimeoutSeconds 8
            if ($null -eq $endpoint) {
                throw "Could not resolve TV audio endpoint after enabling TV profile"
            }

            Set-DefaultRenderAudioEndpoint -EndpointId ([string]$endpoint.Id)
            Write-Log "TV mode complete | '$($current.Name)' -> '$($endpoint.Name)'"
        }
        else {
            Invoke-Profile -Mode "PC"
            Write-Log "Applied PC profile"

            if ($null -eq $endpoint) {
                $endpoint = Resolve-Endpoint -PreferredId $pcId -FallbackNamePattern "7\.1\s*Surround|Surround"
            }

            if ($null -eq $endpoint) {
                throw "Could not resolve PC audio endpoint"
            }

            Set-DefaultRenderAudioEndpoint -EndpointId ([string]$endpoint.Id)
            Write-Log "PC mode complete | '$($current.Name)' -> '$($endpoint.Name)'"
        }
    }
    catch {
        Write-Log "Error: $($_.Exception.Message)"
        throw
    }
}
finally {
    if ($hasLock) {
        $mutex.ReleaseMutex() | Out-Null
    }
    $mutex.Dispose()
}
