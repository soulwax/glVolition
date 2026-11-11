param(
    [string]$Version = "UNRELEASED",
    [string]$DistDir = "./dist",
    [switch]$SkipTests = $false,
    [switch]$SkipAnalyze = $false
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " glVolition Distribution Packager" -ForegroundColor Cyan
Write-Host " Target Version: $Version" -ForegroundColor Cyan
Write-Host " Output Dir:     $DistDir" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Verification: Static Analysis
if (-not $SkipAnalyze) {
    Write-Host "`n[1/4] Running static analysis..." -ForegroundColor Yellow
    dart analyze
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Static analysis failed. Aborting distribution build."
        exit $LASTEXITCODE
    }
    Write-Host "Analysis passed cleanly (0 issues)." -ForegroundColor Green
} else {
    Write-Host "`n[1/4] Skipping static analysis." -ForegroundColor Gray
}

# 2. Verification: Test Suite
if (-not $SkipTests) {
    Write-Host "`n[2/4] Running full test suite..." -ForegroundColor Yellow
    dart test
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Test suite failed. Aborting distribution build."
        exit $LASTEXITCODE
    }
    Write-Host "All tests passed cleanly." -ForegroundColor Green
} else {
    Write-Host "`n[2/4] Skipping test suite." -ForegroundColor Gray
}

# 3. Create Distribution Directories
Write-Host "`n[3/4] Preparing distribution directory structure..." -ForegroundColor Yellow
$resolvedDist = [System.IO.Path]::GetFullPath($DistDir)
if (-not (Test-Path $resolvedDist)) {
    New-Item -ItemType Directory -Path $resolvedDist -Force | Out-Null
}

$versionDist = Join-Path $resolvedDist $Version
if (-not (Test-Path $versionDist)) {
    New-Item -ItemType Directory -Path $versionDist -Force | Out-Null
}

$binDist = Join-Path $versionDist "bin"
if (-not (Test-Path $binDist)) {
    New-Item -ItemType Directory -Path $binDist -Force | Out-Null
}

# 4. Write Version & Metadata
Write-Host "`n[4/4] Writing version and build metadata..." -ForegroundColor Yellow
$versionFilePath = Join-Path $resolvedDist "version"
$Version.Trim() | Set-Content -Path $versionFilePath -Encoding UTF8 -NoNewline

$commitHash = ""
try {
    $commitHash = (git rev-parse --short HEAD).Trim()
} catch {
    $commitHash = "unknown"
}

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$metadata = @"
{
  "name": "gl_volition",
  "version": "$Version",
  "commit": "$commitHash",
  "builtAt": "$timestamp",
  "status": "$Version"
}
"@

$metaFilePath = Join-Path $versionDist "metadata.json"
$metadata | Set-Content -Path $metaFilePath -Encoding UTF8

# Compile volition CLI binary into dist/<version>/bin/volition.exe
Write-Host "Compiling volition executable to $binDist\volition.exe..." -ForegroundColor Yellow
dart compile exe bin/volition.dart -o (Join-Path $binDist "volition.exe")
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Could not compile native volition CLI executable (non-fatal for web-only setups)."
} else {
    Write-Host "Compiled volition CLI executable successfully: $binDist\volition.exe" -ForegroundColor Green
}

# Build Standalone Windows Desktop Game Host into dist/<version>/pixel_rocket/windows
Write-Host "`nBuilding standalone Windows desktop game into $versionDist\pixel_rocket\windows..." -ForegroundColor Yellow
dart run bin/volition.dart build example/pixel_rocket/main.dart --target windows --version $Version --dist $resolvedDist
if ($LASTEXITCODE -eq 0) {
    $gameDist = Join-Path $versionDist "pixel_rocket\windows"
    $gameExe = Join-Path $gameDist "GlVolitionGame.exe"
    
    # Create double-clickable launcher script in dist
    $launcherPath = Join-Path $resolvedDist "Launch_Pixel_Rocket.cmd"
    @"
@echo off
setlocal
cd /d "%~dp0"
if exist "$Version\pixel_rocket\windows\pixel_rocket.exe" (
    start "" "%~dp0$Version\pixel_rocket\windows\pixel_rocket.exe"
    exit /b 0
)
if exist "$Version\pixel_rocket\windows\GlVolitionGame.exe" (
    start "" "%~dp0$Version\pixel_rocket\windows\GlVolitionGame.exe"
    exit /b 0
)
if exist "$Version\pixel_rocket\windows\index.html" (
    start "" msedge --app="%~dp0$Version\pixel_rocket\windows\index.html"
    exit /b 0
)
echo [ERROR] No runnable game binary found under $Version\pixel_rocket\windows.
pause
"@ | Set-Content -Path $launcherPath -Encoding ASCII
    Write-Host "Created game launcher: $launcherPath" -ForegroundColor Green
} else {
    Write-Warning "Windows game build could not complete (dotnet or WebView2 may be missing)."
}

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host " Distribution artifacts built successfully!" -ForegroundColor Green
Write-Host " Version written to: $versionFilePath ($Version)" -ForegroundColor Green
Write-Host " Metadata written to: $metaFilePath" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
