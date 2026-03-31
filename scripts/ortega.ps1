param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeExe = Join-Path $repoRoot "tools\llama-b8589-win-cuda\llama-server.exe"
$modelPath = Join-Path $repoRoot "models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf"
$stateDir = Join-Path $repoRoot ".ortega"
$stateFile = Join-Path $stateDir "state.json"
$stdoutLog = Join-Path $stateDir "server.stdout.log"
$stderrLog = Join-Path $stateDir "server.stderr.log"

$profiles = [ordered]@{
    "1" = @{
        Name = "Daily Default"
        Description = "Best overall for normal daily use"
        Context = 4096
        Ngl = 56
        Threads = 12
        FlashAttn = "on"
        Speed = "13.79-14.1 tok/s"
    }
    "2" = @{
        Name = "Stability Fallback"
        Description = "Extra VRAM headroom when fit errors happen"
        Context = 4096
        Ngl = 48
        Threads = 12
        FlashAttn = "on"
        Speed = "9-10 tok/s"
    }
    "3" = @{
        Name = "Long Context"
        Description = "Higher context history, lower speed"
        Context = 8192
        Ngl = 48
        Threads = 12
        FlashAttn = "on"
        Speed = "9.23 tok/s"
    }
}

function Ensure-StateDir {
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir | Out-Null
    }
}

function Get-ServerState {
    if (-not (Test-Path $stateFile)) {
        return $null
    }

    try {
        return Get-Content -Raw -Path $stateFile | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Set-ServerState($obj) {
    Ensure-StateDir
    ($obj | ConvertTo-Json -Depth 6) | Set-Content -Path $stateFile -Encoding UTF8
}

function Clear-ServerState {
    if (Test-Path $stateFile) {
        Remove-Item $stateFile -Force
    }
}

function Get-RunningProcessFromState {
    $state = Get-ServerState
    if ($null -eq $state) {
        return $null
    }

    if ($null -eq $state.Pid) {
        return $null
    }

    $p = Get-Process -Id ([int]$state.Pid) -ErrorAction SilentlyContinue
    if ($null -eq $p) {
        Clear-ServerState
        return $null
    }

    return $p
}

function Stop-Ortega {
    $p = Get-RunningProcessFromState
    if ($null -eq $p) {
        Write-Host "ortega: no running server found"
        return
    }

    Stop-Process -Id $p.Id -Force
    Clear-ServerState
    Write-Host "ortega: stopped server (PID $($p.Id))"
}

function Start-Ortega([string]$profileId) {
    if (-not (Test-Path $runtimeExe)) {
        throw "llama-server not found: $runtimeExe"
    }
    if (-not (Test-Path $modelPath)) {
        throw "model not found: $modelPath"
    }
    if (-not $profiles.Contains($profileId)) {
        throw "invalid profile id: $profileId"
    }

    $profile = $profiles[$profileId]
    $running = Get-RunningProcessFromState

    if ($null -ne $running) {
        $state = Get-ServerState
        if ($state.ProfileId -eq $profileId) {
            Write-Host "ortega: already running profile $profileId ($($profile.Name)) on http://127.0.0.1:8080"
            Write-Host "ortega: PID $($running.Id)"
            return
        }

        Write-Host "ortega: switching from profile $($state.ProfileId) to $profileId"
        Stop-Ortega
    }

    Ensure-StateDir

    $argList = @(
        "-m", ('"' + $modelPath + '"'),
        "-ngl", [string]$profile.Ngl,
        "-c", [string]$profile.Context,
        "-t", [string]$profile.Threads,
        "-fa", [string]$profile.FlashAttn,
        "--host", "127.0.0.1",
        "--port", "8080"
    )

    $proc = Start-Process -FilePath $runtimeExe -ArgumentList $argList -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

    $state = [ordered]@{
        Pid = $proc.Id
        ProfileId = $profileId
        ProfileName = $profile.Name
        StartedAt = (Get-Date).ToString("o")
        Url = "http://127.0.0.1:8080"
        Model = $modelPath
        Exe = $runtimeExe
    }
    Set-ServerState $state

    Start-Sleep -Seconds 2

    $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($null -eq $alive) {
        $stderrTail = ""
        if (Test-Path $stderrLog) {
            $stderrTail = (Get-Content -Path $stderrLog -Tail 30 -ErrorAction SilentlyContinue) -join "`n"
        }
        Clear-ServerState
        throw "ortega: server exited during startup. Last stderr lines:`n$stderrTail"
    }

    Write-Host "ortega: started profile $profileId ($($profile.Name))"
    Write-Host "ortega: endpoint http://127.0.0.1:8080"
    Write-Host "ortega: PID $($proc.Id)"
    Write-Host "ortega: logs"
    Write-Host "  stdout: $stdoutLog"
    Write-Host "  stderr: $stderrLog"
}

function Show-Profiles {
    Write-Host "ortega profiles"
    Write-Host "---------------"
    foreach ($id in $profiles.Keys) {
        $p = $profiles[$id]
        Write-Host ("[{0}] {1}" -f $id, $p.Name)
        Write-Host ("    {0}" -f $p.Description)
        Write-Host ("    flags: -ngl {0} -c {1} -t {2} -fa {3}" -f $p.Ngl, $p.Context, $p.Threads, $p.FlashAttn)
        Write-Host ("    speed: {0}" -f $p.Speed)
    }

    $running = Get-RunningProcessFromState
    if ($null -ne $running) {
        $state = Get-ServerState
        Write-Host ""
        Write-Host ("running: profile {0} ({1}), PID {2}" -f $state.ProfileId, $state.ProfileName, $running.Id)
    }
}

function Show-Usage {
    Write-Host "usage:"
    Write-Host "  ortega            start profile 1 (daily default)"
    Write-Host "  ortega 1          start/switch to profile 1"
    Write-Host "  ortega 2          start/switch to profile 2"
    Write-Host "  ortega 3          start/switch to profile 3"
    Write-Host "  ortega ls         list profiles"
    Write-Host "  ortega stop       stop running server"
    Write-Host "  ortega status     show running status"
}

function Show-Status {
    $running = Get-RunningProcessFromState
    if ($null -eq $running) {
        Write-Host "ortega: server is not running"
        return
    }

    $state = Get-ServerState
    Write-Host ("ortega: running profile {0} ({1})" -f $state.ProfileId, $state.ProfileName)
    Write-Host ("ortega: PID {0}" -f $running.Id)
    Write-Host ("ortega: endpoint {0}" -f $state.Url)
}

if ($CommandArgs.Count -eq 0) {
    Start-Ortega -profileId "1"
    exit 0
}

$cmd = $CommandArgs[0].ToLowerInvariant()

switch ($cmd) {
    "ls" {
        Show-Profiles
    }
    "list" {
        Show-Profiles
    }
    "stop" {
        Stop-Ortega
    }
    "status" {
        Show-Status
    }
    "help" {
        Show-Usage
    }
    "-h" {
        Show-Usage
    }
    "--help" {
        Show-Usage
    }
    default {
        if ($profiles.Contains($cmd)) {
            Start-Ortega -profileId $cmd
        } else {
            Show-Usage
            throw "unknown command: $cmd"
        }
    }
}
