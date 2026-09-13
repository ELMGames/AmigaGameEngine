# build.ps1 - Assemble and link the game from the command line (no VS Code needed).
#
# Usage:
#   ./build.ps1                 build ../uae/dh0/main (same output as the VS Code task)
#   ./build.ps1 -Assets         regenerate converted assets first (tools/convert_assets.py)
#   ./build.ps1 -Out my.exe     build to a different output path
#   ./build.ps1 -ToolDir <dir>  use vasm/vlink from a specific directory
#
# Toolchain resolution order:
#   1. -ToolDir parameter
#   2. AMIGA_TOOLCHAIN environment variable
#   3. vasmm68k_mot on PATH
#   4. the amiga-assembly VS Code extension's bundled binaries
param(
    [switch]$Assets,
    [string]$Out = "../uae/dh0/main",
    [string]$ToolDir = ""
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- Locate the toolchain -----------------------------------------------------
if (-not $ToolDir -and $env:AMIGA_TOOLCHAIN) { $ToolDir = $env:AMIGA_TOOLCHAIN }
if (-not $ToolDir) {
    $onPath = Get-Command "vasmm68k_mot*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($onPath) { $ToolDir = Split-Path $onPath.Source }
}
if (-not $ToolDir) {
    $ext = Get-ChildItem "$env:USERPROFILE\.vscode\extensions\prb28.amiga-assembly-*\resources\bin\win32" `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ext) { $ToolDir = $ext.FullName }
}
$exe = if ($IsWindows -or $env:OS -eq "Windows_NT") { ".exe" } else { "" }
$vasm  = Join-Path $ToolDir "vasmm68k_mot$exe"
$vlink = Join-Path $ToolDir "vlink$exe"
if (-not (Test-Path $vasm)) {
    Write-Error "vasm not found. Pass -ToolDir, set AMIGA_TOOLCHAIN, or install the amiga-assembly VS Code extension."
}

# --- Optional: regenerate converted assets ------------------------------------
if ($Assets) {
    Write-Host "== Converting assets =="
    python tools/convert_assets.py
    if ($LASTEXITCODE -ne 0) { Write-Error "Asset conversion failed." }
}

# --- Export Tiled Levels -------------------------------------------------------
if (Test-Path "tools/export_level.py") {
    Write-Host "== Exporting Tiled Levels =="
    python tools/export_level.py assets/Levels/Level_01.tmx
    if ($LASTEXITCODE -ne 0) { Write-Error "Tiled export failed." }
}

# --- Convert Player BOB Assets ------------------------------------------------
if (Test-Path "tools/convert_player_bob.py") {
    Write-Host "== Converting Player BOB Assets =="
    python tools/convert_player_bob.py
    if ($LASTEXITCODE -ne 0) { Write-Error "Player BOB conversion failed." }
}

# --- Assemble ------------------------------------------------------------------
New-Item -ItemType Directory -Force build | Out-Null
Write-Host "== Assembling main.asm =="
& $vasm -m68000 -Fhunk -linedebug -ignore-mult-inc -nowarn=2047 -nowarn=2069 `
    -o build/main.o main.asm
if ($LASTEXITCODE -ne 0) { Write-Error "Assembly failed." }

# --- Link ----------------------------------------------------------------------
$outDir = Split-Path $Out
if ($outDir) { New-Item -ItemType Directory -Force $outDir | Out-Null }
Write-Host "== Linking $Out =="
& $vlink -bamigahunk -Bstatic -o $Out build/main.o
if ($LASTEXITCODE -ne 0) { Write-Error "Link failed." }

# Synchronize both workspace and parent uae/dh0/main so WinUAE always loads the latest binary
$workspaceDh0 = Join-Path $PSScriptRoot "uae/dh0/main"
$parentDh0 = Join-Path (Split-Path $PSScriptRoot) "uae/dh0/main"
if (Test-Path $Out) {
    $outResolved = (Resolve-Path $Out).Path
    if ((Test-Path (Split-Path $workspaceDh0)) -and $outResolved -ne (Resolve-Path $workspaceDh0 -ErrorAction SilentlyContinue).Path) {
        Copy-Item -Force $Out $workspaceDh0
        Write-Host "== Synced to $workspaceDh0 =="
    }
    if ((Test-Path (Split-Path $parentDh0)) -and $outResolved -ne (Resolve-Path $parentDh0 -ErrorAction SilentlyContinue).Path) {
        Copy-Item -Force $Out $parentDh0
        Write-Host "== Synced to $parentDh0 =="
    }
}

Write-Host "== OK: $Out =="
