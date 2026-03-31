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
$stateDir = Join-Path $repoRoot ".shard"
$stateFile = Join-Path $stateDir "state.json"
$profileOverrideFile = Join-Path $stateDir "profiles.json"
$stdoutLog = Join-Path $stateDir "server.stdout.log"
$stderrLog = Join-Path $stateDir "server.stderr.log"

# ── Model Catalog ──────────────────────────────────────────────────────────────
# All GGUF models from the Qwen3.5-Claude-4.6-Opus-Reasoning-Distilled collection
# Source: https://huggingface.co/collections/Jackrong/qwen35-claude-46-opus-reasoning-distilled
$CollectionUrl = "https://huggingface.co/collections/Jackrong/qwen35-claude-46-opus-reasoning-distilled"

$ModelCatalog = [ordered]@{
    "27B" = @{
        Name         = "Qwen3.5-27B"
        FullName     = "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled"
        Repo         = "Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-27B"
        Params       = "27B"
        MaxLayers    = 65
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K"   = "10.1 GB"
            "Q3_K_S" = "12.1 GB"
            "Q3_K_M" = "13.3 GB"
            "Q4_K_S" = "15.6 GB"
            "Q4_K_M" = "16.5 GB"
            "Q8_0"   = "28.6 GB"
        }
    }
    "9B" = @{
        Name         = "Qwen3.5-9B"
        FullName     = "Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled"
        Repo         = "Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-9B"
        Params       = "9B"
        MaxLayers    = 41
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K"   = "3.6 GB"
            "Q3_K_S" = "4.3 GB"
            "Q3_K_M" = "4.6 GB"
            "Q3_K_L" = "4.8 GB"
            "Q4_K_S" = "5.3 GB"
            "Q4_K_M" = "5.6 GB"
            "Q5_K_S" = "6.3 GB"
            "Q5_K_M" = "6.5 GB"
            "Q6_K"   = "7.4 GB"
            "Q8_0"   = "9.5 GB"
        }
    }
    "4B" = @{
        Name         = "Qwen3.5-4B"
        FullName     = "Qwen3.5-4B-Claude-4.6-Opus-Reasoning-Distilled"
        Repo         = "Jackrong/Qwen3.5-4B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-4B"
        Params       = "4B"
        MaxLayers    = 37
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K"   = "1.8 GB"
            "Q3_K_S" = "2.1 GB"
            "Q3_K_M" = "2.3 GB"
            "Q3_K_L" = "2.4 GB"
            "Q4_K_S" = "2.6 GB"
            "Q4_K_M" = "2.7 GB"
            "Q5_K_S" = "3.0 GB"
            "Q5_K_M" = "3.1 GB"
            "Q6_K"   = "3.5 GB"
            "Q8_0"   = "4.5 GB"
        }
    }
    "2B" = @{
        Name         = "Qwen3.5-2B"
        FullName     = "Qwen3.5-2B-Claude-4.6-Opus-Reasoning-Distilled"
        Repo         = "Jackrong/Qwen3.5-2B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-2B"
        Params       = "2B"
        MaxLayers    = 29
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K"   = "915 MB"
            "Q3_K_S" = "1.0 GB"
            "Q3_K_M" = "1.1 GB"
            "Q3_K_L" = "1.1 GB"
            "Q4_K_S" = "1.2 GB"
            "Q4_K_M" = "1.3 GB"
            "Q5_K_S" = "1.4 GB"
            "Q5_K_M" = "1.4 GB"
            "Q6_K"   = "1.6 GB"
            "Q8_0"   = "2.0 GB"
        }
    }
    "0.8B" = @{
        Name         = "Qwen3.5-0.8B"
        FullName     = "Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled"
        Repo         = "Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-0.8B"
        Params       = "0.8B"
        MaxLayers    = 25
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K"   = "396 MB"
            "Q3_K_S" = "435 MB"
            "Q3_K_M" = "465 MB"
            "Q3_K_L" = "477 MB"
            "Q4_K_S" = "503 MB"
            "Q4_K_M" = "527 MB"
            "Q5_K_S" = "564 MB"
            "Q5_K_M" = "585 MB"
            "Q6_K"   = "630 MB"
            "Q8_0"   = "812 MB"
        }
    }
}

# ── Size Parsing & Quant Recommendation ────────────────────────────────────────

function Parse-SizeToGB([string]$sizeStr) {
    if ($sizeStr -match '^([\d.]+)\s*GB$') { return [double]$Matches[1] }
    if ($sizeStr -match '^([\d.]+)\s*MB$') { return [double]$Matches[1] / 1024 }
    return $null
}

function Get-RecommendedQuant {
    param([string]$modelId, [double]$vramGB, [double]$ramGB)
    $catalog = $ModelCatalog[$modelId]
    if (-not $catalog) { return $null }

    $vramBudget = $vramGB + 2        # 1-2 layers can spill, still fast
    $totalBudget = $vramGB + $ramGB - 8  # reserve 8 GB for OS

    # Walk quants from highest quality (largest) to lowest
    $quantKeys = @($catalog.Quants.Keys)
    [array]::Reverse($quantKeys)

    $bestGpu = $null
    $bestPartial = $null
    foreach ($q in $quantKeys) {
        $sizeGB = Parse-SizeToGB $catalog.Quants[$q]
        if ($null -eq $sizeGB) { continue }
        if ($sizeGB -le $vramBudget -and -not $bestGpu) {
            $bestGpu = @{ Quant = $q; Size = $catalog.Quants[$q]; SizeGB = $sizeGB; Tier = 'gpu' }
        }
        if ($sizeGB -le $totalBudget -and -not $bestPartial) {
            $bestPartial = @{ Quant = $q; Size = $catalog.Quants[$q]; SizeGB = $sizeGB; Tier = 'partial' }
        }
    }

    if ($bestGpu) { return $bestGpu }
    if ($bestPartial) { return $bestPartial }
    return @{ Quant = $null; Size = $null; SizeGB = 0; Tier = 'none' }
}

function Get-QuantTier([double]$sizeGB, [double]$vramGB, [double]$totalBudget) {
    if ($sizeGB -le $vramGB)       { return 'gpu' }
    if ($sizeGB -le ($vramGB + 2)) { return 'near-gpu' }
    if ($sizeGB -le $totalBudget)  { return 'partial' }
    return 'toolarge'
}

# ── Default Profiles (overridden per-model by .shard/profiles.json) ────────────

$defaultProfiles = [ordered]@{
    "1" = @{
        Name = "Daily Default"
        Description = "Best overall for normal daily use"
        Context = 4096
        Ngl = 56
        Threads = 12
        FlashAttn = "on"
        Speed = "not calibrated"
    }
    "2" = @{
        Name = "Stability Fallback"
        Description = "Extra VRAM headroom when fit errors happen"
        Context = 4096
        Ngl = 48
        Threads = 12
        FlashAttn = "on"
        Speed = "not calibrated"
    }
    "3" = @{
        Name = "Long Context"
        Description = "Higher context history, lower speed"
        Context = 8192
        Ngl = 48
        Threads = 12
        FlashAttn = "on"
        Speed = "not calibrated"
    }
    "4" = @{
        Name = "XL Context"
        Description = "16K token context for extended reasoning"
        Context = 16384
        Ngl = 32
        Threads = 12
        FlashAttn = "on"
        Speed = "not calibrated"
    }
    "5" = @{
        Name = "XXL Context"
        Description = "32K token context for very long documents"
        Context = 32768
        Ngl = 20
        Threads = 12
        FlashAttn = "on"
        Speed = "not calibrated"
    }
}

# ── State Management ───────────────────────────────────────────────────────────

function Ensure-StateDir {
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir | Out-Null
    }
}

function Get-ServerState {
    if (-not (Test-Path $stateFile)) { return $null }
    try { return Get-Content -Raw -Path $stateFile | ConvertFrom-Json }
    catch { return $null }
}

function Set-ServerState($obj) {
    Ensure-StateDir
    ($obj | ConvertTo-Json -Depth 6) | Set-Content -Path $stateFile -Encoding UTF8
}

function Clear-ServerState {
    if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
}

function Get-RunningProcessFromState {
    $state = Get-ServerState
    if ($null -eq $state -or $null -eq $state.Pid) { return $null }
    $p = Get-Process -Id ([int]$state.Pid) -ErrorAction SilentlyContinue
    if ($null -eq $p) { Clear-ServerState; return $null }
    return $p
}

