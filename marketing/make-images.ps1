param([Parameter(Mandatory = $true)][string]$Marketing)
# Builds the game-page thumbnails (1280x720 JPG) and icon (512x512 PNG) from the raw Studio
# screenshots in $Marketing\raw, adding chunky outlined titles like the in-game UI.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$FontName = "Segoe UI Black"
$Navy = [System.Drawing.Color]::FromArgb(255, 22, 30, 44)
$Shadow = [System.Drawing.Color]::FromArgb(140, 0, 0, 0)
$Yellow = [System.Drawing.Color]::FromArgb(255, 255, 230, 70)
$Orange = [System.Drawing.Color]::FromArgb(255, 255, 150, 20)
$White = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$Mint = [System.Drawing.Color]::FromArgb(255, 150, 255, 120)
$Green = [System.Drawing.Color]::FromArgb(255, 60, 210, 60)

function New-Canvas([string]$source, [int]$cropX, [int]$cropY, [int]$cropW, [int]$cropH, [int]$outW, [int]$outH) {
	$image = [System.Drawing.Image]::FromFile($source)
	$bitmap = New-Object System.Drawing.Bitmap($outW, $outH)
	$g = [System.Drawing.Graphics]::FromImage($bitmap)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
	$g.DrawImage($image, (New-Object System.Drawing.Rectangle(0, 0, $outW, $outH)), (New-Object System.Drawing.Rectangle($cropX, $cropY, $cropW, $cropH)), [System.Drawing.GraphicsUnit]::Pixel)
	$image.Dispose()
	return @{ Bitmap = $bitmap; Graphics = $g }
}

# Outlined text centred on (cx, top). Fill is a vertical gradient from $top to $bottom colour.
function Add-Title($g, [string]$text, [float]$size, [float]$cx, [float]$top, $fillTop, $fillBottom, [float]$outline) {
	$family = New-Object System.Drawing.FontFamily($FontName)
	$format = New-Object System.Drawing.StringFormat
	$format.Alignment = [System.Drawing.StringAlignment]::Center
	$path = New-Object System.Drawing.Drawing2D.GraphicsPath
	$path.AddString($text, $family, [int][System.Drawing.FontStyle]::Regular, $size, (New-Object System.Drawing.PointF($cx, $top)), $format)
	$bounds = $path.GetBounds()
	# Drop shadow
	$shadowPath = $path.Clone()
	$matrix = New-Object System.Drawing.Drawing2D.Matrix
	$matrix.Translate(0, $outline * 0.55)
	$shadowPath.Transform($matrix)
	$shadowPen = New-Object System.Drawing.Pen($Shadow, [float]($outline * 2))
	$shadowPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
	$g.DrawPath($shadowPen, $shadowPath)
	# Outline, then fill
	$pen = New-Object System.Drawing.Pen($Navy, [float]($outline * 2))
	$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
	$g.DrawPath($pen, $path)
	$rect = New-Object System.Drawing.RectangleF($bounds.X, ($bounds.Y - 1), $bounds.Width, ($bounds.Height + 2))
	$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $fillTop, $fillBottom, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
	$g.FillPath($brush, $path)
	return $bounds
}

function Save-Jpeg($bitmap, [string]$file) {
	$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
	$params = New-Object System.Drawing.Imaging.EncoderParameters(1)
	$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]93)
	$bitmap.Save($file, $codec, $params)
}

$raw = Join-Path $Marketing "raw"
$cropX = 44 # 1369x720 screenshots -> centred 1280x720

# 1. Hero: the street with the title
$c = New-Canvas (Join-Path $raw "city-street.jpg") $cropX 0 1280 720 1280 720
Add-Title $c.Graphics "SHOP CITY" 132 640 6 $Yellow $Orange 13 | Out-Null
Add-Title $c.Graphics "TYCOON" 112 640 150 $White ([System.Drawing.Color]::FromArgb(255, 200, 235, 255)) 12 | Out-Null
Save-Jpeg $c.Bitmap (Join-Path $Marketing "thumbnail-1-city.jpg"); $c.Graphics.Dispose(); $c.Bitmap.Dispose()

# 2. Mini game
$c = New-Canvas (Join-Path $raw "minigame-pizza.jpg") $cropX 0 1280 720 1280 720
# Paint over the window's hint line ("Next: ...") so it doesn't show between the letters.
$windowColor = $c.Bitmap.GetPixel(166, 450)
$c.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($windowColor)), 168, 606, 944, 54)
Add-Title $c.Graphics "PLAY MINI GAMES!" 78 640 588 $Yellow $Orange 10 | Out-Null
Save-Jpeg $c.Bitmap (Join-Path $Marketing "thumbnail-2-minigame.jpg"); $c.Graphics.Dispose(); $c.Bitmap.Dispose()

# 3. Street customers
$c = New-Canvas (Join-Path $raw "street-pizza-boxes.jpg") $cropX 0 1280 720 1280 720
Add-Title $c.Graphics "REAL CUSTOMERS!" 76 900 560 $White ([System.Drawing.Color]::FromArgb(255, 200, 235, 255)) 10 | Out-Null
Save-Jpeg $c.Bitmap (Join-Path $Marketing "thumbnail-3-street.jpg"); $c.Graphics.Dispose(); $c.Bitmap.Dispose()

# 4. Inside the restaurant
$c = New-Canvas (Join-Path $raw "pizza-inside.jpg") $cropX 0 1280 720 1280 720
Add-Title $c.Graphics "UPGRADE YOUR SHOP!" 76 640 8 $Mint $Green 10 | Out-Null
Save-Jpeg $c.Bitmap (Join-Path $Marketing "thumbnail-4-inside.jpg"); $c.Graphics.Dispose(); $c.Bitmap.Dispose()

# 5. Aerial
$c = New-Canvas (Join-Path $raw "city-aerial.jpg") $cropX 0 1280 720 1280 720
Add-Title $c.Graphics "26 BUSINESSES TO OWN!" 72 640 420 $Yellow $Orange 10 | Out-Null
Save-Jpeg $c.Bitmap (Join-Path $Marketing "thumbnail-5-aerial.jpg"); $c.Graphics.Dispose(); $c.Bitmap.Dispose()

# Icon: square crop around the Pizza Restaurant, 512x512
$c = New-Canvas (Join-Path $raw "icon-base.jpg") 292 0 720 720 512 512
Add-Title $c.Graphics "SHOP CITY" 74 256 6 $Yellow $Orange 8 | Out-Null
Add-Title $c.Graphics "TYCOON" 82 256 404 $White ([System.Drawing.Color]::FromArgb(255, 200, 235, 255)) 9 | Out-Null
$c.Bitmap.Save((Join-Path $Marketing "icon.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$c.Graphics.Dispose(); $c.Bitmap.Dispose()

Get-ChildItem $Marketing -File | Where-Object { $_.Extension -in ".jpg", ".png" } | ForEach-Object { "{0}  {1:N0} KB" -f $_.Name, ($_.Length / 1KB) }
