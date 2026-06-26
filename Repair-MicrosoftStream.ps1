#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$ClearBrowserMediaCache,
    [switch]$ResetNetwork,
    [switch]$RepairWebView2,
    [switch]$RestartAudioVideoServices,
    [switch]$Force,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = "$env:USERPROFILE\Desktop\StreamRepair"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$warnings = [System.Collections.Generic.List[string]]::new()
$logPath = $null

function Write-RepairLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN')][string]$Level = 'INFO'
    )

    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    Write-Host $entry
    if ($logPath) {
        Add-Content -LiteralPath $logPath -Value $entry -Encoding UTF8
    }
}

function Add-RepairWarning {
    param([Parameter(Mandatory)][string]$Message)

    $warnings.Add($Message)
    Write-RepairLog -Level WARN -Message $Message
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-WebView2Setup {
    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique) {
        $applicationPath = Join-Path $root 'Microsoft\EdgeWebView\Application'
        if (-not (Test-Path -LiteralPath $applicationPath)) {
            continue
        }

        $setup = Get-ChildItem -LiteralPath $applicationPath -Filter 'setup.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match '[\\/]Installer$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($setup) {
            return $setup.FullName
        }
    }

    return $null
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int[]]$SuccessExitCodes = @(0)
    )

    $outputFile = Join-Path $OutputPath (($Name -replace '[^A-Za-z0-9-]', '_') + '.txt')
    & $FilePath @ArgumentList 2>&1 | Tee-Object -FilePath $outputFile
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $SuccessExitCodes) {
        throw "$Name exited with code $exitCode. Review '$outputFile'."
    }
}

try {
    if ($env:OS -ne 'Windows_NT') {
        throw 'This repair requires Windows.'
    }

    if (-not ($ClearBrowserMediaCache -or $ResetNetwork -or $RepairWebView2 -or $RestartAudioVideoServices)) {
        throw 'Choose at least one repair action.'
    }

    $requiresAdmin = $ResetNetwork -or $RepairWebView2 -or $RestartAudioVideoServices
    if ($requiresAdmin -and -not (Test-IsAdministrator)) {
        throw 'Run PowerShell as Administrator for network, WebView2, or service repair actions.'
    }

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $logPath = Join-Path $OutputPath ('repair-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))

    if ($ClearBrowserMediaCache) {
        $browserProcesses = @(Get-Process -Name 'msedge', 'chrome' -ErrorAction SilentlyContinue)
        if ($browserProcesses.Count -gt 0 -and -not $Force) {
            throw 'Close Microsoft Edge and Google Chrome or use -Force before clearing media caches.'
        }

        if ($browserProcesses.Count -gt 0 -and $Force -and
            $PSCmdlet.ShouldProcess('Browser processes', 'Stop before clearing media cache')) {
            $browserProcesses | Stop-Process -Force -ErrorAction Stop
            Write-RepairLog 'Stopped browser processes.'
        }

        foreach ($cachePath in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Media Cache'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Media Cache')
        )) {
            if (-not (Test-Path -LiteralPath $cachePath)) {
                Add-RepairWarning "Media cache path was not found: $cachePath"
                continue
            }

            if ($PSCmdlet.ShouldProcess($cachePath, 'Clear browser media cache contents')) {
                Get-ChildItem -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction Stop
                Write-RepairLog "Cleared '$cachePath'."
            }
        }
    }

    if ($ResetNetwork -and $PSCmdlet.ShouldProcess('Windows network stack', 'Flush DNS and reset Winsock')) {
        Clear-DnsClientCache -ErrorAction Stop
        Invoke-NativeCommand -Name 'Winsock Reset' -FilePath 'netsh.exe' -ArgumentList @('winsock', 'reset')
        Write-RepairLog 'DNS cache was cleared and Winsock was reset. Restart Windows to complete the network reset.'
        'Restart Windows to complete the Winsock reset.' |
            Set-Content -LiteralPath (Join-Path $OutputPath 'restart-required.txt') -Encoding UTF8
    }

    if ($RepairWebView2) {
        $setupPath = Find-WebView2Setup
        if (-not $setupPath) {
            throw 'Microsoft Edge WebView2 setup.exe was not found in standard installation paths.'
        }

        if ($PSCmdlet.ShouldProcess('Microsoft Edge WebView2 Runtime', 'Run system-level repair')) {
            $process = Start-Process -FilePath $setupPath `
                -ArgumentList @('--repair', '--msedgewebview', '--system-level', '--verbose-logging') `
                -Wait -PassThru -ErrorAction Stop
            if ($process.ExitCode -ne 0) {
                throw "WebView2 repair exited with code $($process.ExitCode)."
            }
            Write-RepairLog 'WebView2 repair completed successfully.'
        }
    }

    if ($RestartAudioVideoServices) {
        foreach ($serviceName in 'AudioEndpointBuilder', 'Audiosrv', 'FrameServer') {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if (-not $service) {
                Add-RepairWarning "Service '$serviceName' is unavailable."
                continue
            }

            if ($PSCmdlet.ShouldProcess($serviceName, 'Restart media service')) {
                try {
                    if ($service.Status -eq 'Running') {
                        Restart-Service -Name $serviceName -Force -ErrorAction Stop
                    }
                    else {
                        Start-Service -Name $serviceName -ErrorAction Stop
                    }
                    Write-RepairLog "Started or restarted '$serviceName'."
                }
                catch {
                    Add-RepairWarning "Could not restart '$serviceName': $($_.Exception.Message)"
                }
            }
        }
    }

    $warnings | Set-Content -LiteralPath (Join-Path $OutputPath 'warnings.txt') -Encoding UTF8
    if ($warnings.Count -gt 0) {
        Write-RepairLog -Level WARN -Message "Completed with $($warnings.Count) warning(s)."
        exit 2
    }

    Write-RepairLog 'Microsoft Stream playback and upload repair workflow completed.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
