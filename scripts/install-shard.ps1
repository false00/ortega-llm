param(
    [switch]$SkipRuntimeDownload,
    [switch]$SkipModelDownload,
    [string]$LlamaCppTag,
    [switch]$Force,
    [string[]]$Models,
    [string]$Quant = "Q4_K_M"
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "install-shard: requires PowerShell 7 or later (running $($PSVersionTable.PSVersion))"
    Write-Host "Install from: https://aka.ms/install-powershell"
    Write-Host "Then re-run with: pwsh -File $($MyInvocation.MyCommand.Path)"
    exit 1
}

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$launcherScript = Join-Path $repoRoot "scripts\shard.ps1"

if (-not (Test-Path $launcherScript)) {
    throw "launcher script not found: $launcherScript"
}

# ── Model Catalog (mirrors shard.ps1) ─────────────────────────────────────────

$ModelCatalog = [ordered]@{
    "27B" = @{
        Name         = "Qwen3.5-27B"
        Repo         = "Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-27B"
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K" = "10.1 GB"; "Q3_K_S" = "12.1 GB"; "Q3_K_M" = "13.3 GB"
            "Q4_K_S" = "15.6 GB"; "Q4_K_M" = "16.5 GB"; "Q8_0" = "28.6 GB"
        }
    }
    "9B" = @{
        Name         = "Qwen3.5-9B"
        Repo         = "Jackrong/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-9B"
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K" = "3.6 GB"; "Q3_K_S" = "4.3 GB"; "Q3_K_M" = "4.6 GB"; "Q3_K_L" = "4.8 GB"
            "Q4_K_S" = "5.3 GB"; "Q4_K_M" = "5.6 GB"; "Q5_K_S" = "6.3 GB"; "Q5_K_M" = "6.5 GB"
            "Q6_K" = "7.4 GB"; "Q8_0" = "9.5 GB"
        }
    }
    "4B" = @{
        Name         = "Qwen3.5-4B"
        Repo         = "Jackrong/Qwen3.5-4B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-4B"
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K" = "1.8 GB"; "Q3_K_S" = "2.1 GB"; "Q3_K_M" = "2.3 GB"; "Q3_K_L" = "2.4 GB"
            "Q4_K_S" = "2.6 GB"; "Q4_K_M" = "2.7 GB"; "Q5_K_S" = "3.0 GB"; "Q5_K_M" = "3.1 GB"
            "Q6_K" = "3.5 GB"; "Q8_0" = "4.5 GB"
        }
    }
    "2B" = @{
        Name         = "Qwen3.5-2B"
        Repo         = "Jackrong/Qwen3.5-2B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-2B"
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K" = "915 MB"; "Q3_K_S" = "1.0 GB"; "Q3_K_M" = "1.1 GB"; "Q3_K_L" = "1.1 GB"
            "Q4_K_S" = "1.2 GB"; "Q4_K_M" = "1.3 GB"; "Q5_K_S" = "1.4 GB"; "Q5_K_M" = "1.4 GB"
            "Q6_K" = "1.6 GB"; "Q8_0" = "2.0 GB"
        }
    }
    "0.8B" = @{
        Name         = "Qwen3.5-0.8B"
        Repo         = "Jackrong/Qwen3.5-0.8B-Claude-4.6-Opus-Reasoning-Distilled-GGUF"
        FilePrefix   = "Qwen3.5-0.8B"
        DefaultQuant = "Q4_K_M"
        Quants = [ordered]@{
            "Q2_K" = "396 MB"; "Q3_K_S" = "435 MB"; "Q3_K_M" = "465 MB"; "Q3_K_L" = "477 MB"
            "Q4_K_S" = "503 MB"; "Q4_K_M" = "527 MB"; "Q5_K_S" = "564 MB"; "Q5_K_M" = "585 MB"
            "Q6_K" = "630 MB"; "Q8_0" = "812 MB"
        }
    }
}

