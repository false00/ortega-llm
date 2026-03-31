param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$preferredModelName = "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf"
$stateDir = Join-Path $repoRoot ".shard"
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
    "4" = @{
        Name = "XL Context"
        Description = "16K token context for extended reasoning"
        Context = 16384
        Ngl = 32
        Threads = 12
        FlashAttn = "on"
        Speed = "5-6 tok/s (author estimate)"
    }
    "5" = @{
        Name = "XXL Context"
        Description = "32K token context for very long documents"
        Context = 32768
        Ngl = 20
        Threads = 12
        FlashAttn = "on"
        Speed = "2-3 tok/s (author estimate)"
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
    if ($env:SHARD_RUNTIME_EXE -and (Test-Path $env:SHARD_RUNTIME_EXE)) {
        return $env:SHARD_RUNTIME_EXE
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
    if ($env:SHARD_MODEL_PATH -and (Test-Path $env:SHARD_MODEL_PATH)) {
        return $env:SHARD_MODEL_PATH
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
        Write-Host "shard: warning: could not parse profile overrides, using defaults"
    }

    return $profiles
}

function Save-Profiles($profilesToSave) {
    Ensure-StateDir
    ($profilesToSave | ConvertTo-Json -Depth 8) | Set-Content -Path $profileOverrideFile -Encoding UTF8
}

function Stop-Shard {
    $p = Get-RunningProcessFromState
    if ($null -eq $p) {
        Write-Host "shard: no running server found"
        return
    }

    Stop-Process -Id $p.Id -Force
    Clear-ServerState
    Write-Host "shard: stopped server (PID $($p.Id))"
}

function Start-Shard([string]$profileId) {
    $runtimeExe = Resolve-RuntimeExe
    $modelPath = Resolve-ModelPath

    if (-not $runtimeExe -or -not (Test-Path $runtimeExe)) {
        throw "llama-server not found. Run .\\scripts\\install-shard.ps1 to bootstrap runtime assets."
    }
    if (-not $modelPath -or -not (Test-Path $modelPath)) {
        throw "GGUF model not found. Run .\\scripts\\install-shard.ps1 to download the default model."
    }
    if (-not $profiles.Contains($profileId)) {
        throw "invalid profile id: $profileId"
    }

    $profile = $profiles[$profileId]
    $running = Get-RunningProcessFromState

    if ($null -ne $running) {
        $state = Get-ServerState
        if ($state.ProfileId -eq $profileId) {
            Write-Host "shard: already running profile $profileId ($($profile.Name)) on http://127.0.0.1:8080"
            Write-Host "shard: PID $($running.Id)"
            return
        }

        Write-Host "shard: switching from profile $($state.ProfileId) to $profileId"
        Stop-Shard
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
        throw "shard: server exited during startup. Last stderr lines:`n$stderrTail"
    }

    Write-Host "shard: started profile $profileId ($($profile.Name))"
    Write-Host "shard: endpoint http://127.0.0.1:8080"
    Write-Host "shard: PID $($proc.Id)"
    Write-Host "shard: logs"
    Write-Host "  stdout: $stdoutLog"
    Write-Host "  stderr: $stderrLog"
}

function Show-Profiles {
    Write-Host "shard profiles"
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

function Detect-SystemSpecs {
    $specs = [ordered]@{
        OS = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        CPUName = $null
        CPUCores = [Environment]::ProcessorCount
        RecommendedThreads = [Math]::Max(4, [Math]::Min(16, [int][Math]::Floor([Environment]::ProcessorCount / 2)))
        TotalRAM_GB = $null
        GPUName = $null
        VRAM_GB = $null
        CUDAVersion = $null
    }

    # RAM
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $specs.TotalRAM_GB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        }
    } catch {}

    # CPU
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu) {
            $specs.CPUName = $cpu.Name.Trim()
        }
    } catch {}

    # GPU via nvidia-smi
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        try {
            $raw = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null | Out-String
            $lines = $raw.Trim() -split "`r?`n" | Where-Object { $_ -match "\S" }
            if ($lines.Count -gt 0) {
                $parts = $lines[0] -split ","
                $specs.GPUName = $parts[0].Trim()
                if ($parts.Count -gt 1) {
                    $specs.VRAM_GB = [Math]::Round([double]$parts[1].Trim() / 1024, 1)
                }
            }
        } catch {}

        try {
            $rawCuda = & nvidia-smi 2>$null | Out-String
            if ($rawCuda -match "CUDA Version:\s*([0-9]+\.[0-9]+)") {
                $specs.CUDAVersion = $Matches[1]
            }
        } catch {}
    }

    return $specs
}

