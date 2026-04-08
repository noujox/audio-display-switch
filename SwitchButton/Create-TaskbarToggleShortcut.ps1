Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toggleScript = Join-Path $scriptRoot "Toggle-AudioOutput.ps1"
$configPath = Join-Path $scriptRoot "config.json"
$audioToolsPath = Join-Path $scriptRoot "AudioEndpointTools.ps1"

if (-not (Test-Path -LiteralPath $toggleScript)) {
    throw "Toggle script not found: $toggleScript"
}

if (-not (Test-Path -LiteralPath $audioToolsPath)) {
    throw "Audio tools not found: $audioToolsPath"
}

. $audioToolsPath

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Config file not found: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$profilesDir = Join-Path $scriptRoot "profiles"
$logsDir = Join-Path $scriptRoot "logs"
if (-not (Test-Path -LiteralPath $profilesDir)) {
    New-Item -ItemType Directory -Path $profilesDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

function Select-Endpoint {
    param(
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

function Ensure-Configuration {
    $defaultMonitorSwitcher = if (-not [string]::IsNullOrWhiteSpace([string]$config.monitorSwitcherExe)) {
        [string]$config.monitorSwitcherExe
    }
    else {
        "C:\Tools\MonitorSwitcher\app\MonitorSwitcher.exe"
    }

    $monitorSwitcherExe = Read-Host "Ruta de MonitorSwitcher.exe (Enter para '$defaultMonitorSwitcher')"
    if ([string]::IsNullOrWhiteSpace($monitorSwitcherExe)) {
        $monitorSwitcherExe = $defaultMonitorSwitcher
    }
    if (-not (Test-Path -LiteralPath $monitorSwitcherExe)) {
        throw "MonitorSwitcher executable not found: $monitorSwitcherExe"
    }

    $pcProfilePath = Join-Path $profilesDir "pc.xml"
    $tvProfilePath = Join-Path $profilesDir "tv.xml"

    Write-Host "[1/4] Pon modo PC y presiona Enter para guardar perfil PC"
    [void](Read-Host)
    & $monitorSwitcherExe "-save:$pcProfilePath"

    Write-Host "[2/4] Pon modo TV y presiona Enter para guardar perfil TV"
    [void](Read-Host)
    & $monitorSwitcherExe "-save:$tvProfilePath"

    Write-Host "[3/4] Selecciona endpoint de audio TV"
    $tvEndpoint = Select-Endpoint -Question "TV endpoint" -RecommendedPattern "TV|HDMI"

    Write-Host "[4/4] Selecciona endpoint de audio PC"
    $pcEndpoint = Select-Endpoint -Question "PC endpoint" -RecommendedPattern "7\.1\s*Surround|Surround|Headphones|Altavoces"

    $config.monitorSwitcherExe = $monitorSwitcherExe
    $config.profiles.pc = $pcProfilePath
    $config.profiles.tv = $tvProfilePath
    $config.audio.tvEndpointId = [string]$tvEndpoint.Id
    $config.audio.pcEndpointId = [string]$pcEndpoint.Id
    $config.logging.path = Join-Path $logsDir "switch.log"

    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
    Write-Host "Configuracion guardada: $configPath"
}

Ensure-Configuration

$powershellExe = Join-Path $PSHOME "powershell.exe"
if (-not (Test-Path -LiteralPath $powershellExe)) {
    $powershellExe = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
}

$desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
$shortcutPath = Join-Path $desktopPath "Cambiar TV-7.1.lnk"
$startMenuPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)) "Cambiar TV-7.1.lnk"

$shell = New-Object -ComObject WScript.Shell

foreach ($path in @($shortcutPath, $startMenuPath)) {
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $powershellExe
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$toggleScript`""
    $shortcut.WorkingDirectory = $scriptRoot
    $shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,108"
    $shortcut.Description = "Alterna modo TV/PC (pantalla + audio)"
    $shortcut.Save()
}

Write-Host "Shortcut creado: $shortcutPath"
Write-Host "Shortcut Start Menu: $startMenuPath"
Write-Host "Para anclar: abre Inicio, busca 'Cambiar TV-7.1', click derecho -> Anclar a la barra de tareas"
