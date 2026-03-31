param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "shard: requires PowerShell 7 or later (running $($PSVersionTable.PSVersion))"
    Write-Host "Install from: https://aka.ms/install-powershell"
    Write-Host "Then re-run with: pwsh -File $($MyInvocation.MyCommand.Path) $($CommandArgs -join ' ')"
    exit 1
}

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$preferredModelName = "Qwen3.5-27B.Q4_K_M.gguf"
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
            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $raw = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null | Out-String
            $ErrorActionPreference = $prevEAP
            $lines = @($raw.Trim() -split "`r?`n" | Where-Object { $_ -match "\S" })
            if ($lines.Count -gt 0) {
                $parts = $lines[0] -split ","
                $specs.GPUName = $parts[0].Trim()
                if ($parts.Count -gt 1) {
                    $specs.VRAM_GB = [Math]::Round([double]$parts[1].Trim() / 1024, 1)
                }
            }
        } catch { $ErrorActionPreference = $prevEAP }

        try {
            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $rawCuda = & nvidia-smi 2>$null | Out-String
            $ErrorActionPreference = $prevEAP
            if ($rawCuda -match "CUDA Version:\s*([0-9]+\.[0-9]+)") {
                $specs.CUDAVersion = $Matches[1]
            }
        } catch { $ErrorActionPreference = $prevEAP }
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
        if ($parts.Count -lt 8) {
            continue
        }

        # Find tg64 column dynamically - format varies across llama-bench versions
        $tgIdx = -1
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -match '^tg\d+$') {
                $tgIdx = $i
                break
            }
        }
        if ($tgIdx -lt 0 -or ($tgIdx + 1) -ge $parts.Count) { continue }

        # ngl is always the 6th column (index 5): model|size|params|backend|ngl
        $nglText = $parts[5]
        # t/s is always the column right after the test column
        $tsText = $parts[$tgIdx + 1]

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
        [int]$threads,
        [int]$candidateNum = 0,
        [int]$candidateTotal = 0
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ctxK = [int]($context / 1024)
    $counter = ''
    if ($candidateTotal -gt 0) { $counter = "[$candidateNum/$candidateTotal] " }
    Write-Host "  ${counter}ngl $ngl, ${ctxK}K context:"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $completionExe
    $psi.Arguments = "-m `"$modelPath`" -ngl $ngl -c $context -n 64 -t $threads -fa on -no-cnv --temp 0.3 --no-warmup -p `"Test.`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)

    # stdout is small (generated text) - read async to avoid deadlock
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()

    # stderr has progress and timing - stream line by line for real-time output
    $allStderr = [System.Text.StringBuilder]::new()
    $failed = $false
    while ($null -ne ($sline = $proc.StandardError.ReadLine())) {
        [void]$allStderr.AppendLine($sline)

        if ($sline -match 'failed to fit params|CUDA out of memory|out of memory') {
            $failed = $true
            $el = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
            Write-Host "    VRAM overflow - model does not fit at this ngl (${el}s)"
        }
        elseif ($sline -match 'offloading (\d+).*layers') {
            $layerCount = $Matches[1]
            Write-Host "    Offloading $layerCount layers to GPU..."
        }
        elseif ($sline -match 'common_perf_print:\s+load time\s*=\s*([0-9.]+)') {
            $loadS = [Math]::Round([double]$Matches[1] / 1000, 1)
            Write-Host "    Model loaded (${loadS}s), generating 64 tokens..."
        }
        elseif ($sline -match 'eval time\s*=.*?([0-9.]+)\s*tokens per second') {
            $tokSpeed = $Matches[1]
            Write-Host "    Speed: $tokSpeed tok/s"
        }
        elseif ($sline -match 'llama_memory_breakdown.*CUDA.*\|\s*(\d+)\s*=\s*(\d+)\s*\+') {
            $totalV = $Matches[1]; $freeV = $Matches[2]
            $usedV = [int]$totalV - [int]$freeV
            Write-Host "    VRAM: ${usedV} / ${totalV} MiB used (${freeV} MiB free)"
        }
    }

    [void]$stdoutTask.Result
    $proc.WaitForExit()

    $elapsed = $sw.Elapsed.TotalSeconds
    $elRound = [Math]::Round($elapsed, 1)
    $out = $allStderr.ToString()

    if ($proc.ExitCode -ne 0 -or $failed) {
        if (-not $failed) {
            Write-Host "    Failed with exit code $($proc.ExitCode) (${elRound}s)"
        }
        Write-Host ''
        return $null
    }

    $m = [regex]::Match($out, 'eval time\s*=.*?,\s*([0-9]+(\.[0-9]+)?)\s*tokens per second')
    if (-not $m.Success) {
        Write-Host "    No speed data captured (${elRound}s)"
        Write-Host ''
        return $null
    }

    $tps = [double]$m.Groups[1].Value
    Write-Host "    Done in ${elRound}s"
    Write-Host ''
    return $tps
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

    $totalSw = [System.Diagnostics.Stopwatch]::StartNew()
    $threads = [Math]::Max(4, [Math]::Min(16, [int][Math]::Floor([Environment]::ProcessorCount / 2)))

    Write-Host ''
    Write-Host '=========================================='
    Write-Host '  SHARD RECALC - Auto-Tuning Your Hardware'
    Write-Host '=========================================='
    Write-Host ("  Model:   {0}" -f (Split-Path $modelPath -Leaf))
    Write-Host ("  Threads: {0}" -f $threads)
    Write-Host ("  Runtime: {0}" -f (Split-Path $runtimeExe -Leaf))
    Write-Host ''
    Write-Host '  What is recalc doing?'
    Write-Host '  ---------------------'
    Write-Host '  This finds the fastest GPU offload settings for YOUR hardware.'
    Write-Host '  -ngl (GPU layers) controls how much of the model runs on your GPU.'
    Write-Host '  Higher ngl = faster, but too high overflows your VRAM and crashes.'
    Write-Host '  Recalc tests each ngl value at increasing context sizes to find'
    Write-Host '  the sweet spot where you get max speed without VRAM errors.'
    Write-Host '  Bigger context = more conversation memory but needs more VRAM.'
    Write-Host ''

    # -- Phase 1: 4K context bench sweep --
    $candidates4096 = @(32, 40, 44, 48, 56, 64)
    $candidateArg = ($candidates4096 -join ",")
    $phaseCount = 4
    $currentPhase = 1

    Write-Host "[$currentPhase/$phaseCount] SPEED TEST at 4K context (everyday chat)"
    Write-Host '  Testing which ngl values work at the smallest context size.'
    Write-Host '  This is the baseline - every ngl that works here is a candidate'
    Write-Host '  for your fastest daily-use profile.'
    Write-Host "  Candidates: ngl $candidateArg"
    Write-Host '  Running llama-bench - results stream as each ngl completes...'
    Write-Host ''

    $phaseSw = [System.Diagnostics.Stopwatch]::StartNew()
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $benchExe
    $psi.Arguments = "-m `"$modelPath`" -r 1 --no-warmup -p 256 -n 64 -t $threads -ngl $candidateArg -fa 1 -o md"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $benchProc = [System.Diagnostics.Process]::Start($psi)

    # stderr has init/debug info - read async to avoid deadlock
    $benchStderrTask = $benchProc.StandardError.ReadToEndAsync()

    # stdout has markdown table rows - stream for real-time per-ngl results
    $benchStdout = [System.Text.StringBuilder]::new()
    $benchTgCount = 0
    $benchTotal = $candidates4096.Count

    while ($null -ne ($bline = $benchProc.StandardOutput.ReadLine())) {
        [void]$benchStdout.AppendLine($bline)

        if ($bline -match '\|' -and $bline -match 'tg64') {
            $benchTgCount++
            $bparts = $bline.Split('|') | ForEach-Object { $_.Trim() }
            # Find tg column dynamically
            $tgI = -1
            for ($bi = 0; $bi -lt $bparts.Count; $bi++) {
                if ($bparts[$bi] -match '^tg\d+$') { $tgI = $bi; break }
            }
            if ($tgI -ge 0 -and ($tgI + 1) -lt $bparts.Count) {
                $nglM = [regex]::Match($bparts[5], '\d+')
                $tsM = [regex]::Match($bparts[$tgI + 1], '[0-9.]+')
                if ($nglM.Success -and $tsM.Success) {
                    $el = [Math]::Round($phaseSw.Elapsed.TotalSeconds, 0)
                    Write-Host "    [$benchTgCount/$benchTotal] ngl $($nglM.Value): $($tsM.Value) tok/s (${el}s elapsed)"
                }
            }
        }
    }

    $benchStderrContent = $benchStderrTask.Result
    $benchProc.WaitForExit()
    # merge both streams for robust parsing (table is on stdout with -o md)
    $benchOut = $benchStdout.ToString() + "`n" + $benchStderrContent
    $benchRows = Parse-BenchTg64 -text $benchOut

    if ($benchRows.Count -eq 0) {
        throw 'could not parse benchmark output for 4096 profile'
    }

    $phaseElapsed = [Math]::Round($phaseSw.Elapsed.TotalSeconds, 0)
    Write-Host "  Completed in ${phaseElapsed}s"

    $best4096 = $benchRows | Sort-Object TokensPerSecond -Descending | Select-Object -First 1

    $fallback4096 = $benchRows |
        Where-Object { $_.Ngl -lt $best4096.Ngl } |
        Sort-Object TokensPerSecond -Descending |
        Select-Object -First 1

    if ($null -eq $fallback4096) {
        $fallback4096 = $best4096
    }

    $b4ngl = $best4096.Ngl; $b4spd = [Math]::Round($best4096.TokensPerSecond, 2)
    $f4ngl = $fallback4096.Ngl; $f4spd = [Math]::Round($fallback4096.TokensPerSecond, 2)
    Write-Host "  Best: ngl $b4ngl at $b4spd tok/s, Fallback: ngl $f4ngl at $f4spd tok/s"
    Write-Host ""

    # -- Phase 2: 8K context probing --
    $currentPhase = 2
    $candidates8192 = @(56, 48, 44, 40, 32)
    $results8192 = @()

    $ccount = $candidates8192.Count; $clist = $candidates8192 -join ', '
    Write-Host "[$currentPhase/$phaseCount] VRAM FIT TEST at 8K context (longer conversations)"
    Write-Host '  Doubling context from 4K to 8K needs more VRAM for the KV cache.'
    Write-Host '  Testing which ngl values still fit without crashing.'
    Write-Host "  Candidates: ngl $clist (trying highest first, stopping when one works)"
    $cIdx = 0
    foreach ($ngl in $candidates8192) {
        $cIdx++
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 8192 -threads $threads -candidateNum $cIdx -candidateTotal $ccount
        if ($null -ne $speed) {
            $results8192 += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
        }
    }

    if ($results8192.Count -eq 0) {
        Write-Host '  All 8K candidates failed - keeping profile 3 at defaults'
    } else {
        $best8192 = $results8192 | Sort-Object TokensPerSecond -Descending | Select-Object -First 1
        $b8ngl = $best8192.Ngl; $b8spd = [Math]::Round($best8192.TokensPerSecond, 2)
        Write-Host "  Best 8K: ngl $b8ngl at $b8spd tok/s"
    }
    Write-Host ""

    # -- Phase 3: 16K context probing --
    $currentPhase = 3
    $candidates16k = @(48, 44, 40, 32, 24, 20)
    $results16k = @()

    $ccount = $candidates16k.Count; $clist = $candidates16k -join ', '
    Write-Host "[$currentPhase/$phaseCount] VRAM FIT TEST at 16K context (extended reasoning)"
    Write-Host '  16K context uses significantly more VRAM. Lower ngl values are'
    Write-Host '  expected here - some model layers move back to CPU to make room.'
    Write-Host "  Candidates: ngl $clist"
    $cIdx = 0
    foreach ($ngl in $candidates16k) {
        $cIdx++
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 16384 -threads $threads -candidateNum $cIdx -candidateTotal $ccount
        if ($null -ne $speed) {
            $results16k += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
        }
    }

    if ($results16k.Count -gt 0) {
        $best16k = $results16k | Sort-Object TokensPerSecond -Descending | Select-Object -First 1
        $b16ngl = $best16k.Ngl; $b16spd = [Math]::Round($best16k.TokensPerSecond, 2)
        Write-Host "  Best 16K: ngl $b16ngl at $b16spd tok/s"
    } else {
        Write-Host '  All 16K candidates failed - keeping profile 4 at defaults'
    }
    Write-Host ""

    # -- Phase 4: 32K context probing --
    $currentPhase = 4
    $candidates32k = @(32, 24, 20, 16, 12, 8)
    $results32k = @()

    $ccount = $candidates32k.Count; $clist = $candidates32k -join ', '
    Write-Host "[$currentPhase/$phaseCount] VRAM FIT TEST at 32K context (maximum memory)"
    Write-Host '  32K is the largest context window. This will be slowest but lets'
    Write-Host '  you feed very long documents or conversations. Many ngl values'
    Write-Host '  will fail here - that is normal.'
    Write-Host "  Candidates: ngl $clist"
    $cIdx = 0
    foreach ($ngl in $candidates32k) {
        $cIdx++
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 32768 -threads $threads -candidateNum $cIdx -candidateTotal $ccount
        if ($null -ne $speed) {
            $results32k += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
        }
    }

    if ($results32k.Count -gt 0) {
        $best32k = $results32k | Sort-Object TokensPerSecond -Descending | Select-Object -First 1
        $b32ngl = $best32k.Ngl; $b32spd = [Math]::Round($best32k.TokensPerSecond, 2)
        Write-Host "  Best 32K: ngl $b32ngl at $b32spd tok/s"
    } else {
        Write-Host '  All 32K candidates failed - keeping profile 5 at defaults'
    }
    Write-Host ""

    # -- Apply results to profiles --
    $profiles["1"].Ngl = [int]$best4096.Ngl
    $profiles["1"].Context = 4096
    $profiles["1"].Threads = $threads
    $profiles["1"].Speed = "{0} tok/s" -f ([Math]::Round($best4096.TokensPerSecond, 2))

    $profiles["2"].Ngl = [int]$fallback4096.Ngl
    $profiles["2"].Context = 4096
    $profiles["2"].Threads = $threads
    $profiles["2"].Speed = "{0} tok/s" -f ([Math]::Round($fallback4096.TokensPerSecond, 2))

    if ($results8192.Count -gt 0) {
        $profiles["3"].Ngl = [int]$best8192.Ngl
        $profiles["3"].Context = 8192
        $profiles["3"].Threads = $threads
        $profiles["3"].Speed = "{0} tok/s" -f ([Math]::Round($best8192.TokensPerSecond, 2))
    }

    if ($results16k.Count -gt 0) {
        $profiles["4"].Ngl = [int]$best16k.Ngl
        $profiles["4"].Context = 16384
        $profiles["4"].Threads = $threads
        $profiles["4"].Speed = "{0} tok/s" -f ([Math]::Round($best16k.TokensPerSecond, 2))
    }

    if ($results32k.Count -gt 0) {
        $profiles["5"].Ngl = [int]$best32k.Ngl
        $profiles["5"].Context = 32768
        $profiles["5"].Threads = $threads
        $profiles["5"].Speed = "{0} tok/s" -f ([Math]::Round($best32k.TokensPerSecond, 2))
    }

    Save-Profiles -profilesToSave $profiles

    $totalElapsed = $totalSw.Elapsed
    $totalMin = [int][Math]::Floor($totalElapsed.TotalMinutes)
    $totalSec = $totalElapsed.Seconds
    Write-Host "=========================================="
    Write-Host "  RECALC COMPLETE"
    Write-Host "  Total time: ${totalMin}m ${totalSec}s"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host '  Profile          Context   ngl   Speed'
    Write-Host '  ---------------  -------  ----  ----------------'
    for ($i = 1; $i -le 5; $i++) {
        $p = $profiles["$i"]
        $pName = $p.Name.PadRight(15)
        $ctxK = [int]($p.Context / 1024)
        $ctxStr = "${ctxK}K".PadRight(7)
        $pNgl = "$($p.Ngl)".PadLeft(4)
        Write-Host "  $pName  $ctxStr  $pNgl  $($p.Speed)"
    }
    Write-Host ""
    Write-Host "  Saved to: $profileOverrideFile"

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