# ── Resolve Paths ──────────────────────────────────────────────────────────────

function Resolve-RuntimeExe {
    if ($env:SHARD_RUNTIME_EXE -and (Test-Path $env:SHARD_RUNTIME_EXE)) {
        return $env:SHARD_RUNTIME_EXE
    }
    $toolsDir = Join-Path $repoRoot "tools"
    if (-not (Test-Path $toolsDir)) { return $null }
    $serverExes = Get-ChildItem -Path $toolsDir -Recurse -File -Filter "llama-server.exe" -ErrorAction SilentlyContinue
    if ($null -eq $serverExes -or $serverExes.Count -eq 0) { return $null }
    $preferred = $serverExes |
        Sort-Object @{Expression = { if ($_.FullName -match "cuda") { 0 } else { 1 } }}, @{Expression = { $_.LastWriteTime }; Descending = $true } |
        Select-Object -First 1
    return $preferred.FullName
}

function Resolve-CompletionExe {
    param([string]$runtimeExe)
    if (-not $runtimeExe) { return $null }
    $dir = Split-Path -Parent $runtimeExe
    $candidate = Join-Path $dir "llama-completion.exe"
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Resolve-BenchExe {
    param([string]$runtimeExe)
    if (-not $runtimeExe) { return $null }
    $dir = Split-Path -Parent $runtimeExe
    $candidate = Join-Path $dir "llama-bench.exe"
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Resolve-ModelPath {
    param([string]$modelId)

    if ($env:SHARD_MODEL_PATH -and (Test-Path $env:SHARD_MODEL_PATH)) {
        return $env:SHARD_MODEL_PATH
    }
    $modelsDir = Join-Path $repoRoot "models"
    if (-not (Test-Path $modelsDir)) { return $null }

    if (-not $modelId) { $modelId = Get-ActiveModelId }
    $catalog = $ModelCatalog[$modelId]
    if (-not $catalog) { return $null }

    $prefix = [regex]::Escape($catalog.FilePrefix)
    $fullPrefix = [regex]::Escape($catalog.FullName)

    # Match both short (Qwen3.5-27B.Q4_K_M.gguf) and long naming
    $ggufs = @(Get-ChildItem -Path $modelsDir -File -Filter "*.gguf" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^($prefix|$fullPrefix)\." } |
        Sort-Object Length -Descending)

    if ($ggufs.Count -gt 0) { return $ggufs[0].FullName }
    return $null
}

# ── Model Scanning ─────────────────────────────────────────────────────────────

function Get-InstalledModels {
    $modelsDir = Join-Path $repoRoot "models"
    if (-not (Test-Path $modelsDir)) { return @() }

    $ggufs = @(Get-ChildItem -Path $modelsDir -File -Filter "*.gguf" -ErrorAction SilentlyContinue)
    $installed = @()

    foreach ($modelId in $ModelCatalog.Keys) {
        $catalog = $ModelCatalog[$modelId]
        $prefix = [regex]::Escape($catalog.FilePrefix)
        $fullPrefix = [regex]::Escape($catalog.FullName)

        $matchingFiles = @($ggufs | Where-Object {
            $_.Name -match "^($prefix|$fullPrefix)\."
        })

        foreach ($f in $matchingFiles) {
            $quant = "unknown"
            if ($f.Name -match '[\.\-](Q[0-9][A-Za-z0-9_]*)\.gguf$') {
                $quant = $Matches[1]
            }
            $installed += [pscustomobject]@{
                ModelId = $modelId
                Quant   = $quant
                File    = $f.Name
                Path    = $f.FullName
                SizeMB  = [Math]::Round($f.Length / 1MB, 0)
            }
        }
    }

    return $installed
}

function Get-InstalledModelIds {
    $installed = Get-InstalledModels
    return @($installed | Select-Object -ExpandProperty ModelId -Unique)
}

# ── Profile Management ─────────────────────────────────────────────────────────

function Get-ActiveModelId {
    if (-not (Test-Path $profileOverrideFile)) { return "27B" }
    try {
        $data = Get-Content -Raw -Path $profileOverrideFile | ConvertFrom-Json -AsHashtable
        if ($data.Contains("activeModel")) { return $data["activeModel"] }
        return "27B"
    } catch { return "27B" }
}

function Set-ActiveModelId([string]$modelId) {
    $allData = Load-AllProfileData
    $allData["activeModel"] = $modelId
    Save-AllProfileData $allData
}

function Load-AllProfileData {
    if (-not (Test-Path $profileOverrideFile)) {
        return @{ "activeModel" = "27B"; "models" = @{} }
    }
    try {
        $data = Get-Content -Raw -Path $profileOverrideFile | ConvertFrom-Json -AsHashtable
        # Migrate legacy format (flat profile keys without "activeModel")
        if (-not $data.Contains("activeModel")) {
            $legacyProfiles = @{}
            foreach ($k in $data.Keys) { $legacyProfiles[$k] = $data[$k] }
            $migrated = @{
                "activeModel" = "27B"
                "models" = @{ "27B" = $legacyProfiles }
            }
            # Persist the migrated format
            Save-AllProfileData $migrated
            return $migrated
        }
        if (-not $data.Contains("models")) { $data["models"] = @{} }
        return $data
    } catch {
        return @{ "activeModel" = "27B"; "models" = @{} }
    }
}

function Save-AllProfileData($allData) {
    Ensure-StateDir
    ($allData | ConvertTo-Json -Depth 8) | Set-Content -Path $profileOverrideFile -Encoding UTF8
}

function Load-Profiles {
    param([string]$modelId)

    if (-not $modelId) { $modelId = Get-ActiveModelId }

    $profiles = [ordered]@{}
    foreach ($id in $defaultProfiles.Keys) {
        $profiles[$id] = @{
            Name        = $defaultProfiles[$id].Name
            Description = $defaultProfiles[$id].Description
            Context     = [int]$defaultProfiles[$id].Context
            Ngl         = [int]$defaultProfiles[$id].Ngl
            Threads     = [int]$defaultProfiles[$id].Threads
            FlashAttn   = $defaultProfiles[$id].FlashAttn
            Speed       = $defaultProfiles[$id].Speed
        }
    }

    $allData = Load-AllProfileData
    if ($allData["models"] -and $allData["models"].Contains($modelId)) {
        $override = $allData["models"][$modelId]
        foreach ($id in $override.Keys) {
            if (-not $profiles.Contains($id)) { continue }
            foreach ($k in $override[$id].Keys) {
                $profiles[$id][$k] = $override[$id][$k]
            }
            $profiles[$id].Context = [int]$profiles[$id].Context
            $profiles[$id].Ngl     = [int]$profiles[$id].Ngl
            $profiles[$id].Threads = [int]$profiles[$id].Threads
        }
    }

    return $profiles
}

function Save-Profiles {
    param($profilesToSave, [string]$modelId)

    if (-not $modelId) { $modelId = Get-ActiveModelId }

    $allData = Load-AllProfileData
    if (-not $allData["models"]) { $allData["models"] = @{} }
    $allData["models"][$modelId] = $profilesToSave
    Save-AllProfileData $allData
}

function Model-HasTunedProfiles([string]$modelId) {
    $allData = Load-AllProfileData
    return ($allData["models"] -and $allData["models"].Contains($modelId))
}

# ── Server Management ──────────────────────────────────────────────────────────

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
    $activeModelId = Get-ActiveModelId
    $runtimeExe = Resolve-RuntimeExe
    $modelPath = Resolve-ModelPath -modelId $activeModelId

    if (-not $runtimeExe -or -not (Test-Path $runtimeExe)) {
        throw "llama-server not found. Run .\\scripts\\install-shard.ps1 to bootstrap runtime assets."
    }
    if (-not $modelPath -or -not (Test-Path $modelPath)) {
        throw "GGUF model not found for $activeModelId. Run 'shard download $activeModelId' or .\\scripts\\install-shard.ps1"
    }
    if (-not $profiles.Contains($profileId)) {
        throw "invalid profile id: $profileId"
    }

    $profile = $profiles[$profileId]
    $running = Get-RunningProcessFromState

    if ($null -ne $running) {
        $state = Get-ServerState
        if ($state.ProfileId -eq $profileId -and $state.ModelId -eq $activeModelId) {
            Write-Host "shard: already running $activeModelId profile $profileId ($($profile.Name)) on http://127.0.0.1:8080"
            Write-Host "shard: PID $($running.Id)"
            return
        }
        Write-Host "shard: switching to $activeModelId profile $profileId"
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
        ModelId = $activeModelId
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

    $modelName = $ModelCatalog[$activeModelId].Name
    Write-Host "shard: started $modelName profile $profileId ($($profile.Name))"
    Write-Host "shard: endpoint http://127.0.0.1:8080"
    Write-Host "shard: PID $($proc.Id)"
    Write-Host "shard: logs"
    Write-Host "  stdout: $stdoutLog"
    Write-Host "  stderr: $stderrLog"

    # Auto-update OpenCode config if it exists
    $ocConfig = Join-Path $env:USERPROFILE ".config\opencode\opencode.jsonc"
    if (Test-Path $ocConfig) {
        $ctxK = [int]($profile.Context / 1024)
        Update-OpenCodeConfig -Silent -profileId $profileId
        Write-Host "shard: updated OpenCode config (${ctxK}K context)"
    }
}

# ── Display Functions ──────────────────────────────────────────────────────────

function Show-Profiles {
    $activeModelId = Get-ActiveModelId
    $catalog = $ModelCatalog[$activeModelId]
    $installed = Get-InstalledModels
    $activeFiles = @($installed | Where-Object { $_.ModelId -eq $activeModelId })
    $activeQuant = if ($activeFiles.Count -gt 0) { $activeFiles[0].Quant } else { "?" }

    Write-Host ''
    Write-Host '  SHARD PROFILES'
    Write-Host '  =============='
    Write-Host ''
    Write-Host ("  Active Model: {0} ({1})" -f $catalog.Name, $activeQuant)
    Write-Host ''
    Write-Host '   #   Profile              Context   ngl  Threads  Speed'
    Write-Host '  ───  ───────────────────  ────────  ───  ───────  ──────────────'

    $running = Get-RunningProcessFromState
    $runningState = $null
    if ($null -ne $running) { $runningState = Get-ServerState }

    foreach ($id in $profiles.Keys) {
        $p = $profiles[$id]
        $ctxK = [int]($p.Context / 1024)
        $marker = ''
        if ($null -ne $runningState -and $runningState.ProfileId -eq $id -and
            ($null -eq $runningState.ModelId -or $runningState.ModelId -eq $activeModelId)) {
            $marker = ' *'
        }
        $name = $p.Name.PadRight(19)
        $ctxStr = "${ctxK}K".PadRight(8)
        $nglStr = "$($p.Ngl)".PadLeft(3)
        $thrStr = "$($p.Threads)".PadLeft(5)
        Write-Host ("  [{0}]  {1}  {2}  {3}  {4}   {5}{6}" -f $id, $name, $ctxStr, $nglStr, $thrStr, $p.Speed, $marker)
    }

    if ($null -ne $runningState) {
        Write-Host ''
        Write-Host ("  * = running (PID {0})" -f $running.Id)
    }

    Write-Host ''
    Write-Host '  Installed Models:'

    $installedIds = @($installed | Select-Object -ExpandProperty ModelId -Unique)
    foreach ($mid in $ModelCatalog.Keys) {
        $mc = $ModelCatalog[$mid]
        $files = @($installed | Where-Object { $_.ModelId -eq $mid })
        $isActive = ($mid -eq $activeModelId)
        $arrow = if ($isActive) { '>' } else { ' ' }

        if ($files.Count -gt 0) {
            $quants = (($files | ForEach-Object { $_.Quant } | Select-Object -Unique) -join ', ')
            $sizeMB = ($files | Measure-Object -Property SizeMB -Sum).Sum
            $sizeStr = if ($sizeMB -ge 1024) { "{0:N1} GB" -f ($sizeMB / 1024) } else { "${sizeMB} MB" }
            $tunedStr = if (Model-HasTunedProfiles $mid) { '[tuned]' } else { '[default]' }
            $activeStr = if ($isActive) { ' <-- active' } else { '' }
            Write-Host ("    {0} {1}  {2}  {3}  {4}{5}" -f $arrow, $mid.PadRight(5), $quants.PadRight(14), $sizeStr.PadRight(9), $tunedStr, $activeStr)
        } else {
            $defQuant = $mc.DefaultQuant
            $defSize = $mc.Quants[$defQuant]
            Write-Host ("    {0} {1}  --  not downloaded  (default: {2} {3})" -f $arrow, $mid.PadRight(5), $defQuant, $defSize)
        }
    }

    Write-Host ''
    Write-Host "  'shard model <id>'  switch active model    'shard download'  get more models"
    Write-Host ''
}

function Show-Status {
    $running = Get-RunningProcessFromState
    if ($null -eq $running) {
        Write-Host "shard: server is not running"
        return
    }

    $state = Get-ServerState
    $modelId = if ($state.ModelId) { $state.ModelId } else { Get-ActiveModelId }
    $modelName = if ($ModelCatalog.Contains($modelId)) { $ModelCatalog[$modelId].Name } else { $modelId }
    $currentProfiles = Load-Profiles -modelId $modelId
    $profile = $currentProfiles[$state.ProfileId]

    Write-Host ("shard: running {0} profile {1} ({2})" -f $modelName, $state.ProfileId, $state.ProfileName)
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
    $activeModelId = Get-ActiveModelId
    $modelPath = Resolve-ModelPath -modelId $activeModelId

    Write-Host "shard: resolved paths"
    Write-Host ("  runtime: {0}" -f ($(if ($runtimeExe) { $runtimeExe } else { "<not found>" })))
    Write-Host ("  model:   {0}" -f ($(if ($modelPath) { $modelPath } else { "<not found>" })))
    Write-Host ("  active:  {0}" -f $activeModelId)

    if ($env:SHARD_RUNTIME_EXE) {
        Write-Host ("  SHARD_RUNTIME_EXE override: {0}" -f $env:SHARD_RUNTIME_EXE)
    }
    if ($env:SHARD_MODEL_PATH) {
        Write-Host ("  SHARD_MODEL_PATH override:   {0}" -f $env:SHARD_MODEL_PATH)
    }

    Write-Host ""
    Write-Host "  Installed models:"
    $installed = Get-InstalledModels
    foreach ($m in $installed) {
        $sizeStr = if ($m.SizeMB -ge 1024) { "{0:N1} GB" -f ($m.SizeMB / 1024) } else { "$($m.SizeMB) MB" }
        Write-Host ("    {0}  {1}  {2}  {3}" -f $m.ModelId.PadRight(5), $m.Quant.PadRight(8), $sizeStr.PadRight(9), $m.File)
    }
}

function Show-Usage {
    Write-Host "usage:"
    Write-Host "  shard              start active model with profile 1"
    Write-Host "  shard 1..5         start/switch to a specific profile"
    Write-Host "  shard stop         stop running server"
    Write-Host "  shard ls           list profiles and installed models"
    Write-Host "  shard status       show running status"
    Write-Host "  shard info         show resolved runtime/model paths"
    Write-Host ""
    Write-Host "  shard model        show active model"
    Write-Host "  shard model <id>   switch active model (e.g. shard model 9B)"
    Write-Host "  shard download     interactive model download"
    Write-Host "  shard download <id> [quant]   download a specific model"
    Write-Host "  shard check        check HuggingFace for new/updated models"
    Write-Host ""
    Write-Host "  shard detect       show detected system specs"
    Write-Host "  shard recalc       benchmark active model and auto-tune profiles"
    Write-Host "  shard recalc all   benchmark all installed models"
    Write-Host "  shard recalc <id>  benchmark a specific model (e.g. shard recalc 9B)"
    Write-Host "  shard reset        remove profile overrides and return to defaults"
    Write-Host "  shard update       update llama.cpp runtime to latest"
    Write-Host "  shard opencode     setup/update OpenCode config for local shard"
    Write-Host "  shard help         show this message"
}

# ── Hardware Detection ─────────────────────────────────────────────────────────

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

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) { $specs.TotalRAM_GB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1) }
    } catch {}

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu) { $specs.CPUName = $cpu.Name.Trim() }
    } catch {}

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
    Write-Host "  Run 'shard recalc' to generate optimized profiles for this machine."
}

