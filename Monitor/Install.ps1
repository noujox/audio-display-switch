Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
    [switch]$SkipShortcut
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$switchButtonRoot = Join-Path (Split-Path -Parent $scriptRoot) "SwitchButton"

. (Join-Path $scriptRoot "AudioEndpointTools.ps1")

$configPath = Join-Path $scriptRoot "config.json"
$profilesDir = Join-Path $scriptRoot "profiles"
$logsDir = Join-Path $scriptRoot "logs"
$pcProfilePath = Join-Path $profilesDir "pc.xml"
$tvProfilePath = Join-Path $profilesDir "tv.xml"
$logPath = Join-Path $logsDir "switch.log"

if (-not (Test-Path -LiteralPath $profilesDir)) {
    New-Item -ItemType Directory -Path $profilesDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$defaultMonitorSwitcher = "C:\Tools\MonitorSwitcher\app\MonitorSwitcher.exe"
if (Test-Path -LiteralPath $configPath) {
    try {
        $existing = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace([string]$existing.monitorSwitcherExe)) {
            $defaultMonitorSwitcher = [string]$existing.monitorSwitcherExe
        }
    }
    catch {
    }
}

$monitorSwitcherExe = Read-Host "Ruta de MonitorSwitcher.exe (Enter para '$defaultMonitorSwitcher')"
if ([string]::IsNullOrWhiteSpace($monitorSwitcherExe)) {
    $monitorSwitcherExe = $defaultMonitorSwitcher
}

if (-not (Test-Path -LiteralPath $monitorSwitcherExe)) {
    throw "MonitorSwitcher executable not found: $monitorSwitcherExe"
}

function Save-Profile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    & $monitorSwitcherExe "-save:$Path"
}

function Test-ProfileForClone {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath
    )

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        return $false
    }

    $xml = [xml](Get-Content -LiteralPath $ProfilePath -Raw)
    $paths = @($xml.displaySettings.pathInfoArray.DisplayConfigPathInfo)
    if ($paths.Count -eq 0) {
        return $false
    }

    $dups = @($paths |
        Group-Object { [string]$_.sourceInfo.id } |
        Where-Object { $_.Count -gt 1 })

    return ($dups.Count -gt 0)
}

function Select-Endpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Question,
        [string]$RecommendedPattern = ""
    )

    $all = @(Get-RenderAudioEndpoints)
    if ($all.Count -eq 0) {
        throw "No audio render endpoints were detected"
    }

    $candidates = @($all | Where-Object { $_.State -in @("ACTIVE", "UNPLUGGED") })
    if ($candidates.Count -eq 0) {
        $candidates = $all
    }

    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $mark = if ($candidates[$i].IsDefault) { "(default)" } else { "" }
        Write-Host ("[{0}] [{1}] {2}  {3}" -f $i, $candidates[$i].State, $candidates[$i].Name, $mark)
    }

    $defaultIndex = 0
    if (-not [string]::IsNullOrWhiteSpace($RecommendedPattern)) {
        $match = $candidates | Where-Object { $_.Name -match $RecommendedPattern } | Select-Object -First 1
        if ($null -ne $match) {
            $defaultIndex = [array]::IndexOf($candidates, $match)
        }
    }

    if ($defaultIndex -lt 0) {
        $defaultIndex = 0
    }

    $choice = Read-Host "$Question (Enter=$defaultIndex)"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = "$defaultIndex"
    }

    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index)) {
        throw "Invalid selection: $choice"
    }

    if ($index -lt 0 -or $index -ge $candidates.Count) {
        throw "Selection out of range: $index"
    }

    return $candidates[$index]
}

Write-Host "[1/6] Configure PC mode and press Enter to capture profile"
Write-Host "Expected: your normal PC layout (for example 1+2, TV off)"
[void](Read-Host)
Save-Profile -Path $pcProfilePath
if (Test-ProfileForClone -ProfilePath $pcProfilePath) {
    Write-Warning "PC profile appears to include clone paths. Continue only if that is intentional."
}

if ($null -eq (Get-DefaultRenderAudioEndpoint)) {
    throw "Could not detect current default audio endpoint for PC mode"
}

Write-Host "[2/6] Select TV/HDMI audio output"
$tvEndpoint = Select-Endpoint -Question "TV endpoint number" -RecommendedPattern "TV|HDMI"

Write-Host "[3/6] Select PC audio output"
$pcSelected = Select-Endpoint -Question "PC endpoint number" -RecommendedPattern "7\.1\s*Surround|Surround|Headphones|Altavoces"

Write-Host "[4/6] Configure TV mode and press Enter to capture profile"
Write-Host "Expected: TV layout enabled (for example 1+3)"
[void](Read-Host)
Save-Profile -Path $tvProfilePath
if (Test-ProfileForClone -ProfilePath $tvProfilePath) {
    Write-Warning "TV profile appears to include clone paths. Continue only if that is intentional."
}

$config = [ordered]@{
    monitorSwitcherExe = $monitorSwitcherExe
    profiles = [ordered]@{
        pc = $pcProfilePath
        tv = $tvProfilePath
    }
    audio = [ordered]@{
        tvEndpointId = [string]$tvEndpoint.Id
        pcEndpointId = [string]$pcSelected.Id
        pollMs = 1500
        debounceCount = 2
        cooldownSeconds = 4
    }
    behavior = [ordered]@{
        enforceStateOnStart = $true
    }
    logging = [ordered]@{
        path = $logPath
        maxSizeMb = 5
    }
}

$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
Write-Host "[5/6] Config saved: $configPath"

& (Join-Path $scriptRoot "Register-AudioDisplayAutoSwitchTask.ps1") -RunNow
Write-Host "[6/6] Monitor auto-start configured"

if (-not $SkipShortcut) {
    $shortcutScript = Join-Path $switchButtonRoot "Create-TaskbarToggleShortcut.ps1"
    if (Test-Path -LiteralPath $shortcutScript) {
        & $shortcutScript
    }
}

Write-Host "Done."