function Show-DetectedSpecs {
    $specs = Detect-SystemSpecs

    Write-Host "shard: detected system specs"
    Write-Host "-----------------------------"
    Write-Host ("  OS:         {0}" -f $specs.OS)
    Write-Host ("  CPU:        {0}" -f $(if ($specs.CPUName) { $specs.CPUName } else { "unknown" }))
    Write-Host ("  CPU cores:  {0}" -f $specs.CPUCores)
    Write-Host ("  Threads:    {0} (recommended for llama.cpp)" -f $specs.RecommendedThreads)
    Write-Host ("  RAM:        {0} GB" -f $(if ($specs.TotalRAM_GB) { $specs.TotalRAM_GB } else { "unknown" }))
    Write-Host ("  GPU:        {0}" -f $(if ($specs.GPUName) { $specs.GPUName } else { "not detected (CPU-only mode)" }))
    Write-Host ("  VRAM:       {0}" -f $(if ($specs.VRAM_GB) { "{0} GB" -f $specs.VRAM_GB } else { "n/a" }))
    Write-Host ("  CUDA:       {0}" -f $(if ($specs.CUDAVersion) { $specs.CUDAVersion } else { "n/a" }))
    Write-Host ""

    if (-not $specs.GPUName) {
        Write-Host "  No NVIDIA GPU detected. The server will run in CPU-only mode."
        Write-Host "  Offloading layers (-ngl) will have no effect."
    } else {
        Write-Host "  GPU detected. Run 'shard recalc' to benchmark and auto-tune"
        Write-Host "  profiles for your specific hardware."
    }

    Write-Host ""
    Write-Host "  Default profiles are based on the author's system (RTX 4080, 64 GB RAM)."
    Write-Host "  Run 'shard recalc' to generate optimized profiles for this machine."
}

function Show-Usage {
    Write-Host "usage:"
    Write-Host "  shard            start profile 1 (daily default)"
    Write-Host "  shard 1          start/switch to profile 1"
    Write-Host "  shard 2          start/switch to profile 2"
    Write-Host "  shard 3          start/switch to profile 3"
    Write-Host "  shard ls         list profiles"
    Write-Host "  shard stop       stop running server"
    Write-Host "  shard status     show running status"
    Write-Host "  shard info       show resolved runtime/model paths"
    Write-Host "  shard detect     show detected system specs"
    Write-Host "  shard update     update llama.cpp runtime + model to latest"
    Write-Host "  shard recalc     benchmark this hardware and recalculate profiles"
    Write-Host "  shard reset      remove profile overrides and return to defaults"
}

function Show-Status {
    $running = Get-RunningProcessFromState
    if ($null -eq $running) {
        Write-Host "shard: server is not running"
        return
    }

    $state = Get-ServerState
    $profiles = Load-Profiles
    $profile = $profiles[$state.ProfileId]

    Write-Host ("shard: running profile {0} ({1})" -f $state.ProfileId, $state.ProfileName)
    Write-Host ("shard: PID {0}" -f $running.Id)
    Write-Host ""
    Write-Host "Profile parameters:"
    Write-Host ("  -ngl {0}" -f $profile.Ngl)
    Write-Host ("  -c {0}" -f $profile.Context)
    Write-Host ("  -t {0}" -f $profile.Threads)
    Write-Host ("  -fa {0}" -f $profile.FlashAttn)
    Write-Host ("  speed: {0}" -f $profile.Speed)
    Write-Host ""
    Write-Host "API endpoint:"
    Write-Host ("  {0}" -f $state.Url)
}