# ── Benchmarking ───────────────────────────────────────────────────────────────

function Parse-BenchTg64 {
    param([string]$text)

    $results = @()
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -notmatch "\|" -or $line -notmatch "tg64") { continue }

        $parts = $line.Split('|') | ForEach-Object { $_.Trim() }
        if ($parts.Count -lt 8) { continue }

        $tgIdx = -1
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -match '^tg\d+$') { $tgIdx = $i; break }
        }
        if ($tgIdx -lt 0 -or ($tgIdx + 1) -ge $parts.Count) { continue }

        $nglText = $parts[5]
        $tsText = $parts[$tgIdx + 1]

        $nglMatch = [regex]::Match($nglText, "\d+")
        $tsMatch = [regex]::Match($tsText, "[0-9]+(\.[0-9]+)?")
        if (-not $nglMatch.Success -or -not $tsMatch.Success) { continue }

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
        [int]$candidateTotal = 0,
        [int]$vramMarginMiB = 512
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
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()

    $allStderr = [System.Text.StringBuilder]::new()
    $overflowWarning = $false
    $freeVramMiB = -1
    while ($null -ne ($sline = $proc.StandardError.ReadLine())) {
        [void]$allStderr.AppendLine($sline)

        if ($sline -match 'failed to fit params|CUDA out of memory|out of memory') {
            $overflowWarning = $true
        }
        elseif ($sline -match 'offloading (\d+).*layers') {
            $layerCount = $Matches[1]
            Write-Host "    Offloading $layerCount layers to GPU..."
        }
        elseif ($sline -match 'common_perf_print:\s+load time\s*=\s*([0-9.]+)') {
            $loadS = [Math]::Round([double]$Matches[1] / 1000, 1)
            Write-Host "    Model loaded (${loadS}s), generating 64 tokens..."
        }
        elseif ($sline -match '(?<!prompt )eval time\s*=.*?([0-9.]+)\s*tokens per second') {
            $tokSpeed = $Matches[1]
            Write-Host "    Speed: $tokSpeed tok/s"
        }
        elseif ($sline -match 'llama_memory_breakdown.*CUDA.*\|\s*(\d+)\s*=\s*(\d+)\s*\+') {
            $totalV = $Matches[1]; $freeV = $Matches[2]
            $freeVramMiB = [int]$freeV
            $usedV = [int]$totalV - [int]$freeV
            Write-Host "    VRAM: ${usedV} / ${totalV} MiB used (${freeV} MiB free)"
        }
    }

    [void]$stdoutTask.Result
    $proc.WaitForExit()

    $elapsed = $sw.Elapsed.TotalSeconds
    $elRound = [Math]::Round($elapsed, 1)
    $out = $allStderr.ToString()

    if ($proc.ExitCode -ne 0) {
        if ($overflowWarning) {
            Write-Host "    VRAM overflow - model does not fit at this ngl (${elRound}s)"
        } else {
            Write-Host "    Failed with exit code $($proc.ExitCode) (${elRound}s)"
        }
        Write-Host ''
        return $null
    }

    if ($freeVramMiB -ge 0 -and $freeVramMiB -lt $vramMarginMiB) {
        Write-Host "    Rejected: only ${freeVramMiB} MiB free (need ${vramMarginMiB} MiB margin for stability)"
        Write-Host ''
        return $null
    }

    $m = [regex]::Matches($out, '(?<!prompt )eval time\s*=.*?,\s*([0-9]+(\.[0-9]+)?)\s*tokens per second')
    if ($m.Count -eq 0) {
        Write-Host "    No speed data captured (${elRound}s)"
        Write-Host ''
        return $null
    }

    $tps = [double]$m[$m.Count - 1].Groups[1].Value
    Write-Host "    Done in ${elRound}s"
    Write-Host ''
    return $tps
}

