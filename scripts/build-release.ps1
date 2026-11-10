<#
.SYNOPSIS  Builds dist\StreonorDock-<version>.zip (git-ignored): the addon folder ready to unpack into Interface\AddOns.
.DESCRIPTION
  The zip root contains the folder "StreonorDock" (TOC, Lua, XML, embedded Libs with their license files, LICENSE)
  and INSTALL.txt. No tests, no scripts, no saved data. The version comes from "## Version:" in the TOC.
.PARAMETER OutDir  Output folder (default: dist next to the repo root).
#>
param([string]$OutDir)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
$src = Join-Path $root 'src\StreonorDock'
$toc = Get-Content -LiteralPath (Join-Path $src 'StreonorDock.toc')
$versionLine = $toc | Where-Object { $_ -match '^## Version:\s*(\S+)' } | Select-Object -First 1
if (-not $versionLine -or $versionLine -notmatch '^## Version:\s*(\d+\.\d+\.\d+)') { throw 'No "## Version: x.y.z" line in the TOC' }
$version = $Matches[1]
$interface = ($toc | Where-Object { $_ -match '^## Interface:\s*(\d+)' } | Select-Object -First 1) -replace '^## Interface:\s*', ''

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("sd-addon-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
  $dest = Join-Path $stage 'StreonorDock'
  & robocopy $src $dest /E /XF *.bak *.zip Thumbs.db /NFL /NDL /NJH /NJS | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
  Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $dest 'LICENSE')
  @"
StreonorDock $version (Interface $interface)
Stream Controller Actionbar for Streonor Dock

INSTALL
1. Close World of Warcraft (or just /reload after copying).
2. Extract this zip. Copy the folder "StreonorDock" into
       <your WoW folder>\_forever_\Interface\AddOns\
   so that  ...\AddOns\StreonorDock\StreonorDock.toc  exists. Libraries are included; nothing else is needed.
3. Start the game (restart the client if a brand-new addon folder does not show up) and make sure StreonorDock is enabled
   on the character select AddOns screen.
4. In game: /sdock  (help),  /sdock settings,  /sdock assign.

REQUIRED for the S15 keys: the Streonor plugin
   https://github.com/DinoNuggolus/StreonorWoW
Install it with its double-click installer (see its README), then place Dock Key 1..15 in landscape order:
       top row:     11  12  13  14  15
       middle row:   6   7   8   9  10
       bottom row:   1   2   3   4   5     (Dock Key 1 is bottom-left)

UPDATE: extract over the old folder (your settings live in WTF and are kept). REMOVE: delete the StreonorDock folder.
License: MIT (addon). Embedded libraries keep their own licenses, see StreonorDock\Libs\LIBRARIES.md.
"@ | Set-Content -LiteralPath (Join-Path $stage 'INSTALL.txt') -Encoding ASCII

  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $zip = Join-Path $OutDir "StreonorDock-$version.zip"
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
  try {
    Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($stage.Length + 1) -replace '\\', '/'
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $rel, 'Optimal') | Out-Null
    }
  } finally { $archive.Dispose() }
  Write-Host "Built $zip"
  Write-Host ("SHA256 " + (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash)
} finally {
  Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
