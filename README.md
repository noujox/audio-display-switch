# Audio Display AutoSwitch

Proyecto simple para alternar entre modo **PC** y modo **TV** en Windows, sincronizando pantallas y audio.

Esta carpeta contiene **2 funciones separadas** que pueden usarse juntas o por separado:

- `Monitor/`: monitor automatico (daemon) que reacciona al audio por defecto.
- `SwitchButton/`: boton manual para alternar modo TV/PC con un click.

## Requisitos

- Windows 10/11
- PowerShell
- [MonitorSwitcher](https://sourceforge.net/projects/monitorswitcher/) (portable)

Ruta esperada por defecto:

`C:\Tools\MonitorSwitcher\app\MonitorSwitcher.exe`

Puedes cambiarla durante los setups.

## 1) Monitor (automatico)

Detecta continuamente la salida de audio por defecto y cambia perfiles de pantalla:

- audio TV -> perfil TV
- audio no TV -> perfil PC
- audio no TV -> otro no TV -> no cambia pantallas

### Setup

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Install.ps1"
```

El instalador:

- captura `pc.xml` y `tv.xml`
- pide endpoint de audio TV y endpoint de audio PC
- guarda `Monitor\config.json`
- registra autoarranque al iniciar sesion

### Reconfigurar

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Reconfigure.ps1"
```

### Desinstalar

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Uninstall.ps1"
```

## 2) SwitchButton (manual)

Boton para barra de tareas que alterna modo completo:

- PC -> TV: aplica perfil TV y luego audio TV
- TV -> PC: aplica perfil PC y luego audio PC

Importante: este modulo es **standalone**. No depende de `Monitor/`.

### Setup + shortcut

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\SwitchButton\Create-TaskbarToggleShortcut.ps1"
```

Ese script tambien configura perfiles/endpoints y crea el acceso directo `Cambiar TV-7.1`.

Luego:

1. Abrir Inicio
2. Buscar `Cambiar TV-7.1`
3. Click derecho -> **Anclar a la barra de tareas**

## Estructura

```text
AudioDisplayAutoSwitch/
  Monitor/
    Install.ps1
    AudioDisplayAutoSwitch.ps1
    AudioEndpointTools.ps1
    Register-AudioDisplayAutoSwitchTask.ps1
    Reconfigure.ps1
    Uninstall.ps1
    config.json
    logs/
    profiles/

  SwitchButton/
    Create-TaskbarToggleShortcut.ps1
    Toggle-AudioOutput.ps1
    AudioEndpointTools.ps1
    config.json
    logs/
    profiles/
```

## Nota

Los `config.json` y perfiles (`pc.xml`, `tv.xml`) son especificos de cada equipo.  
Si cambias monitor/TV/puerto HDMI, vuelve a correr el setup del modulo que uses.

## License

MIT - see `LICENSE`.