function Get-NglCandidates([int]$maxLayers) {
    $candidates = @()
    if ($maxLayers -le 30) {
        for ($n = 4; $n -lt $maxLayers; $n += 4) { $candidates += $n }
    } elseif ($maxLayers -le 50) {
        for ($n = 4; $n -lt $maxLayers; $n += 4) { $candidates += $n }
    } else {
        $candidates = @(8, 12, 16, 20, 24, 32, 40, 44, 48, 56, 64)
        $candidates = @($candidates | Where-Object { $_ -lt $maxLayers })
    }
    if ($candidates.Count -eq 0 -or $candidates[-1] -ne $maxLayers) {
        $candidates += $maxLayers
    }
    return $candidates
}

function Recalculate-ModelProfiles {
    param(
        [string]$modelId,
        [string]$runtimeExe,
        [string]$benchExe,
        [string]$completionExe
    )

    $modelPath = Resolve-ModelPath -modelId $modelId
    if (-not $modelPath -or -not (Test-Path $modelPath)) {
        Write-Host "shard: model $modelId not downloaded, skipping"
        return
    }

    $catalog = $ModelCatalog[$modelId]
    $maxNgl = $catalog.MaxLayers
    $modelProfiles = Load-Profiles -modelId $modelId

    $totalSw = [System.Diagnostics.Stopwatch]::StartNew()
    $threads = [Math]::Max(4, [Math]::Min(16, [int][Math]::Floor([Environment]::ProcessorCount / 2)))

    Write-Host ''
    Write-Host '=========================================='
    Write-Host "  RECALC - $($catalog.Name) ($modelId)"
    Write-Host '=========================================='
    Write-Host ("  Model:   {0}" -f (Split-Path $modelPath -Leaf))
    Write-Host ("  Layers:  {0}" -f $maxNgl)
    Write-Host ("  Threads: {0}" -f $threads)
    Write-Host ("  Runtime: {0}" -f (Split-Path $runtimeExe -Leaf))
    Write-Host ''

    # Detect VRAM and compute adaptive candidate lists
    $specs = Detect-SystemSpecs
    $vramGB = $specs.VRAM_GB
    $allNgl = Get-NglCandidates -maxLayers $maxNgl

    if ($vramGB) {
        Write-Host ("  Detected VRAM: {0} GB" -f $vramGB)
        # Estimate per-layer cost based on model size
        $perLayerMiB = switch ($modelId) {
            "27B"  { 220 }
            "9B"   { 120 }
            "4B"   { 65 }
            "2B"   { 40 }
            "0.8B" { 20 }
            default { 100 }
        }
        $baseMiB = switch ($modelId) {
            "27B"  { 2048 }
            "9B"   { 800 }
            "4B"   { 400 }
            "2B"   { 200 }
            "0.8B" { 100 }
            default { 500 }
        }
        $availMiB = ($vramGB * 1024) - $baseMiB - 512
        $minUsefulNgl = [int][Math]::Max(4, [Math]::Floor($availMiB / $perLayerMiB * 0.3))
        $candidates4096 = @($allNgl | Where-Object { $_ -ge $minUsefulNgl })
        if ($candidates4096.Count -eq 0) { $candidates4096 = $allNgl }
        if ($minUsefulNgl -gt 4) {
            Write-Host ("  Skipping ngl below {0} (too slow for {1} GB VRAM)" -f $minUsefulNgl, $vramGB)
        }
    } else {
        $candidates4096 = $allNgl
    }
    $candidateArg = ($candidates4096 -join ",")
    $phaseCount = 4
    $currentPhase = 1

    Write-Host ''
    Write-Host "[$currentPhase/$phaseCount] SPEED TEST at 4K context"
    Write-Host "  Candidates: ngl $candidateArg"
    Write-Host '  Running llama-bench...'
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
    $benchStderrTask = $benchProc.StandardError.ReadToEndAsync()

    $benchStdout = [System.Text.StringBuilder]::new()
    $benchTgCount = 0
    $benchTotal = $candidates4096.Count

    while ($null -ne ($bline = $benchProc.StandardOutput.ReadLine())) {
        [void]$benchStdout.AppendLine($bline)

        if ($bline -match '\|' -and $bline -match 'tg64') {
            $benchTgCount++
            $bparts = $bline.Split('|') | ForEach-Object { $_.Trim() }
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
    $benchOut = $benchStdout.ToString() + "`n" + $benchStderrContent
    $benchRows = Parse-BenchTg64 -text $benchOut

    if ($benchRows.Count -eq 0) {
        Write-Host "  WARNING: could not parse benchmark output, keeping defaults for $modelId"
        return
    }

    $phaseElapsed = [Math]::Round($phaseSw.Elapsed.TotalSeconds, 0)
    Write-Host "  Completed in ${phaseElapsed}s"

    $best4096 = $benchRows | Sort-Object TokensPerSecond -Descending | Select-Object -First 1

    $fallback4096 = $benchRows |
        Where-Object { $_.Ngl -lt $best4096.Ngl } |
        Sort-Object TokensPerSecond -Descending |
        Select-Object -First 1

    if ($null -eq $fallback4096) { $fallback4096 = $best4096 }

    $b4ngl = $best4096.Ngl; $b4spd = [Math]::Round($best4096.TokensPerSecond, 2)
    $f4ngl = $fallback4096.Ngl; $f4spd = [Math]::Round($fallback4096.TokensPerSecond, 2)
    Write-Host "  Best: ngl $b4ngl at $b4spd tok/s, Fallback: ngl $f4ngl at $f4spd tok/s"
    Write-Host ""

    # -- Phase 2: 8K context --
    $currentPhase = 2
    $maxProvenNgl = $best4096.Ngl
    $candidates8192 = @($allNgl | Where-Object { $_ -le $maxProvenNgl } | Sort-Object -Descending)
    if ($candidates8192.Count -eq 0) { $candidates8192 = @(4) }
    $results8192 = @()

    $ccount = $candidates8192.Count; $clist = $candidates8192 -join ', '
    Write-Host "[$currentPhase/$phaseCount] VRAM FIT TEST at 8K context"
    Write-Host "  Candidates: ngl $clist"
    $cIdx = 0
    foreach ($ngl in $candidates8192) {
        $cIdx++
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 8192 -threads $threads -candidateNum $cIdx -candidateTotal $ccount
        if ($null -ne $speed) {
            $results8192 += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
            break
        }
    }

    if ($results8192.Count -gt 0) {
        $best8192 = $results8192 | Sort-Object TokensPerSecond -Descending | Select-Object -First 1
        Write-Host ("  Best 8K: ngl {0} at {1} tok/s" -f $best8192.Ngl, [Math]::Round($best8192.TokensPerSecond, 2))
    } else {
        Write-Host '  All 8K candidates failed - keeping defaults'
    }
    Write-Host ""

    # -- Phase 3: 16K context --
    $currentPhase = 3
    $anchor16k = if ($results8192.Count -gt 0) { $best8192.Ngl } else { $maxProvenNgl }
    $candidates16k = @($allNgl | Where-Object { $_ -le $anchor16k } | Sort-Object -Descending)
    if ($candidates16k.Count -eq 0) { $candidates16k = @(4) }
    $results16k = @()

    $ccount = $candidates16k.Count; $clist = $candidates16k -join ', '
    Write-Host "[$currentPhase/$phaseCount] VRAM FIT TEST at 16K context"
    Write-Host "  Candidates: ngl $clist"
    $cIdx = 0
    foreach ($ngl in $candidates16k) {
        $cIdx++
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 16384 -threads $threads -candidateNum $cIdx -candidateTotal $ccount
        if ($null -ne $speed) {
            $results16k += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
            break
        }
    }

    if ($results16k.Count -gt 0) {
        $best16k = $results16k | Sort-Object TokensPerSecond -Descending | Select-Object -First 1
        Write-Host ("  Best 16K: ngl {0} at {1} tok/s" -f $best16k.Ngl, [Math]::Round($best16k.TokensPerSecond, 2))
    } else {
        Write-Host '  All 16K candidates failed - keeping defaults'
    }
    Write-Host ""

    # -- Phase 4: 32K context --
    $currentPhase = 4
    $anchor32k = if ($results16k.Count -gt 0) { $best16k.Ngl } else { $anchor16k }
    $candidates32k = @($allNgl | Where-Object { $_ -le $anchor32k } | Sort-Object -Descending)
    if ($candidates32k.Count -eq 0) { $candidates32k = @(4) }
    $results32k = @()

    $ccount = $candidates32k.Count; $clist = $candidates32k -join ', '
    Write-Host "[$currentPhase/$phaseCount] VRAM FIT TEST at 32K context"
    Write-Host "  Candidates: ngl $clist"
    $cIdx = 0
    foreach ($ngl in $candidates32k) {
        $cIdx++
        $speed = Measure-ContextCandidate -completionExe $completionExe -modelPath $modelPath -ngl $ngl -context 32768 -threads $threads -candidateNum $cIdx -candidateTotal $ccount
        if ($null -ne $speed) {
            $results32k += [pscustomobject]@{ Ngl = $ngl; TokensPerSecond = $speed }
            break
        }
    }

    if ($results32k.Count -gt 0) {
        $best32k = $results32k | Sort-Object TokensPerSecond -Descending | Select-Object -First 1
        Write-Host ("  Best 32K: ngl {0} at {1} tok/s" -f $best32k.Ngl, [Math]::Round($best32k.TokensPerSecond, 2))
    } else {
        Write-Host '  All 32K candidates failed - keeping defaults'
    }
    Write-Host ""

    # -- Apply results --
    $modelProfiles["1"].Ngl = [int]$best4096.Ngl
    $modelProfiles["1"].Context = 4096
    $modelProfiles["1"].Threads = $threads
    $modelProfiles["1"].Speed = "{0} tok/s" -f ([Math]::Round($best4096.TokensPerSecond, 2))

    $modelProfiles["2"].Ngl = [int]$fallback4096.Ngl
    $modelProfiles["2"].Context = 4096
    $modelProfiles["2"].Threads = $threads
    $modelProfiles["2"].Speed = "{0} tok/s" -f ([Math]::Round($fallback4096.TokensPerSecond, 2))

    if ($results8192.Count -gt 0) {
        $modelProfiles["3"].Ngl = [int]$best8192.Ngl
        $modelProfiles["3"].Context = 8192
        $modelProfiles["3"].Threads = $threads
        $modelProfiles["3"].Speed = "{0} tok/s" -f ([Math]::Round($best8192.TokensPerSecond, 2))
    }
    if ($results16k.Count -gt 0) {
        $modelProfiles["4"].Ngl = [int]$best16k.Ngl
        $modelProfiles["4"].Context = 16384
        $modelProfiles["4"].Threads = $threads
        $modelProfiles["4"].Speed = "{0} tok/s" -f ([Math]::Round($best16k.TokensPerSecond, 2))
    }
    if ($results32k.Count -gt 0) {
        $modelProfiles["5"].Ngl = [int]$best32k.Ngl
        $modelProfiles["5"].Context = 32768
        $modelProfiles["5"].Threads = $threads
        $modelProfiles["5"].Speed = "{0} tok/s" -f ([Math]::Round($best32k.TokensPerSecond, 2))
    }

    Save-Profiles -profilesToSave $modelProfiles -modelId $modelId

    $totalElapsed = $totalSw.Elapsed
    $totalMin = [int][Math]::Floor($totalElapsed.TotalMinutes)
    $totalSec = $totalElapsed.Seconds
    Write-Host '=========================================='
    Write-Host "  RECALC COMPLETE - $($catalog.Name)"
    Write-Host "  Total time: ${totalMin}m ${totalSec}s"
    Write-Host '=========================================='
    Write-Host ''
    Write-Host '  Profile          Context   ngl   Speed'
    Write-Host '  ---------------  -------  ----  ----------------'
    for ($i = 1; $i -le 5; $i++) {
        $p = $modelProfiles["$i"]
        $pName = $p.Name.PadRight(15)
        $ctxK = [int]($p.Context / 1024)
        $ctxStr = "${ctxK}K".PadRight(7)
        $pNgl = "$($p.Ngl)".PadLeft(4)
        Write-Host "  $pName  $ctxStr  $pNgl  $($p.Speed)"
    }
    Write-Host ""
    Write-Host "  Saved to: $profileOverrideFile"

    # Auto-update OpenCode config if it exists
    $ocConfig = Join-Path $env:USERPROFILE ".config\opencode\opencode.jsonc"
    if (Test-Path $ocConfig) {
        Update-OpenCodeConfig -Silent
        Write-Host "  Updated OpenCode config: $ocConfig"
    }
}

function Recalculate-Profiles {
    param([string[]]$modelIds)

    $runtimeExe = Resolve-RuntimeExe
    $benchExe = Resolve-BenchExe -runtimeExe $runtimeExe
    $completionExe = Resolve-CompletionExe -runtimeExe $runtimeExe

    if (-not $runtimeExe -or -not (Test-Path $runtimeExe)) {
        throw "llama-server not found. Install runtime first with .\\scripts\\install-shard.ps1"
    }
    if (-not $benchExe -or -not (Test-Path $benchExe)) {
        throw "llama-bench.exe not found next to runtime"
    }
    if (-not $completionExe -or -not (Test-Path $completionExe)) {
        throw "llama-completion.exe not found next to runtime"
    }

    # Determine targets
    $installedIds = Get-InstalledModelIds
    $targets = @()

    if ($null -eq $modelIds -or $modelIds.Count -eq 0) {
        $targets = @(Get-ActiveModelId)
    }
    elseif ($modelIds.Count -eq 1 -and $modelIds[0].ToLowerInvariant() -eq "all") {
        $targets = $installedIds
    }
    else {
        foreach ($id in $modelIds) {
            $upper = $id.ToUpperInvariant()
            # Accept lowercase like "27b" → "27B", "0.8b" → "0.8B"
            $matched = $ModelCatalog.Keys | Where-Object { $_.ToUpperInvariant() -eq $upper }
            if ($matched) {
                $targets += @($matched)[0]
            } else {
                Write-Host "shard: unknown model '$id' - skipping"
            }
        }
    }

    if ($targets.Count -eq 0) {
        throw "no models to recalculate. Install a model first with 'shard download'"
    }

    $notInstalled = @($targets | Where-Object { $_ -notin $installedIds })
    if ($notInstalled.Count -gt 0) {
        Write-Host ("shard: models not downloaded (will skip): {0}" -f ($notInstalled -join ', '))
        $targets = @($targets | Where-Object { $_ -in $installedIds })
    }

    if ($targets.Count -eq 0) {
        throw "none of the specified models are downloaded"
    }

    # Stop server if running
    $resumeProfileId = $null
    $resumeModelId = $null
    $alreadyRunning = Get-RunningProcessFromState
    if ($null -ne $alreadyRunning) {
        $runningState = Get-ServerState
        $resumeProfileId = $runningState.ProfileId
        $resumeModelId = if ($runningState.ModelId) { $runningState.ModelId } else { Get-ActiveModelId }
        Write-Host ("shard: stopping running server (profile {0}) before calibration" -f $resumeProfileId)
        Stop-Shard
        Start-Sleep -Seconds 1
    }

    # Kill any lingering llama processes before benchmarking
    $staleProcs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '^llama-(bench|completion|cli|server)$'
    })
    if ($staleProcs.Count -gt 0) {
        Write-Host ("  Killing {0} lingering llama process(es)..." -f $staleProcs.Count)
        $staleProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    Write-Host ''
    Write-Host ("  Recalculating {0} model(s): {1}" -f $targets.Count, ($targets -join ', '))
    Write-Host ''

    foreach ($targetId in $targets) {
        Recalculate-ModelProfiles -modelId $targetId -runtimeExe $runtimeExe -benchExe $benchExe -completionExe $completionExe
    }

    if ($resumeProfileId -and $resumeModelId) {
        # Reload profiles for the model that was running
        $script:profiles = Load-Profiles -modelId $resumeModelId
        Write-Host ("shard: restarting previously running profile {0}" -f $resumeProfileId)
        Start-Shard -profileId $resumeProfileId
    }
}

# ── OpenCode Integration ───────────────────────────────────────────────────────

function Update-OpenCodeConfig {
    param([switch]$Silent, [string]$profileId)

    $activeModelId = Get-ActiveModelId
    $catalog = $ModelCatalog[$activeModelId]
    if (-not $catalog) {
        if (-not $Silent) { Write-Host "shard: no active model found" }
        return $false
    }

    $modelProfiles = Load-Profiles -modelId $activeModelId
    if (-not $profileId) { $profileId = "1" }
    $selectedProfile = $modelProfiles[$profileId]
    if (-not $selectedProfile) { $selectedProfile = $modelProfiles["1"] }
    $contextLimit = [int]$selectedProfile.Context
    $speed = $selectedProfile.Speed

    # Model key for the OpenCode config (sent as model id to llama-server, which ignores it)
    $modelKey = ($catalog.Name).ToLower() -replace '\s+', '-'
    $displayName = "$($catalog.FullName) (local)"
    if ($speed -and $speed -ne "not calibrated") {
        $ctxK = [int]($contextLimit / 1024)
        $displayName += " - ${ctxK}K ctx, $speed"
    }

    $configDir = Join-Path $env:USERPROFILE ".config\opencode"
    $configFile = Join-Path $configDir "opencode.jsonc"

    # Load existing config or start fresh
    $config = $null
    if (Test-Path $configFile) {
        try {
            $raw = Get-Content -Raw -Path $configFile
            # Strip single-line // comments for parsing
            $stripped = ($raw -split "`r?`n" | ForEach-Object { $_ -replace '^\s*//.*$', '' -replace '\s//\s.*$', '' }) -join "`n"
            $config = $stripped | ConvertFrom-Json -AsHashtable
        } catch {
            if (-not $Silent) {
                Write-Host "  Warning: could not parse existing opencode.jsonc, creating backup"
            }
            Copy-Item $configFile "$configFile.bak" -Force
            $config = $null
        }
    }

    if (-not $config) {
        $config = [ordered]@{
            '$schema' = "https://opencode.ai/config.json"
        }
    }

    if (-not $config.Contains("provider")) {
        $config["provider"] = @{}
    }

    $config["provider"]["shard"] = [ordered]@{
        npm     = "@ai-sdk/openai-compatible"
        name    = "Shard (local)"
        options = [ordered]@{
            baseURL = "http://127.0.0.1:8080/v1"
        }
        models = [ordered]@{
            $modelKey = [ordered]@{
                name  = $displayName
                limit = [ordered]@{
                    context = $contextLimit
                    output  = $contextLimit
                }
            }
        }
    }

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $json = $config | ConvertTo-Json -Depth 8
    Set-Content -Path $configFile -Value $json -Encoding UTF8

    if (-not $Silent) {
        Write-Host "  Updated: $configFile"
        Write-Host "  Provider: shard (local llama-server on http://127.0.0.1:8080)"
        Write-Host "  Model: $($catalog.Name) - context: $contextLimit, output: $contextLimit"
        if ($speed -and $speed -ne "not calibrated") {
            Write-Host "  Speed: $speed"
        }
    }
    return $true
}

function Setup-OpenCode {
    Write-Host ''
    Write-Host '  OPENCODE SETUP'
    Write-Host '  =============='
    Write-Host ''

    # Check if opencode is installed
    $oc = Get-Command opencode -ErrorAction SilentlyContinue
    if (-not $oc) {
        $npm = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $npm) {
            Write-Host "  opencode is not installed and npm was not found."
            Write-Host "  Install Node.js from https://nodejs.org then run:"
            Write-Host "    npm i -g opencode-ai"
            Write-Host ''
        } else {
            Write-Host "  opencode is not installed."
            $ans = Read-Host "  Install now via 'npm i -g opencode-ai'? (y/n)"
            if ($ans -match '^[yY]') {
                Write-Host '  Installing opencode-ai...'
                $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                & npm i -g opencode-ai 2>&1 | ForEach-Object { Write-Host "    $_" }
                $ErrorActionPreference = $prevEAP
                $oc = Get-Command opencode -ErrorAction SilentlyContinue
                if ($oc) {
                    Write-Host '  opencode installed successfully.'
                } else {
                    Write-Host '  Installation may have failed. Try manually: npm i -g opencode-ai'
                }
                Write-Host ''
            } else {
                Write-Host '  Skipping install. You can install later with: npm i -g opencode-ai'
                Write-Host ''
            }
        }
    } else {
        Write-Host "  opencode found: $($oc.Source)"
        Write-Host ''
    }

    # Generate/update the config
    $result = Update-OpenCodeConfig
    Write-Host ''

    if ($result) {
        Write-Host '  To use with shard:'
        Write-Host '    1. shard           # start the server'
        Write-Host '    2. opencode        # launch OpenCode TUI'
        Write-Host '    3. /models         # select the shard model inside OpenCode'
        Write-Host ''
        Write-Host '  The config auto-updates after every "shard recalc".'
    }
    Write-Host ''
}