function Show-Info {
    $runtimeExe = Resolve-RuntimeExe
    $modelPath = Resolve-ModelPath

    Write-Host "shard: resolved paths"
    Write-Host ("  runtime: {0}" -f ($(if ($runtimeExe) { $runtimeExe } else { "<not found>" })))
    Write-Host ("  model:   {0}" -f ($(if ($modelPath) { $modelPath } else { "<not found>" })))

    if ($env:SHARD_RUNTIME_EXE) {
        Write-Host ("  SHARD_RUNTIME_EXE override: {0}" -f $env:SHARD_RUNTIME_EXE)
    }
    if ($env:SHARD_MODEL_PATH) {
        Write-Host ("  SHARD_MODEL_PATH override:   {0}" -f $env:SHARD_MODEL_PATH)
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

function Measure-ContextCandidate {
    param(
        [string]$completionExe,
        [string]$modelPath,
        [int]$ngl,
        [int]$context,
        [int]$threads
    )

    $out = & $completionExe -m $modelPath -ngl $ngl -c $context -n 64 -t $threads -fa on -no-cnv --temp 0.3 --no-warmup -p "Test." 2>&1 | Out-String

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
        throw "llama-server not found. Install runtime first with .\\scripts\\install-shard.ps1"
    }
    if (-not $modelPath -or -not (Test-Path $modelPath)) {
        throw "model not found. Install model first with .\\scripts\\install-shard.ps1"
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
        Write-Host ("shard: stopping running server (profile {0}) before calibration" -f $resumeProfileId)
        Stop-Shard
        Start-Sleep -Seconds 1
    }

    $threads = [Math]::Max(4, [Math]::Min(16, [int][Math]::Floor([Environment]::ProcessorCount / 2)))
    $candidates4096 = @(32, 40, 44, 48, 56, 64)
    $candidateArg = ($candidates4096 -join ",")

    Write-Host "shard: recalc started"
    Write-Host ("shard: benchmarking 4096-context candidates: {0}" -f $candidateArg)

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

    Write-Host ("shard: best 4096 profile => ngl {0}, {1} tok/s" -f $best4096.Ngl, ([Math]::Round($best4096.TokensPerSecond, 2)))

    $candidates8192 = @(56, 48, 44, 40, 32)
    $results8192 = @()

    Write-Host "shard: probing 8192-context candidates (this may take a bit)..."
    foreach ($ngl in $candidates8192) {
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 8192 -threads $threads
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

    # --- Profile 4: 16K context ---
    $candidates16k = @(48, 44, 40, 32, 24, 20)
    $results16k = @()

    Write-Host "shard: probing 16384-context candidates..."
    foreach ($ngl in $candidates16k) {
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 16384 -threads $threads
        if ($null -eq $speed) {
            Write-Host ("  ngl {0}: failed" -f $ngl)
            continue
        }

        Write-Host ("  ngl {0}: {1} tok/s" -f $ngl, ([Math]::Round($speed, 2)))
        $results16k += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
    }

    if ($results16k.Count -gt 0) {
        $best16k = $results16k | Sort-Object TokensPerSecond -Descending | Select-Object -First 1
        $profiles["4"].Ngl = [int]$best16k.Ngl
        $profiles["4"].Context = 16384
        $profiles["4"].Threads = $threads
        $profiles["4"].Speed = "{0} tok/s" -f ([Math]::Round($best16k.TokensPerSecond, 2))
    } else {
        Write-Host "shard: all 16384 candidates failed, profile 4 kept at defaults"
    }

    # --- Profile 5: 32K context ---
    $candidates32k = @(32, 24, 20, 16, 12, 8)
    $results32k = @()

    Write-Host "shard: probing 32768-context candidates..."
    foreach ($ngl in $candidates32k) {
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 32768 -threads $threads
        if ($null -eq $speed) {
            Write-Host ("  ngl {0}: failed" -f $ngl)
            continue
        }

        Write-Host ("  ngl {0}: {1} tok/s" -f $ngl, ([Math]::Round($speed, 2)))
        $results32k += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
    }

    if ($results32k.Count -gt 0) {
        $best32k = $results32k | Sort-Object TokensPerSecond -Descending | Select-Object -First 1
        $profiles["5"].Ngl = [int]$best32k.Ngl
        $profiles["5"].Context = 32768
        $profiles["5"].Threads = $threads
        $profiles["5"].Speed = "{0} tok/s" -f ([Math]::Round($best32k.TokensPerSecond, 2))
    } else {
        Write-Host "shard: all 32768 candidates failed, profile 5 kept at defaults"
    }

    Save-Profiles -profilesToSave $profiles

    Write-Host ""
    Write-Host "shard: recalculation complete"
    Write-Host ("  profile 1 => -ngl {0} -c {1} -t {2} ({3})" -f $profiles["1"].Ngl, $profiles["1"].Context, $profiles["1"].Threads, $profiles["1"].Speed)
    Write-Host ("  profile 2 => -ngl {0} -c {1} -t {2} ({3})" -f $profiles["2"].Ngl, $profiles["2"].Context, $profiles["2"].Threads, $profiles["2"].Speed)
    Write-Host ("  profile 3 => -ngl {0} -c {1} -t {2} ({3})" -f $profiles["3"].Ngl, $profiles["3"].Context, $profiles["3"].Threads, $profiles["3"].Speed)
    Write-Host ("  profile 4 => -ngl {0} -c {1} -t {2} ({3})" -f $profiles["4"].Ngl, $profiles["4"].Context, $profiles["4"].Threads, $profiles["4"].Speed)
    Write-Host ("  profile 5 => -ngl {0} -c {1} -t {2} ({3})" -f $profiles["5"].Ngl, $profiles["5"].Context, $profiles["5"].Threads, $profiles["5"].Speed)
    Write-Host ("  overrides saved to: {0}" -f $profileOverrideFile)

    if ($resumeProfileId) {
        Write-Host ("shard: restarting previously running profile {0}" -f $resumeProfileId)
        Start-Shard -profileId $resumeProfileId
    }
}

function Reset-Profiles {
    if (Test-Path $profileOverrideFile) {
        Remove-Item -Path $profileOverrideFile -Force
        Write-Host "shard: removed profile overrides"
    } else {
        Write-Host "shard: no profile overrides found"
    }
}

function Update-Shard {
    $installScript = Join-Path $repoRoot "scripts\install-shard.ps1"
    if (-not (Test-Path $installScript)) {
        throw "install script not found: $installScript"
    }

    $resumeProfileId = $null
    $running = Get-RunningProcessFromState
    if ($null -ne $running) {
        $runningState = Get-ServerState
        $resumeProfileId = $runningState.ProfileId
        Write-Host ("shard: stopping running server (profile {0}) before update" -f $resumeProfileId)
        Stop-Shard
        Start-Sleep -Seconds 1
    }

    Write-Host "shard: updating llama.cpp runtime and model to latest supported assets..."
    & $installScript -Force
    if ($LASTEXITCODE -ne 0) {
        throw "shard: update failed"
    }

    if ($resumeProfileId) {
        $profiles = Load-Profiles
        Write-Host ("shard: restarting previously running profile {0}" -f $resumeProfileId)
        Start-Shard -profileId $resumeProfileId
    }

    Write-Host "shard: update complete"
}

$profiles = Load-Profiles

if ($CommandArgs.Count -eq 0) {
    Start-Shard -profileId "1"
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
        Stop-Shard
    }
    "status" {
        Show-Status
    }
    "info" {
        Show-Info
    }
    "detect" {
        Show-DetectedSpecs
    }
    "update" {
        Update-Shard
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
            Start-Shard -profileId $cmd
        } else {
            Show-Usage
            throw "unknown command: $cmd"
        }
    }
}
