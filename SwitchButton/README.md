# SwitchButton

Manual toggle button for TV/PC mode.

This project is standalone and does not require the `Monitor` folder.

- from PC mode: applies TV display profile, then sets TV audio
- from TV mode: applies PC display profile, then sets PC audio

## Create shortcut for taskbar

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\SwitchButton\Create-TaskbarToggleShortcut.ps1"
```

The shortcut creator also runs interactive configuration:
- asks MonitorSwitcher path
- captures PC/TV display profiles
- asks TV/PC audio endpoints
- writes `SwitchButton\config.json`

Then in Start menu search for `Cambiar TV-7.1` and pin it to taskbar.
