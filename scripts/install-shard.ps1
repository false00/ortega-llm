param(
    [switch]$SkipRuntimeDownload,
    [switch]$SkipModelDownload,
    [string]$LlamaCppTag,
    [switch]$Force,
    [string]$ModelRepo = "Jackrong/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-GGUF",
    [string]$ModelFile = "Qwen3.5-27B.Q4_K_M.gguf"
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

function Ensure-Dir([string]$path) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
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
    if ($null -eq $smi) {
        return $null
    }

    $raw = & nvidia-smi 2>$null | Out-String
    if ($raw -match "CUDA Version:\s*([0-9]+\.[0-9]+)") {
        return $Matches[1]
    }

    return $null
}

function Resolve-CudaVariant {
    $cuda = Get-NvidiaCudaVersion
    if ($null -eq $cuda) {
        return $null
    }

    try {
        $v = [version]$cuda
        if ($v -ge [version]"13.1") {
            return "13.1"
        }
        return "12.4"
    } catch {
        return "12.4"
    }
}

function Resolve-LlamaCppTag {
    param([string]$requestedTag)

    if (-not [string]::IsNullOrWhiteSpace($requestedTag)) {
        return $requestedTag
    }

    try {
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
        if ($latest.tag_name) {
            return [string]$latest.tag_name
        }
    } catch {
        Write-Host "Warning: could not query latest llama.cpp release tag. Falling back to b8589."
    }

    return "b8589"
}

function Install-LlamaRuntime {
    param(
        [string]$tag,
        [bool]$forceDownload
    )

    $toolsDir = Join-Path $repoRoot "tools"
    Ensure-Dir $toolsDir

    $cudaVariant = Resolve-CudaVariant
    $runtimeDirName = ""

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

        if (Test-Path $runtimeDir) {
            Remove-Item -Path $runtimeDir -Recurse -Force
        }
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

        if (Test-Path $runtimeDir) {
            Remove-Item -Path $runtimeDir -Recurse -Force
        }
        Ensure-Dir $runtimeDir

        Expand-Archive -Path $zipPath -DestinationPath $runtimeDir -Force

        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue

        Write-Host "Installed CPU runtime to: $runtimeDir"
    }
}

function Install-Model {
    param(
        [string]$repo,
        [string]$file,
        [bool]$forceDownload
    )

    $modelsDir = Join-Path $repoRoot "models"
    Ensure-Dir $modelsDir

    $outPath = Join-Path $modelsDir $file
    if ((Test-Path $outPath) -and -not $forceDownload) {
        Write-Host "Model already exists, skipping download: $outPath"
        return
    }

    if ((Test-Path $outPath) -and $forceDownload) {
        Write-Host "Force enabled: re-downloading model to: $outPath"
    }

    $url = "https://huggingface.co/${repo}/resolve/main/${file}?download=true"
    Invoke-Download -url $url -outFile $outPath
    Write-Host "Downloaded model to: $outPath"
}

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
    echo shard: script not found at %SCRIPT%
    echo Hint: run install-shard.ps1 again from your repo clone.
    exit /b 1
)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
"@

    Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrWhiteSpace($userPath)) {
        $userPath = ""
    }

    $paths = $userPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $alreadyInPath = $false
    foreach ($p in $paths) {
        if ($p.TrimEnd("\\") -ieq $targetDir.TrimEnd("\\")) {
            $alreadyInPath = $true
            break
        }
    }

    if (-not $alreadyInPath) {
        $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $targetDir } else { "$userPath;$targetDir" }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added to user PATH: $targetDir"
    } else {
        Write-Host "PATH already contains: $targetDir"
    }

    Write-Host ""
    Write-Host "Installed command: shard"
    Write-Host "Launcher file: $cmdPath"
    Write-Host "SHARD_HOME: $repoRoot"
}

$resolvedTag = Resolve-LlamaCppTag -requestedTag $LlamaCppTag
Write-Host "Using llama.cpp release tag: $resolvedTag"

if (-not $SkipRuntimeDownload) {
    Install-LlamaRuntime -tag $resolvedTag -forceDownload:$Force
} else {
    Write-Host "Skipping runtime download (--SkipRuntimeDownload)"
}

if (-not $SkipModelDownload) {
    Install-Model -repo $ModelRepo -file $ModelFile -forceDownload:$Force
} else {
    Write-Host "Skipping model download (--SkipModelDownload)"
}

Install-ShardCommand

Write-Host ""
Write-Host "Open a NEW terminal, then run:"
Write-Host "  shard info"
Write-Host "  shard ls"
Write-Host "  shard"
Write-Host "  shard 2"
Write-Host "  shard stop"
