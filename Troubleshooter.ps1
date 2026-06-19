#requires -Version 5.1
<# Created by Dewald Pretorius #>
param([string]$OutputPath)
if(-not $OutputPath){$OutputPath="$([Environment]::GetFolderPath('Desktop'))\Stream_Reports"};New-Item $OutputPath -ItemType Directory -Force|Out-Null
$targets='stream.office.com','stream.microsoft.com','login.microsoftonline.com','graph.microsoft.com';$net=foreach($t in $targets){[pscustomobject]@{Target=$t;DNS=[bool](Resolve-DnsName $t -ErrorAction SilentlyContinue);HTTPS443=(Test-NetConnection $t -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)}}
@('MICROSOFT STREAM PLAYBACK AND UPLOAD TROUBLESHOOTER','Created by Dewald Pretorius',"Generated: $(Get-Date)",($net|Format-Table -AutoSize|Out-String -Width 220),'Guidance: verify permissions, source file format, upload size, browser media support, network stability, transcript processing, storage location, and service health.')|Set-Content (Join-Path $OutputPath 'Report.txt') -Encoding UTF8