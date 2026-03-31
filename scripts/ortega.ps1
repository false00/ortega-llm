param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$preferredModelName = "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf"
$stateDir = Join-Path $repoRoot ".ortega"
$stateFile = Join-Path $stateDir "state.json"
$profileOverrideFile = Join-Path $stateDir "profiles.json"
$stdoutLog = Join-Path $stateDir "server.stdout.log"
$stderrLog = Join-Path $stateDir "server.stderr.log"

$defaultProfiles = [ordered]@{
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
    if ($null -eq $state -or $null -eq $state.Pid) {
        return $null
    }

    $p = Get-Process -Id ([int]$state.Pid) -ErrorAction SilentlyContinue
    if ($null -eq $p) {
        Clear-ServerState
        return $null
    }

    return $p
}

function Resolve-RuntimeExe {
    if ($env:ORTEGA_RUNTIME_EXE -and (Test-Path $env:ORTEGA_RUNTIME_EXE)) {
        return $env:ORTEGA_RUNTIME_EXE
    }

    $toolsDir = Join-Path $repoRoot "tools"
    if (-not (Test-Path $toolsDir)) {
        return $null
    }

    $serverExes = Get-ChildItem -Path $toolsDir -Recurse -File -Filter "llama-server.exe" -ErrorAction SilentlyContinue
    if ($null -eq $serverExes -or $serverExes.Count -eq 0) {
        return $null
    }

    $preferred = $serverExes |
        Sort-Object @{Expression = { if ($_.FullName -match "cuda") { 0 } else { 1 } }}, @{Expression = { $_.LastWriteTime }; Descending = $true } |
        Select-Object -First 1

    return $preferred.FullName
}

function Resolve-CompletionExe {
    param([string]$runtimeExe)

    if (-not $runtimeExe) {
        return $null
    }

    $dir = Split-Path -Parent $runtimeExe
    $candidate = Join-Path $dir "llama-completion.exe"
    if (Test-Path $candidate) {
        return $candidate
    }

    return $null
}

function Resolve-BenchExe {
    param([string]$runtimeExe)

    if (-not $runtimeExe) {
        return $null
    }

    $dir = Split-Path -Parent $runtimeExe
    $candidate = Join-Path $dir "llama-bench.exe"
    if (Test-Path $candidate) {
        return $candidate
    }

    return $null
}

function Resolve-ModelPath {
    if ($env:ORTEGA_MODEL_PATH -and (Test-Path $env:ORTEGA_MODEL_PATH)) {
        return $env:ORTEGA_MODEL_PATH
    }

    $modelsDir = Join-Path $repoRoot "models"
    if (-not (Test-Path $modelsDir)) {
        return $null
    }

    $preferred = Join-Path $modelsDir $preferredModelName
    if (Test-Path $preferred) {
        return $preferred
    }

    $ggufs = Get-ChildItem -Path $modelsDir -File -Filter "*.gguf" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if ($null -eq $ggufs -or $ggufs.Count -eq 0) {
        return $null
    }

    return $ggufs[0].FullName
}

function Load-Profiles {
    $profiles = [ordered]@{}

    foreach ($id in $defaultProfiles.Keys) {
        $profiles[$id] = @{
            Name = $defaultProfiles[$id].Name
            Description = $defaultProfiles[$id].Description
            Context = [int]$defaultProfiles[$id].Context
            Ngl = [int]$defaultProfiles[$id].Ngl
            Threads = [int]$defaultProfiles[$id].Threads
            FlashAttn = $defaultProfiles[$id].FlashAttn
            Speed = $defaultProfiles[$id].Speed
        }
    }

    if (-not (Test-Path $profileOverrideFile)) {
        return $profiles
    }

    try {
        $override = Get-Content -Raw -Path $profileOverrideFile | ConvertFrom-Json -AsHashtable
        foreach ($id in $override.Keys) {
            if (-not $profiles.Contains($id)) {
                continue
            }

            foreach ($k in $override[$id].Keys) {
                $profiles[$id][$k] = $override[$id][$k]
            }

            $profiles[$id].Context = [int]$profiles[$id].Context
            $profiles[$id].Ngl = [int]$profiles[$id].Ngl
            $profiles[$id].Threads = [int]$profiles[$id].Threads
        }
    } catch {
        Write-Host "ortega: warning: could not parse profile overrides, using defaults"
    }

    return $profiles
}

