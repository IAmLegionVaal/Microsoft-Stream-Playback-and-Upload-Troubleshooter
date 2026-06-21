# Microsoft Stream Playback and Upload Troubleshooter

Created by **Dewald Pretorius**.

The repository includes the original diagnostics and a guarded `Repair.ps1` helper.

Supported actions:

- `Diagnose`
- `ResetClientCache`
- `StartAudioService`
- `FlushDns`

```powershell
.\Repair.ps1 -Action Diagnose
.\Repair.ps1 -Action ResetClientCache -WhatIf
.\Repair.ps1 -Action ResetClientCache -Confirm
```

Close Edge and Teams before cache repair. Existing cache data is preserved as timestamped backups. Source-reviewed for PowerShell 5.1; not runtime-tested against every Stream configuration.