# ── Helpers ────────────────────────────────────────────────────────────────────

function Ensure-Dir([string]$path) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Parse-SizeToGB([string]$sizeStr) {
    if ($sizeStr -match '^([\d.]+)\s*GB$') { return [double]$Matches[1] }
    if ($sizeStr -match '^([\d.]+)\s*MB$') { return [double]$Matches[1] / 1024 }
    return $null
}

function Detect-VramAndRam {
    $result = @{ VRAM_GB = $null; RAM_GB = $null; GPUName = $null }
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) { $result.RAM_GB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1) }
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
                $result.GPUName = $parts[0].Trim()
                if ($parts.Count -gt 1) { $result.VRAM_GB = [Math]::Round([double]$parts[1].Trim() / 1024, 1) }
            }
        } catch { $ErrorActionPreference = $prevEAP }
    }
    return $result
}

function Get-RecommendedQuant {
    param([string]$modelId, [double]$vramGB, [double]$ramGB)
    $catalog = $ModelCatalog[$modelId]
    if (-not $catalog) { return $null }
    $vramBudget = $vramGB + 2
    $totalBudget = $vramGB + $ramGB - 8
    $quantKeys = @($catalog.Quants.Keys)
    [array]::Reverse($quantKeys)
    $bestGpu = $null; $bestPartial = $null
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

function Get-NvidiaCudaVersion {
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($null -eq $smi) { return $null }
    $raw = & nvidia-smi 2>$null | Out-String
    if ($raw -match "CUDA Version:\s*([0-9]+\.[0-9]+)") { return $Matches[1] }
    return $null
}

function Resolve-CudaVariant {
    $cuda = Get-NvidiaCudaVersion
    if ($null -eq $cuda) { return $null }
    try {
        $v = [version]$cuda
        if ($v -ge [version]"13.1") { return "13.1" }
        return "12.4"
    } catch { return "12.4" }
}

function Resolve-LlamaCppTag {
    param([string]$requestedTag)
    if (-not [string]::IsNullOrWhiteSpace($requestedTag)) { return $requestedTag }
    try {
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
        if ($latest.tag_name) { return [string]$latest.tag_name }
    } catch {
        Write-Host "Warning: could not query latest llama.cpp release tag. Falling back to b8589."
    }
    return "b8589"
}

# ── Runtime Install ────────────────────────────────────────────────────────────

function Install-LlamaRuntime {
    param(
        [string]$tag,
        [bool]$forceDownload
    )

    $toolsDir = Join-Path $repoRoot "tools"
    Ensure-Dir $toolsDir

    $cudaVariant = Resolve-CudaVariant

    if ($cudaVariant) {
        Write-Host "Detected NVIDIA CUDA runtime version: $cudaVariant"
        $runtimeDirName = "llama-$tag-win-cuda-$($cudaVariant -replace '\\.', '_')"
        $runtimeDir = Join-Path $toolsDir $runtimeDirName

        if ((Test-Path $runtimeDir) -and -not $forceDownload) {
            Write-Host "Runtime already exists, skipping download: $runtimeDir"
            return
        }

        $mainZip = Join-Path $toolsDir "llama-$tag-bin-win-cuda-$cudaVariant-x64.zip"
        $cudartZip = Join-Path $toolsDir "cudart-llama-bin-win-cuda-$cudaVariant-x64.zip"

        $mainUrl = "https://github.com/ggml-org/llama.cpp/releases/download/$tag/llama-$tag-bin-win-cuda-$cudaVariant-x64.zip"
        $cudartUrl = "https://github.com/ggml-org/llama.cpp/releases/download/$tag/cudart-llama-bin-win-cuda-$cudaVariant-x64.zip"

        Invoke-Download -url $mainUrl -outFile $mainZip
        Invoke-Download -url $cudartUrl -outFile $cudartZip

        if (Test-Path $runtimeDir) { Remove-Item -Path $runtimeDir -Recurse -Force }
        Ensure-Dir $runtimeDir

        Expand-Archive -Path $mainZip -DestinationPath $runtimeDir -Force
        Expand-Archive -Path $cudartZip -DestinationPath $runtimeDir -Force

        Remove-Item -Path $mainZip -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $cudartZip -Force -ErrorAction SilentlyContinue

        Write-Host "Installed CUDA runtime to: $runtimeDir"
    } else {
        Write-Host "No NVIDIA CUDA detected. Installing CPU llama.cpp runtime."

        $runtimeDirName = "llama-$tag-win-cpu"
        $runtimeDir = Join-Path $toolsDir $runtimeDirName

        if ((Test-Path $runtimeDir) -and -not $forceDownload) {
            Write-Host "Runtime already exists, skipping download: $runtimeDir"
            return
        }

        $zipPath = Join-Path $toolsDir "llama-$tag-bin-win-cpu-x64.zip"
        $url = "https://github.com/ggml-org/llama.cpp/releases/download/$tag/llama-$tag-bin-win-cpu-x64.zip"

        Invoke-Download -url $url -outFile $zipPath

        if (Test-Path $runtimeDir) { Remove-Item -Path $runtimeDir -Recurse -Force }
        Ensure-Dir $runtimeDir

        Expand-Archive -Path $zipPath -DestinationPath $runtimeDir -Force

        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue

        Write-Host "Installed CPU runtime to: $runtimeDir"
    }
}

# ── Model Install ──────────────────────────────────────────────────────────────

function Install-Model {
    param(
        [string]$modelId,
        [string]$quant,
        [bool]$forceDownload
    )

    $catalog = $ModelCatalog[$modelId]
    if (-not $catalog) { throw "Unknown model: $modelId" }

    $fileName = "$($catalog.FilePrefix).$quant.gguf"
    $modelsDir = Join-Path $repoRoot "models"
    Ensure-Dir $modelsDir

    $outPath = Join-Path $modelsDir $fileName
    if ((Test-Path $outPath) -and -not $forceDownload) {
        Write-Host "Model already exists, skipping download: $outPath"
        return
    }

    $url = "https://huggingface.co/$($catalog.Repo)/resolve/main/${fileName}?download=true"
    $sizeStr = $catalog.Quants[$quant]
    Write-Host "Downloading $($catalog.Name) $quant ($sizeStr)..."
    Invoke-Download -url $url -outFile $outPath
    Write-Host "Downloaded model to: $outPath"
}

function Select-ModelsInteractive {
    # Detect hardware for recommendations
    $hw = Detect-VramAndRam
    $hasSpecs = ($null -ne $hw.VRAM_GB -and $null -ne $hw.RAM_GB)
    $vramGB = if ($hw.VRAM_GB) { $hw.VRAM_GB } else { 0 }
    $ramGB = if ($hw.RAM_GB) { $hw.RAM_GB } else { 0 }
    $totalBudget = $vramGB + $ramGB - 8

    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════════════════════╗'
    Write-Host '  ║  SHARD - Model Selection                                    ║'
    Write-Host '  ║  Qwen3.5-Claude-4.6-Opus-Reasoning-Distilled (GGUF)        ║'
    Write-Host '  ╚══════════════════════════════════════════════════════════════╝'
    if ($hasSpecs) {
        Write-Host ("  Detected: {0} ({1} GB VRAM), {2} GB RAM" -f $hw.GPUName, $vramGB, $ramGB)
    }
    Write-Host ''

    $idx = 0
    $choices = @{}
    $recQuants = @{}
    foreach ($mid in $ModelCatalog.Keys) {
        $idx++
        $mc = $ModelCatalog[$mid]
        $choices["$idx"] = $mid

        if ($hasSpecs) {
            $rec = Get-RecommendedQuant -modelId $mid -vramGB $vramGB -ramGB $ramGB
            $recQuants[$mid] = $rec
            if ($rec.Tier -eq 'none') {
                $minSize = $mc.Quants[($mc.Quants.Keys | Select-Object -First 1)]
                Write-Host ("  [{0}]  {1}  {2}  too large for your system (min {3})" -f $idx, $mid.PadRight(5), $mc.Name.PadRight(14), $minSize)
            } else {
                $tierTag = if ($rec.Tier -eq 'gpu') { 'fits GPU' } else { 'needs RAM' }
                Write-Host ("  [{0}]  {1}  {2}  {3} ({4})  {5}" -f $idx, $mid.PadRight(5), $mc.Name.PadRight(14), $rec.Quant.PadRight(8), $rec.Size, $tierTag)
            }
        } else {
            $defSize = $mc.Quants[$Quant]
            if (-not $defSize) { $defSize = $mc.Quants[$mc.DefaultQuant] }
            Write-Host ("  [{0}]  {1}  {2}  {3} ({4})" -f $idx, $mid.PadRight(5), $mc.Name.PadRight(14), $Quant.PadRight(8), $defSize)
        }
    }

    Write-Host ''
    Write-Host "  Enter model number(s) to download (e.g. 1 or 1,3 or 'all')"
    Write-Host "  Press Enter for default [1 = 27B]"
    $selection = Read-Host "  Selection"

    if ([string]::IsNullOrWhiteSpace($selection)) { $selection = "1" }

    $selected = @()
    if ($selection.ToLowerInvariant() -eq 'all') {
        $selected = @($ModelCatalog.Keys)
    } else {
        foreach ($part in ($selection -split ',')) {
            $num = $part.Trim()
            if ($choices.ContainsKey($num)) {
                $selected += $choices[$num]
            } elseif ($ModelCatalog.ContainsKey($num.ToUpperInvariant())) {
                $selected += $num.ToUpperInvariant()
            } else {
                Write-Host "  Unknown selection: $num, skipping"
            }
        }
    }

    if ($selected.Count -eq 0) { return @() }

    # Per-model quant selection with recommendations
    $results = @()
    foreach ($mid in $selected) {
        $mc = $ModelCatalog[$mid]
        $rec = if ($recQuants.ContainsKey($mid)) { $recQuants[$mid] } else { $null }
        $defaultQ = if ($rec -and $rec.Quant) { $rec.Quant } elseif ($Quant -and $mc.Quants.Contains($Quant)) { $Quant } else { $mc.DefaultQuant }

        Write-Host ''
        Write-Host ("  Quants for {0} ({1}):" -f $mid, $mc.Name)

        foreach ($q in $mc.Quants.Keys) {
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
                if ($q -eq $defaultQ) { $tag += '  << recommended' }
            }
            $marker = if ($q -eq $defaultQ) { '>' } else { ' ' }
            Write-Host ("    {0} {1}  {2}{3}" -f $marker, $q.PadRight(8), $sizeStr.PadRight(10), $tag)
        }

        Write-Host ("  Quant to download? [{0}]" -f $defaultQ)
        $quantInput = Read-Host "  Quant"
        $chosenQuant = if ([string]::IsNullOrWhiteSpace($quantInput)) { $defaultQ } else { $quantInput.Trim() }
        $results += @{ Id = $mid; Quant = $chosenQuant }
    }

    return ,$results
}

