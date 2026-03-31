$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$launcherScript = Join-Path $repoRoot "scripts\ortega.ps1"

if (-not (Test-Path $launcherScript)) {
    throw "launcher script not found: $launcherScript"
}

$targetDir = Join-Path $HOME "bin"
$cmdPath = Join-Path $targetDir "ortega.cmd"

if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}

$cmdContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$launcherScript" %*
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
Write-Host "Installed command: ortega"
Write-Host "Launcher file: $cmdPath"
Write-Host ""
Write-Host "Open a NEW terminal, then run:"
Write-Host "  ortega ls"
Write-Host "  ortega"
Write-Host "  ortega 2"
Write-Host "  ortega stop"
