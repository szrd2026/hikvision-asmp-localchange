[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
$source = Join-Path $root 'LocalChangeTool.ps1'
$icon = Join-Path $root 'assets\icon.ico'
$output = Join-Path $dist "Hikvision-LocalChange-v$Version-win64.exe"

if (-not (Test-Path $source)) { throw "Source script not found: $source" }
if (-not (Test-Path $icon)) { throw "Icon not found: $icon. Run tools\make-icon.ps1 first." }

$module = Get-Module -ListAvailable ps2exe | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) {
    throw 'ps2exe is required. Install it with: Install-PSResource ps2exe -Scope CurrentUser'
}
Import-Module $module.Path -Force

Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$fileVersion = if ($Version -match '^\d+\.\d+\.\d+$') { "$Version.0" } else { $Version }

$params = @{
    InputFile   = $source
    OutputFile  = $output
    NoConsole   = $true
    STA         = $true
    x64         = $true
    SupportOS   = $true
    IconFile    = $icon
    Title       = "Hikvision ASMP Local Change Tool v$Version"
    Description = 'Portable Windows GUI for batch RMA local-change submissions to Hikvision ASMP.'
    Company     = 'szrd2026'
    Product     = 'Hikvision ASMP Local Change Tool'
    Copyright   = '(c) 2026 szrd2026. MIT License.'
    Version     = $fileVersion
}

Write-Host "Building $output ..."
Invoke-PS2Exe @params

if (-not (Test-Path $output)) { throw "Build did not produce $output" }

$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = Join-Path $dist 'checksums.txt'
$checksumLine = "$hash  $([IO.Path]::GetFileName($output))"
[IO.File]::WriteAllText($checksumPath, $checksumLine + "`r`n", [Text.Encoding]::ASCII)

$size = (Get-Item -LiteralPath $output).Length
Write-Host ''
Write-Host "Output   : $output"
Write-Host "Size     : $size bytes"
Write-Host "SHA256   : $hash"
Write-Host "Checksums: $checksumPath"
