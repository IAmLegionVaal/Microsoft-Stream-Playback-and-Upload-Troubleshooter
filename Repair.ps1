#requires -Version 5.1
<# Created by Dewald Pretorius. #>
[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Diagnose','ResetClientCache','StartAudioService','FlushDns')][string]$Action='Diagnose',[string]$OutputPath=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Microsoft_Stream_Repair'))
$ErrorActionPreference='Stop';$cachePaths=@("$env:APPDATA\Microsoft\Teams\Cache","$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache")
New-Item -ItemType Directory -Path $OutputPath -Force|Out-Null;$stamp=Get-Date -Format yyyyMMdd_HHmmss;$log=Join-Path $OutputPath "Repair_$stamp.log";function Log($m){$l='{0:u} {1}'-f(Get-Date),$m;Write-Host $l;Add-Content $log $l}
[ordered]@{Action=$Action;Processes=@(Get-Process msedge,'ms-teams' -ErrorAction SilentlyContinue|Select-Object Name,Id);AudioService=(Get-Service Audiosrv -ErrorAction SilentlyContinue|Select-Object Name,Status,StartType);Stream443=(Test-NetConnection 'stream.office.com' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue);Caches=@($cachePaths|ForEach-Object{[pscustomobject]@{Path=$_;Exists=Test-Path $_}})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutputPath "PreRepair_$stamp.json")
if($Action -eq 'Diagnose'){Log '[COMPLETE] Snapshot saved.';exit 0}
try{if($Action -eq 'ResetClientCache' -and $PSCmdlet.ShouldProcess('Teams and Edge caches','Back up and reset')){if(Get-Process msedge,'ms-teams' -ErrorAction SilentlyContinue){throw 'Close Edge and Teams before resetting caches.'};foreach($path in $cachePaths){if(Test-Path $path){$backup="$path.backup-$stamp";Move-Item $path $backup -Force;New-Item -ItemType Directory $path -Force|Out-Null;Log "[BACKUP] $backup"}}}
elseif($Action -eq 'StartAudioService' -and $PSCmdlet.ShouldProcess('Windows Audio','Start if stopped')){$svc=Get-Service Audiosrv;if($svc.Status -eq 'Stopped'){Start-Service Audiosrv}}
elseif($Action -eq 'FlushDns' -and $PSCmdlet.ShouldProcess('Windows DNS client cache','Clear')){Clear-DnsClientCache}}catch{Log "[FAILED] $($_.Exception.Message)";exit 5};Log '[COMPLETE] Repair completed.';exit 0
