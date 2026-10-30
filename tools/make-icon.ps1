# Generates assets/icon.ico (256x256 PNG-compressed ICO).
# Run from the repository root: powershell -NoProfile -File .\tools\make-icon.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'assets'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir 'icon.ico'

$size = 256
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$bgPath = New-RoundedPath 8 8 240 240 48
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0, 0)),
    (New-Object System.Drawing.Point(256, 256)),
    [System.Drawing.Color]::FromArgb(255, 11, 18, 32),
    [System.Drawing.Color]::FromArgb(255, 14, 40, 54)
)
$g.FillPath($bgBrush, $bgPath)
$borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 30, 64, 84), 4)
$g.DrawPath($borderPen, $bgPath)

$teal = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 45, 212, 191), 13)
$teal.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$teal.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$sky = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 56, 189, 248), 13)
$sky.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$sky.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

$g.DrawArc($teal, 50, 50, 156, 156, 200, 120)
$g.DrawArc($sky, 50, 50, 156, 156, 20, 120)

# Arrowheads
$tealBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 45, 212, 191))
$skyBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 56, 189, 248))
$g.FillPolygon($tealBrush, @(
    (New-Object System.Drawing.Point(190, 44)),
    (New-Object System.Drawing.Point(214, 82)),
    (New-Object System.Drawing.Point(170, 80))
))
$g.FillPolygon($skyBrush, @(
    (New-Object System.Drawing.Point(66, 212)),
    (New-Object System.Drawing.Point(42, 174)),
    (New-Object System.Drawing.Point(86, 176))
))

# Barcode panel
$panel = New-RoundedPath 82 100 92 56 10
$g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 10, 34, 48))), $panel)
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 226, 232, 240))
$bars = @(
    @(94, 112, 4, 32), @(102, 112, 3, 32), @(109, 112, 7, 32),
    @(120, 112, 3, 32), @(127, 112, 5, 32), @(136, 112, 2, 32),
    @(142, 112, 6, 32), @(152, 112, 3, 32), @(159, 112, 5, 32)
)
foreach ($b in $bars) { $g.FillRectangle($white, $b[0], $b[1], $b[2], $b[3]) }

# Small sync dot accents
$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 52, 211, 153))), 174, 178, 14, 14)

$g.Dispose()

$pngStream = New-Object System.IO.MemoryStream
$bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
$png = $pngStream.ToArray()
$pngStream.Dispose()
$bmp.Dispose()

$fs = [System.IO.File]::Create($outPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]1)
$bw.Write([Byte]0)
$bw.Write([Byte]0)
$bw.Write([Byte]0)
$bw.Write([Byte]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]32)
$bw.Write([UInt32]$png.Length)
$bw.Write([UInt32]22)
$bw.Write($png)
$bw.Dispose()
$fs.Dispose()

Write-Host "Created $outPath ($((Get-Item $outPath).Length) bytes)"