function Save-Profiles($profilesToSave) {
    Ensure-StateDir
    ($profilesToSave | ConvertTo-Json -Depth 8) | Set-Content -Path $profileOverrideFile -Encoding UTF8
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
    $runtimeExe = Resolve-RuntimeExe
    $modelPath = Resolve-ModelPath

    if (-not $runtimeExe -or -not (Test-Path $runtimeExe)) {
        throw "llama-server not found. Run .\\scripts\\install-ortega.ps1 to bootstrap runtime assets."
    }
    if (-not $modelPath -or -not (Test-Path $modelPath)) {
        throw "GGUF model not found. Run .\\scripts\\install-ortega.ps1 to download the default model."
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

    if (Test-Path $profileOverrideFile) {
        Write-Host ""
        Write-Host ("profile overrides: {0}" -f $profileOverrideFile)
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
    Write-Host "  ortega info       show resolved runtime/model paths"
    Write-Host "  ortega update     update llama.cpp runtime + model to latest"
    Write-Host "  ortega recalc     benchmark this hardware and recalculate profiles"
    Write-Host "  ortega reset      remove profile overrides and return to defaults"
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

function Show-Info {
    $runtimeExe = Resolve-RuntimeExe
    $modelPath = Resolve-ModelPath

    Write-Host "ortega: resolved paths"
    Write-Host ("  runtime: {0}" -f ($(if ($runtimeExe) { $runtimeExe } else { "<not found>" })))
    Write-Host ("  model:   {0}" -f ($(if ($modelPath) { $modelPath } else { "<not found>" })))

    if ($env:ORTEGA_RUNTIME_EXE) {
        Write-Host ("  ORTEGA_RUNTIME_EXE override: {0}" -f $env:ORTEGA_RUNTIME_EXE)
    }
    if ($env:ORTEGA_MODEL_PATH) {
        Write-Host ("  ORTEGA_MODEL_PATH override:   {0}" -f $env:ORTEGA_MODEL_PATH)
    }
}

function Parse-BenchTg64 {
    param([string]$text)

    $results = @()
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -notmatch "\|" -or $line -notmatch "tg64") {
            continue
        }

        $parts = $line.Split('|') | ForEach-Object { $_.Trim() }
        if ($parts.Count -lt 10) {
            continue
        }

        $nglText = $parts[5]
        $test = $parts[8]
        $tsText = $parts[9]

        if ($test -ne "tg64") {
            continue
        }

        $nglMatch = [regex]::Match($nglText, "\d+")
        $tsMatch = [regex]::Match($tsText, "[0-9]+(\.[0-9]+)?")
        if (-not $nglMatch.Success -or -not $tsMatch.Success) {
            continue
        }

        $results += [pscustomobject]@{
            Ngl = [int]$nglMatch.Value
            TokensPerSecond = [double]$tsMatch.Value
        }
    }

    return $results
}

function Measure-8192Candidate {
    param(
        [string]$completionExe,
        [string]$modelPath,
        [int]$ngl,
        [int]$threads
    )

    $out = & $completionExe -m $modelPath -ngl $ngl -c 8192 -n 64 -t $threads -fa on -no-cnv --temp 0.3 --no-warmup -p "Test." 2>&1 | Out-String

    if ($LASTEXITCODE -ne 0 -or $out -match "failed to fit params|error:") {
        return $null
    }

    $m = [regex]::Match($out, "eval time\s*=.*?,\s*([0-9]+(\.[0-9]+)?)\s*tokens per second")
    if (-not $m.Success) {
        return $null
    }

    return [double]$m.Groups[1].Value
}

function Recalculate-Profiles {
    $runtimeExe = Resolve-RuntimeExe
    $modelPath = Resolve-ModelPath
    $benchExe = Resolve-BenchExe -runtimeExe $runtimeExe
    $completionExe = Resolve-CompletionExe -runtimeExe $runtimeExe

    if (-not $runtimeExe -or -not (Test-Path $runtimeExe)) {
        throw "llama-server not found. Install runtime first with .\\scripts\\install-ortega.ps1"
    }
    if (-not $modelPath -or -not (Test-Path $modelPath)) {
        throw "model not found. Install model first with .\\scripts\\install-ortega.ps1"
    }
    if (-not $benchExe -or -not (Test-Path $benchExe)) {
        throw "llama-bench.exe not found next to runtime"
    }
    if (-not $completionExe -or -not (Test-Path $completionExe)) {
        throw "llama-completion.exe not found next to runtime"
    }

    $resumeProfileId = $null
    $alreadyRunning = Get-RunningProcessFromState
    if ($null -ne $alreadyRunning) {
        $runningState = Get-ServerState
        $resumeProfileId = $runningState.ProfileId
        Write-Host ("ortega: stopping running server (profile {0}) before calibration" -f $resumeProfileId)
        Stop-Ortega
        Start-Sleep -Seconds 1
    }

    $threads = [Math]::Max(4, [Math]::Min(16, [int][Math]::Floor([Environment]::ProcessorCount / 2)))
    $candidates4096 = @(32, 40, 44, 48, 56, 64)
    $candidateArg = ($candidates4096 -join ",")

    Write-Host "ortega: recalc started"
    Write-Host ("ortega: benchmarking 4096-context candidates: {0}" -f $candidateArg)

    $benchOut = & $benchExe -m $modelPath -r 1 --no-warmup -p 256 -n 64 -t $threads -ngl $candidateArg -fa 1 -o md 2>&1 | Out-String
    $benchRows = Parse-BenchTg64 -text $benchOut

    if ($benchRows.Count -eq 0) {
        throw "could not parse benchmark output for 4096 profile"
    }

    $best4096 = $benchRows | Sort-Object TokensPerSecond -Descending | Select-Object -First 1

    $fallback4096 = $benchRows |
        Where-Object { $_.Ngl -lt $best4096.Ngl } |
        Sort-Object TokensPerSecond -Descending |
        Select-Object -First 1

    if ($null -eq $fallback4096) {
        $fallback4096 = $best4096
    }

    Write-Host ("ortega: best 4096 profile => ngl {0}, {1} tok/s" -f $best4096.Ngl, ([Math]::Round($best4096.TokensPerSecond, 2)))

    $candidates8192 = @(56, 48, 44, 40, 32)
    $results8192 = @()

    Write-Host "ortega: probing 8192-context candidates (this may take a bit)..."
    foreach ($ngl in $candidates8192) {
        $speed = Measure-8192Candidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -threads $threads
        if ($null -eq $speed) {
            Write-Host ("  ngl {0}: failed" -f $ngl)
            continue
        }

        Write-Host ("  ngl {0}: {1} tok/s" -f $ngl, ([Math]::Round($speed, 2)))
        $results8192 += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
    }

    if ($results8192.Count -eq 0) {
        throw "all 8192 candidates failed on this hardware"
    }

    $best8192 = $results8192 | Sort-Object TokensPerSecond -Descending | Select-Object -First 1

    $profiles["1"].Ngl = [int]$best4096.Ngl
    $profiles["1"].Context = 4096
    $profiles["1"].Threads = $threads
    $profiles["1"].Speed = "{0} tok/s" -f ([Math]::Round($best4096.TokensPerSecond, 2))

    $profiles["2"].Ngl = [int]$fallback4096.Ngl
    $profiles["2"].Context = 4096
    $profiles["2"].Threads = $threads
    $profiles["2"].Speed = "{0} tok/s" -f ([Math]::Round($fallback4096.TokensPerSecond, 2))

    $profiles["3"].Ngl = [int]$best8192.Ngl
    $profiles["3"].Context = 8192
    $profiles["3"].Threads = $threads
    $profiles["3"].Speed = "{0} tok/s" -f ([Math]::Round($best8192.TokensPerSecond, 2))

    Save-Profiles -profilesToSave $profiles

    Write-Host ""
    Write-Host "ortega: recalculation complete"
    Write-Host ("  profile 1 => -ngl {0} -c {1} -t {2} ({3})" -f $profiles["1"].Ngl, $profiles["1"].Context, $profiles["1"].Threads, $profiles["1"].Speed)
    Write-Host ("  profile 2 => -ngl {0} -c {1} -t {2} ({3})" -f $profiles["2"].Ngl, $profiles["2"].Context, $profiles["2"].Threads, $profiles["2"].Speed)
    Write-Host ("  profile 3 => -ngl {0} -c {1} -t {2} ({3})" -f $profiles["3"].Ngl, $profiles["3"].Context, $profiles["3"].Threads, $profiles["3"].Speed)
    Write-Host ("  overrides saved to: {0}" -f $profileOverrideFile)

    if ($resumeProfileId) {
        Write-Host ("ortega: restarting previously running profile {0}" -f $resumeProfileId)
        Start-Ortega -profileId $resumeProfileId
    }
}

function Reset-Profiles {
    if (Test-Path $profileOverrideFile) {
        Remove-Item -Path $profileOverrideFile -Force
        Write-Host "ortega: removed profile overrides"
    } else {
        Write-Host "ortega: no profile overrides found"
    }
}

function Update-Ortega {
    $installScript = Join-Path $repoRoot "scripts\install-ortega.ps1"
    if (-not (Test-Path $installScript)) {
        throw "install script not found: $installScript"
    }

    $resumeProfileId = $null
    $running = Get-RunningProcessFromState
    if ($null -ne $running) {
        $runningState = Get-ServerState
        $resumeProfileId = $runningState.ProfileId
        Write-Host ("ortega: stopping running server (profile {0}) before update" -f $resumeProfileId)
        Stop-Ortega
        Start-Sleep -Seconds 1
    }

    Write-Host "ortega: updating llama.cpp runtime and model to latest supported assets..."
    & $installScript -Force
    if ($LASTEXITCODE -ne 0) {
        throw "ortega: update failed"
    }

    if ($resumeProfileId) {
        $profiles = Load-Profiles
        Write-Host ("ortega: restarting previously running profile {0}" -f $resumeProfileId)
        Start-Ortega -profileId $resumeProfileId
    }

    Write-Host "ortega: update complete"
}

$profiles = Load-Profiles

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
    "info" {
        Show-Info
    }
    "update" {
        Update-Ortega
    }
    "recalc" {
        Recalculate-Profiles
    }
    "reset" {
        Reset-Profiles
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
