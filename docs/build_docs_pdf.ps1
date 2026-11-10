# Builds the companion-guide PDFs from docs/*.md with Pandoc + XeLaTeX (same toolchain as the book).
#
# Usage:  ./docs/build_docs_pdf.ps1                          # every guide
#         ./docs/build_docs_pdf.ps1 -Name RING_BUFFER_GUIDE  # one guide
#
# Styling: docs/tools/guide-header.tex; "Breaks as:" call-out boxes: docs/tools/guide-boxes.lua.
# Rebuild the PDF whenever you edit its Markdown source, and commit both.
param([string]$Name = "")
$ErrorActionPreference = "Stop"

$Guides = @(
    "MAKING_A_GAME_GUIDE",
    "BLIT_ORDER_GUIDE",
    "RING_BUFFER_GUIDE",
    "ASSET_PIPELINE_GUIDE",
    "CODING_CONVENTIONS_GUIDE",
    "SINGLE_TRANSLATION_UNITS_GUIDE",
    "VSCODE_LAUNCH_PROFILES_GUIDE"
)
if ($Name) { $Guides = @($Name) }

$docs = $PSScriptRoot
$pandoc = (Get-Command pandoc -ErrorAction SilentlyContinue).Source
if (-not $pandoc) { $pandoc = "C:\Program Files\Pandoc\pandoc.exe" }
$xelatex = (Get-Command xelatex -ErrorAction SilentlyContinue).Source
if (-not $xelatex) { $xelatex = "$env:LOCALAPPDATA\Programs\MiKTeX\miktex\bin\x64\xelatex.exe" }

Push-Location $docs
try {
    foreach ($g in $Guides) {
        & $pandoc "$g.md" -o "$g.pdf" `
            --pdf-engine="$xelatex" `
            --shift-heading-level-by=-1 `
            -H tools/guide-header.tex `
            --lua-filter=tools/guide-boxes.lua `
            --toc --toc-depth=2 `
            --syntax-highlighting=tango `
            -V documentclass=article `
            -V geometry:"a4paper,margin=2cm" `
            -V mainfont="Georgia" -V monofont="Consolas" -V fontsize=10pt `
            -V subtitle="A companion guide to Building an AMIGA Game Engine" `
            -V author="Richard Shannon" `
            -V date="AmigaGameEngine v1.0"
        if ($LASTEXITCODE -ne 0) { throw "pandoc failed on $g ($LASTEXITCODE)" }
        Write-Host "OK: $docs\$g.pdf"
    }
} finally { Pop-Location }