# ── Model Management Commands ──────────────────────────────────────────────────

function Show-Models {
    $activeModelId = Get-ActiveModelId
    $installed = Get-InstalledModels
    $installedIds = @($installed | Select-Object -ExpandProperty ModelId -Unique)

    Write-Host ''
    Write-Host '  AVAILABLE MODELS'
    Write-Host '  ================'
    Write-Host ''

    foreach ($mid in $ModelCatalog.Keys) {
        $mc = $ModelCatalog[$mid]
        $isActive = ($mid -eq $activeModelId)
        $arrow = if ($isActive) { '>' } else { ' ' }
        $files = @($installed | Where-Object { $_.ModelId -eq $mid })

        if ($files.Count -gt 0) {
            $quants = ($files | ForEach-Object { $_.Quant } | Select-Object -Unique) -join ', '
            $sizeMB = ($files | Measure-Object -Property SizeMB -Sum).Sum
            $sizeStr = if ($sizeMB -ge 1024) { "{0:N1} GB" -f ($sizeMB / 1024) } else { "${sizeMB} MB" }
            $tunedStr = if (Model-HasTunedProfiles $mid) { '[tuned]' } else { '[default]' }
            $activeStr = if ($isActive) { ' <-- active' } else { '' }
            Write-Host ("    {0} {1}  {2}  {3}  {4}  {5}{6}" -f $arrow, $mid.PadRight(5), $mc.Name.PadRight(14), $quants.PadRight(14), $sizeStr.PadRight(9), $tunedStr, $activeStr)
        } else {
            $defQuant = $mc.DefaultQuant
            $defSize = $mc.Quants[$defQuant]
            Write-Host ("    {0} {1}  {2}  --  not downloaded  (rec: {3} {4})" -f $arrow, $mid.PadRight(5), $mc.Name.PadRight(14), $defQuant, $defSize)
        }
    }

    Write-Host ''
    Write-Host "  Active model: $activeModelId"
    Write-Host "  Switch with:  shard model <id>   (e.g. shard model 9B)"
    Write-Host ''
}