# ── Shard Command Install ──────────────────────────────────────────────────────

function Install-ShardCommand {
    $targetDir = Join-Path $HOME "bin"
    $cmdPath = Join-Path $targetDir "shard.cmd"

    [Environment]::SetEnvironmentVariable("SHARD_HOME", $repoRoot, "User")
    $env:SHARD_HOME = $repoRoot

    Ensure-Dir $targetDir

    $cmdContent = @"
@echo off
set "SCRIPT=%SHARD_HOME%\scripts\shard.ps1"
if not exist "%SCRIPT%" (
    echo shard: launcher script not found at %SCRIPT%
    echo shard: re-run install-shard.ps1 to fix
    exit /b 1
)
pwsh -NoProfile -File "%SCRIPT%" %*
"@

    Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII
    Write-Host "Installed shard command: $cmdPath"

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$targetDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$targetDir;$currentPath", "User")
        Write-Host "Added $targetDir to PATH"
    }

    Write-Host ""
    Write-Host "  SHARD_HOME = $repoRoot"
    Write-Host "  Command:     $cmdPath"
    Write-Host ""
    Write-Host "  Open a NEW terminal, then run:"
    Write-Host "    shard detect     # see your hardware"
    Write-Host "    shard recalc     # auto-tune for your GPU"
    Write-Host "    shard            # start the server"
}

