# Audio Display AutoSwitch

Audio Display AutoSwitch is a small Windows project for people who switch often between a desk monitor setup and a TV setup.

The idea is simple: changing displays and audio every time can be annoying. This project removes most of that manual work.

## Why this exists

Many gaming and media setups use two common modes:

- **PC mode**: desk monitors + headphones/speakers
- **TV mode**: HDMI TV + TV audio

Windows can handle both, but switching back and forth repeatedly usually means several clicks in different menus. This repo was built to make that transition quick and reliable.

## Two separate tools

This repository contains two independent modules. You can use either one, or both.

### `Monitor/` (automatic)

Runs in the background and watches your default audio output.

- If audio switches to TV, it loads the TV display profile.
- If audio switches away from TV, it loads the PC display profile.
- If audio changes between two non-TV devices, it does nothing.

Setup:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Install.ps1"
```

This setup captures display profiles, asks for TV/PC audio endpoints, writes config, and enables auto-start.

Useful commands:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Reconfigure.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\Monitor\Uninstall.ps1"
```

### `SwitchButton/` (manual)

Creates a one-click toggle button for taskbar use.

- PC -> TV: apply TV display profile, then set TV audio
- TV -> PC: apply PC display profile, then set PC audio

This module is standalone and does not require `Monitor/`.

Setup + shortcut creation:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Tools\AudioDisplayAutoSwitch\SwitchButton\Create-TaskbarToggleShortcut.ps1"
```

Then pin it from Start:

1. Search `Cambiar TV-7.1`
2. Right click
3. Select **Pin to taskbar**

## Requirements

- Windows 10/11
- PowerShell
- [MonitorSwitcher](https://sourceforge.net/projects/monitorswitcher/)

Default path used in scripts:

`C:\Tools\MonitorSwitcher\app\MonitorSwitcher.exe`

You can choose a different path during setup.

## Notes

- `config.json` and display profiles are machine-specific.
- If you change monitors, cables, GPU outputs, or audio devices, run setup again.

## License

MPL-2.0. See `LICENSE`.