function Switch-Model([string]$targetId) {
    # Accept case-insensitive
    $matched = @($ModelCatalog.Keys | Where-Object { $_.ToUpperInvariant() -eq $targetId.ToUpperInvariant() })
    if ($matched.Count -eq 0) {
        Write-Host "shard: unknown model '$targetId'"
        Write-Host "  Available: $($ModelCatalog.Keys -join ', ')"
        return
    }
    $targetId = $matched[0]

    $modelPath = Resolve-ModelPath -modelId $targetId
    if (-not $modelPath) {
        Write-Host "shard: model $targetId is not downloaded"
        Write-Host "  Run 'shard download $targetId' to get it"
        return
    }

    $oldModelId = Get-ActiveModelId
    Set-ActiveModelId $targetId
    $script:profiles = Load-Profiles -modelId $targetId
    Write-Host "shard: switched active model from $oldModelId to $targetId ($($ModelCatalog[$targetId].Name))"

    # If server is running on a different model, notify user
    $running = Get-RunningProcessFromState
    if ($null -ne $running) {
        $state = Get-ServerState
        $runModel = if ($state.ModelId) { $state.ModelId } else { $oldModelId }
        if ($runModel -ne $targetId) {
            Write-Host "shard: server is still running with $runModel. Use 'shard 1' to restart with the new model."
        }
    }
}

