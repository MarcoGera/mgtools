param(
    [Parameter(Mandatory = $true)][string]$SourceImage,
    [Parameter(Mandatory = $true)][string]$ProjectRoot
)

Add-Type -AssemblyName System.Drawing

$densities = @(
    @{ Name = 'mdpi'; Legacy = 48; Foreground = 108 },
    @{ Name = 'hdpi'; Legacy = 72; Foreground = 162 },
    @{ Name = 'xhdpi'; Legacy = 96; Foreground = 216 },
    @{ Name = 'xxhdpi'; Legacy = 144; Foreground = 324 },
    @{ Name = 'xxxhdpi'; Legacy = 192; Foreground = 432 }
)

function Save-Resized {
    param(
        [System.Drawing.Image]$Bitmap,
        [int]$Size,
        [string]$Path,
        [bool]$Round = $false
    )
    $out = New-Object System.Drawing.Bitmap(
        $Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    if ($Round) {
        $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
        $clip.AddEllipse(0, 0, $Size - 1, $Size - 1)
        $g.SetClip($clip)
    }
    $g.DrawImage($Bitmap, 0, 0, $Size, $Size)
    $g.Dispose()
    $out.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
}

if (-not (Test-Path $SourceImage)) { throw "Source image not found: $SourceImage" }

$source = [System.Drawing.Image]::FromFile($SourceImage)
$side = [Math]::Min($source.Width, $source.Height)
$cropX = [int](($source.Width - $side) / 2)
$cropY = [int](($source.Height - $side) / 2)

$square = New-Object System.Drawing.Bitmap($side, $side)
$g = [System.Drawing.Graphics]::FromImage($square)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage(
    $source,
    (New-Object System.Drawing.Rectangle(0, 0, $side, $side)),
    (New-Object System.Drawing.Rectangle($cropX, $cropY, $side, $side)),
    [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()

# Средний цвет изображения — для фона адаптивной иконки
$rSum = 0; $gSum = 0; $bSum = 0; $count = 0
$sample = New-Object System.Drawing.Bitmap($square)
for ($y = 0; $y -lt $side; $y += 8) {
    for ($x = 0; $x -lt $side; $x += 8) {
        $c = $sample.GetPixel($x, $y)
        $rSum += $c.R; $gSum += $c.G; $bSum += $c.B; $count++
    }
}
$sample.Dispose()
$bgColor = '#{0:X2}{1:X2}{2:X2}' -f [int]($rSum / $count), [int]($gSum / $count), [int]($bSum / $count)

$res = Join-Path $ProjectRoot 'android\app\src\main\res'
foreach ($d in $densities) {
    $dir = Join-Path $res "mipmap-$($d.Name)"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Save-Resized $square $d.Legacy (Join-Path $dir 'ic_launcher.png')
    Save-Resized $square $d.Legacy (Join-Path $dir 'ic_launcher_round.png') $true
    Save-Resized $square $d.Foreground (Join-Path $dir 'ic_launcher_foreground.png')
}

$valuesDir = Join-Path $res 'values'
New-Item -ItemType Directory -Path $valuesDir -Force | Out-Null
$bgXml = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<resources>`n    <color name=`"ic_launcher_background`">$bgColor</color>`n</resources>`n"
[System.IO.File]::WriteAllText((Join-Path $valuesDir 'ic_launcher_background.xml'), $bgXml)

$anyDpi = Join-Path $res 'mipmap-anydpi-v26'
New-Item -ItemType Directory -Path $anyDpi -Force | Out-Null
$adaptive = '<?xml version="1.0" encoding="utf-8"?>' + "`n" +
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">' + "`n" +
    '    <background android:drawable="@color/ic_launcher_background" />' + "`n" +
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />' + "`n" +
    '</adaptive-icon>' + "`n"
[System.IO.File]::WriteAllText((Join-Path $anyDpi 'ic_launcher.xml'), $adaptive)
[System.IO.File]::WriteAllText((Join-Path $anyDpi 'ic_launcher_round.xml'), $adaptive)

$manifest = Join-Path $ProjectRoot 'android\app\src\main\AndroidManifest.xml'
$manifestText = [System.IO.File]::ReadAllText($manifest)
if ($manifestText -notmatch 'android:roundIcon=') {
    $manifestText = [regex]::Replace(
        $manifestText,
        'android:icon="@mipmap/ic_launcher"',
        'android:icon="@mipmap/ic_launcher" android:roundIcon="@mipmap/ic_launcher_round"')
    [System.IO.File]::WriteAllText($manifest, $manifestText)
}

$square.Dispose()
$source.Dispose()
Write-Output "Icon installed into: $ProjectRoot"
Write-Output "Adaptive background color: $bgColor"
