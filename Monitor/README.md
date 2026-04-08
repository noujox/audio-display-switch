# Monitor

Automatic display mode switcher driven by default audio output.

## First install

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Install.ps1"
```

What it does:
- captures your `pc.xml` and `tv.xml` display profiles
- asks you to select TV and PC audio endpoints
- writes `config.json`
- enables auto-start
- optionally creates taskbar toggle shortcut

## Reconfigure

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Reconfigure.ps1"
```

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Uninstall.ps1"
```

To also remove config/profiles/logs:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Uninstall.ps1" -RemoveData
```
