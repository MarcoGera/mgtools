param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot
)

Add-Type -AssemblyName System.Drawing

$source = Join-Path $ProjectRoot 'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png'
$target = Join-Path $ProjectRoot 'windows\runner\resources\app_icon.ico'
if (-not (Test-Path $source)) { throw "Android icon not found: $source" }

$sizes = @(16, 32, 48, 64, 128, 256)
$images = New-Object System.Collections.Generic.List[byte[]]
$src = [System.Drawing.Image]::FromFile($source)

foreach ($size in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap(
        $size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $images.Add($ms.ToArray())
    $ms.Dispose()
    $bmp.Dispose()
}
$src.Dispose()

$header = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($header)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]$sizes.Count)

$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dim = if ($sizes[$i] -eq 256) { [byte]0 } else { [byte]$sizes[$i] }
    $bw.Write($dim)
    $bw.Write($dim)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]$images[$i].Length)
    $bw.Write([UInt32]$offset)
    $offset += $images[$i].Length
}

$dir = Split-Path $target
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$fs = [System.IO.File]::Create($target)
$fs.Write($header.ToArray(), 0, [int]$header.Length)
foreach ($png in $images) {
    $fs.Write($png, 0, $png.Length)
}
$fs.Dispose()
$bw.Dispose()
$header.Dispose()

Write-Output "Windows icon installed: $target"