function Check-NewModels {
    Write-Host ''
    Write-Host '  CHECKING HUGGINGFACE FOR MODELS'
    Write-Host '  ================================'
    Write-Host ''

    $installed = Get-InstalledModels
    $installedIds = @($installed | Select-Object -ExpandProperty ModelId -Unique)

    # Check known repos
    foreach ($mid in $ModelCatalog.Keys) {
        $mc = $ModelCatalog[$mid]
        $apiUrl = "https://huggingface.co/api/models/$($mc.Repo)"
        $isInstalled = $mid -in $installedIds
        $status = if ($isInstalled) { 'installed' } else { 'available' }
        $icon = if ($isInstalled) { '[OK]' } else { '[--]' }

        try {
            $info = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10
            $downloads = if ($info.downloads) { "{0:N0}" -f $info.downloads } else { "?" }
            $likes = if ($info.likes) { $info.likes } else { "?" }
            Write-Host ("  {0} {1}  {2}  downloads: {3}  likes: {4}  ({5})" -f $icon, $mid.PadRight(5), $mc.Name.PadRight(14), $downloads.PadLeft(9), "$likes".PadLeft(4), $status)
        } catch {
            Write-Host ("  [??] {0}  {1}  could not reach HuggingFace" -f $mid.PadRight(5), $mc.Name.PadRight(14))
        }
    }

    # Search for new GGUF repos not in our catalog
    Write-Host ''
    Write-Host '  Checking for new models in the collection...'
    try {
        $searchUrl = "https://huggingface.co/api/models?author=Jackrong&search=Claude-4.6-Opus-Reasoning-Distilled-GGUF&sort=downloads&direction=-1&limit=20"
        $results = Invoke-RestMethod -Uri $searchUrl -TimeoutSec 15
        $knownRepos = @($ModelCatalog.Values | ForEach-Object { $_.Repo })
        $newRepos = @($results | Where-Object { $_.modelId -notin $knownRepos -and $_.modelId -match 'GGUF' })

        if ($newRepos.Count -gt 0) {
            Write-Host ''
            Write-Host '  NEW MODELS FOUND (not in catalog):'
            foreach ($r in $newRepos) {
                $downloads = if ($r.downloads) { "{0:N0}" -f $r.downloads } else { "?" }
                Write-Host ("    {0}  downloads: {1}" -f $r.modelId, $downloads)
            }
            Write-Host ''
            Write-Host '  These models may need a shard update to be supported.'
        } else {
            Write-Host '  No new models found outside the current catalog.'
        }
    } catch {
        Write-Host '  Could not search for new models (network error).'
    }

    Write-Host ''
    Write-Host "  Collection: $CollectionUrl"
    Write-Host ''
}

# ── Download ───────────────────────────────────────────────────────────────────