# ── Main ───────────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '  ╔══════════════════════════════════════════════════════╗'
Write-Host '  ║  SHARD INSTALLER                                    ║'
Write-Host '  ╚══════════════════════════════════════════════════════╝'
Write-Host ''

# Step 1: Runtime
if (-not $SkipRuntimeDownload) {
    $tag = Resolve-LlamaCppTag -requestedTag $LlamaCppTag
    Write-Host "llama.cpp release: $tag"
    Install-LlamaRuntime -tag $tag -forceDownload $Force
    Write-Host ''
} else {
    Write-Host "Skipping runtime download (-SkipRuntimeDownload)"
    Write-Host ''
}

# Step 2: Models
if (-not $SkipModelDownload) {
    $modelsToInstall = @()

    if ($null -ne $Models -and $Models.Count -gt 0) {
        # Models specified via parameter — resolve recommended quants
        $hw = Detect-VramAndRam
        $hasHw = ($null -ne $hw.VRAM_GB -and $null -ne $hw.RAM_GB)

        $modelIds = @()
        if ($Models.Count -eq 1 -and $Models[0].ToLowerInvariant() -eq 'all') {
            $modelIds = @($ModelCatalog.Keys)
        } else {
            foreach ($m in $Models) {
                $upper = $m.ToUpperInvariant()
                if ($ModelCatalog.ContainsKey($upper)) {
                    $modelIds += $upper
                } elseif ($ModelCatalog.ContainsKey($m)) {
                    $modelIds += $m
                } else {
                    Write-Host "Unknown model: $m (available: $($ModelCatalog.Keys -join ', '))"
                }
            }
        }

        foreach ($mid in $modelIds) {
            $mc = $ModelCatalog[$mid]
            $q = $Quant
            if ($hasHw -and $q -eq 'Q4_K_M') {
                # Use recommended quant when user didn't override
                $rec = Get-RecommendedQuant -modelId $mid -vramGB $hw.VRAM_GB -ramGB $hw.RAM_GB
                if ($rec.Quant) { $q = $rec.Quant }
            }
            if (-not $mc.Quants.Contains($q)) {
                Write-Host "Quant $q not available for $mid, using $($mc.DefaultQuant)"
                $q = $mc.DefaultQuant
            }
            $modelsToInstall += @{ Id = $mid; Quant = $q }
        }
    } else {
        # Interactive selection (returns @{Id; Quant} objects)
        $modelsToInstall = @(Select-ModelsInteractive)
    }

    if ($modelsToInstall.Count -eq 0) {
        Write-Host "No models selected, skipping model download."
    } else {
        Write-Host ''
        $summary = ($modelsToInstall | ForEach-Object { "$($_.Id) $($_.Quant)" }) -join ', '
        Write-Host ("Downloading {0} model(s): {1}" -f $modelsToInstall.Count, $summary)
        Write-Host ''

        foreach ($entry in $modelsToInstall) {
            Install-Model -modelId $entry.Id -quant $entry.Quant -forceDownload $Force
        }
    }

    Write-Host ''
} else {
    Write-Host "Skipping model download (-SkipModelDownload)"
    Write-Host ''
}

# Step 3: Shard command
Install-ShardCommand