function Invoke-Download([string]$url, [string]$outFile) {
    Write-Host "Downloading: $url"
    $tmpFile = "$outFile.tmp"
    try {
        $response = [System.Net.HttpWebRequest]::Create($url).GetResponse()
        $totalBytes = $response.ContentLength
        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($tmpFile)
        $buffer = New-Object byte[] (8 * 1024 * 1024)
        $downloaded = 0
        $lastPct = -1
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $downloaded += $read
            if ($totalBytes -gt 0) {
                $pct = [int]([Math]::Floor($downloaded * 100 / $totalBytes))
                if ($pct -ne $lastPct -and $pct % 5 -eq 0) {
                    $dlMB = [Math]::Round($downloaded / 1MB, 0)
                    $totMB = [Math]::Round($totalBytes / 1MB, 0)
                    Write-Host "  ${pct}% (${dlMB} / ${totMB} MB)"
                    $lastPct = $pct
                }
            }
        }
        $fileStream.Close()
        $stream.Close()
        $response.Close()
        Move-Item -Path $tmpFile -Destination $outFile -Force
    } catch {
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Download-ModelFile {
    param(
        [string]$modelId,
        [string]$quant
    )

    $matched = @($ModelCatalog.Keys | Where-Object { $_.ToUpperInvariant() -eq $modelId.ToUpperInvariant() })
    if ($matched.Count -eq 0) {
        throw "unknown model: $modelId (available: $($ModelCatalog.Keys -join ', '))"
    }
    $modelId = $matched[0]
    $catalog = $ModelCatalog[$modelId]

    if (-not $quant) { $quant = $catalog.DefaultQuant }
    $quant = $quant.ToUpperInvariant()

    # Normalize Q8_0 casing
    if ($quant -match '^Q(\d+)_(\d+)$') { $quant = "Q$($Matches[1])_$($Matches[2])" }
    elseif ($quant -match '^Q(\d+)_K_([A-Z])$') { $quant = "Q$($Matches[1])_K_$($Matches[2])" }

    if (-not $catalog.Quants.Contains($quant)) {
        Write-Host "shard: quant '$quant' not available for $modelId"
        Write-Host "  Available: $($catalog.Quants.Keys -join ', ')"
        return
    }

    $fileName = "$($catalog.FilePrefix).$quant.gguf"
    $modelsDir = Join-Path $repoRoot "models"
    if (-not (Test-Path $modelsDir)) {
        New-Item -ItemType Directory -Path $modelsDir | Out-Null
    }

    $outPath = Join-Path $modelsDir $fileName
    if (Test-Path $outPath) {
        Write-Host "shard: $fileName already exists"
        return
    }

    $url = "https://huggingface.co/$($catalog.Repo)/resolve/main/${fileName}?download=true"
    $sizeStr = $catalog.Quants[$quant]
    Write-Host "shard: downloading $($catalog.Name) $quant ($sizeStr)"
    Invoke-Download -url $url -outFile $outPath
    Write-Host "shard: downloaded $fileName"
}

function Download-ModelInteractive {
    $installed = Get-InstalledModels
    $installedIds = @($installed | Select-Object -ExpandProperty ModelId -Unique)

    # Detect system specs for quant recommendations
    $specs = Detect-SystemSpecs
    $hasSpecs = ($null -ne $specs.VRAM_GB -and $null -ne $specs.TotalRAM_GB)
    $vramGB = if ($specs.VRAM_GB) { $specs.VRAM_GB } else { 0 }
    $ramGB = if ($specs.TotalRAM_GB) { $specs.TotalRAM_GB } else { 0 }
    $totalBudget = $vramGB + $ramGB - 8

    Write-Host ''
    Write-Host '  DOWNLOAD MODELS'
    Write-Host '  ==============='
    if ($hasSpecs) {
        Write-Host ("  Detected: {0} ({1} GB VRAM), {2} GB RAM" -f $specs.GPUName, $vramGB, $ramGB)
    }
    Write-Host ''

    $idx = 0
    $choices = @{}
    $recQuants = @{}
    foreach ($mid in $ModelCatalog.Keys) {
        $idx++
        $mc = $ModelCatalog[$mid]
        $choices["$idx"] = $mid
        $isInstalled = ($mid -in $installedIds)
        $files = @($installed | Where-Object { $_.ModelId -eq $mid })
        $installedStr = if ($isInstalled) { "  (have: $(($files | ForEach-Object { $_.Quant } | Select-Object -Unique) -join ', '))" } else { '' }

        if ($hasSpecs) {
            $rec = Get-RecommendedQuant -modelId $mid -vramGB $vramGB -ramGB $ramGB
            $recQuants[$mid] = $rec
            if ($rec.Tier -eq 'none') {
                Write-Host ("  [{0}] {1}  {2}  {3}  too large for your system{4}" -f $idx, $mid.PadRight(5), $mc.Name.PadRight(14), ('(min ' + $mc.Quants[($mc.Quants.Keys | Select-Object -First 1)] + ')').PadRight(14), $installedStr)
            } else {
                $tierTag = if ($rec.Tier -eq 'gpu') { 'fits GPU' } else { 'needs RAM' }
                Write-Host ("  [{0}] {1}  {2}  {3} ({4})  {5}{6}" -f $idx, $mid.PadRight(5), $mc.Name.PadRight(14), $rec.Quant.PadRight(8), $rec.Size, $tierTag, $installedStr)
            }
        } else {
            $defSize = $mc.Quants[$mc.DefaultQuant]
            Write-Host ("  [{0}] {1}  {2}  default: {3} ({4}){5}" -f $idx, $mid.PadRight(5), $mc.Name.PadRight(14), $mc.DefaultQuant, $defSize, $installedStr)
        }
    }

    Write-Host ''
    Write-Host "  Enter model number(s) to download (e.g. 1,3 or 'all'), or 'q' to cancel"
    $input = Read-Host "  Selection"

    if ($input -eq 'q' -or [string]::IsNullOrWhiteSpace($input)) {
        Write-Host "  Cancelled."
        return
    }

    $toDownload = @()
    if ($input.ToLowerInvariant() -eq 'all') {
        $toDownload = @($ModelCatalog.Keys)
    } else {
        foreach ($part in ($input -split ',')) {
            $num = $part.Trim()
            if ($choices.Contains($num)) {
                $toDownload += $choices[$num]
            } elseif ($ModelCatalog.Contains($num.ToUpperInvariant())) {
                $toDownload += $num.ToUpperInvariant()
            } else {
                Write-Host "  Unknown selection: $num"
            }
        }
    }

    if ($toDownload.Count -eq 0) {
        Write-Host "  No valid models selected."
        return
    }

    # Per-model quant selection with recommendations
    foreach ($mid in $toDownload) {
        $mc = $ModelCatalog[$mid]
        $rec = if ($recQuants.Contains($mid)) { $recQuants[$mid] } else { $null }
        $defaultQuant = if ($rec -and $rec.Quant) { $rec.Quant } else { $mc.DefaultQuant }

        Write-Host ''
        Write-Host ("  Quants for {0} ({1}):" -f $mid, $mc.Name)

        $quantKeys = @($mc.Quants.Keys)
        foreach ($q in $quantKeys) {
            $sizeStr = $mc.Quants[$q]
            $sizeGB = Parse-SizeToGB $sizeStr
            $tag = ''
            if ($hasSpecs -and $null -ne $sizeGB) {
                $tier = Get-QuantTier -sizeGB $sizeGB -vramGB $vramGB -totalBudget $totalBudget
                $tag = switch ($tier) {
                    'gpu'      { '  fits GPU' }
                    'near-gpu' { '  mostly GPU' }
                    'partial'  { '  needs RAM' }
                    'toolarge' { '  too large' }
                }
                if ($q -eq $defaultQuant) { $tag += '  << recommended' }
            }
            $marker = if ($q -eq $defaultQuant) { '>' } else { ' ' }
            Write-Host ("    {0} {1}  {2}{3}" -f $marker, $q.PadRight(8), $sizeStr.PadRight(10), $tag)
        }

        Write-Host ("  Quant to download? [{0}]" -f $defaultQuant)
        $quantInput = Read-Host "  Quant"
        $quant = if ([string]::IsNullOrWhiteSpace($quantInput)) { $defaultQuant } else { $quantInput.Trim() }

        try {
            Download-ModelFile -modelId $mid -quant $quant
        } catch {
            Write-Host "shard: error downloading ${mid}: $_"
        }
    }

    Write-Host ''
    Write-Host "  Done. Run 'shard recalc' to tune profiles for the new model(s)."
    Write-Host ''
}

# ── Reset / Update ─────────────────────────────────────────────────────────────

function Reset-Profiles {
    param([string]$modelId)

    if ($modelId) {
        # Reset specific model
        $allData = Load-AllProfileData
        if ($allData["models"] -and $allData["models"].Contains($modelId)) {
            $allData["models"].Remove($modelId)
            Save-AllProfileData $allData
            Write-Host "shard: removed profile overrides for $modelId"
        } else {
            Write-Host "shard: no profile overrides found for $modelId"
        }
    } else {
        # Reset all
        if (Test-Path $profileOverrideFile) {
            Remove-Item -Path $profileOverrideFile -Force
            Write-Host "shard: removed all profile overrides"
        } else {
            Write-Host "shard: no profile overrides found"
        }
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

    Write-Host "shard: updating llama.cpp runtime to latest..."
    & $installScript -SkipModelDownload -Force
    if ($LASTEXITCODE -ne 0) {
        throw "shard: update failed"
    }

    if ($resumeProfileId) {
        $script:profiles = Load-Profiles
        Write-Host ("shard: restarting previously running profile {0}" -f $resumeProfileId)
        Start-Shard -profileId $resumeProfileId
    }

    Write-Host "shard: update complete"
}

# ── Command Dispatch ───────────────────────────────────────────────────────────

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
    "model" {
        if ($CommandArgs.Count -gt 1) {
            Switch-Model -targetId $CommandArgs[1]
        } else {
            Show-Models
        }
    }
    "check" {
        Check-NewModels
    }
    "download" {
        if ($CommandArgs.Count -gt 1) {
            $dlModelId = $CommandArgs[1]
            $dlQuant = if ($CommandArgs.Count -gt 2) { $CommandArgs[2] } else { $null }
            Download-ModelFile -modelId $dlModelId -quant $dlQuant
        } else {
            Download-ModelInteractive
        }
    }
    "update" {
        Update-Shard
    }
    "opencode" {
        Setup-OpenCode
    }
    "recalc" {
        $recalcArgs = @()
        if ($CommandArgs.Count -gt 1) {
            $recalcArgs = @($CommandArgs[1] -split ',')
        }
        Recalculate-Profiles -modelIds $recalcArgs
    }
    "reset" {
        $resetModel = if ($CommandArgs.Count -gt 1) { $CommandArgs[1] } else { $null }
        Reset-Profiles -modelId $resetModel
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
