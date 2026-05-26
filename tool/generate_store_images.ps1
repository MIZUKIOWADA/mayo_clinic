Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$iconDir = Join-Path $root "store\icons"
$screenshotDir = Join-Path $root "store\screenshots"
New-Item -ItemType Directory -Force -Path $iconDir | Out-Null
New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null

function New-Font {
    param([float]$Size, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular)
    $families = @("Yu Gothic UI", "Meiryo", "Arial")
    foreach ($family in $families) {
        try { return [System.Drawing.Font]::new($family, $Size, $Style, [System.Drawing.GraphicsUnit]::Pixel) } catch {}
    }
    return [System.Drawing.SystemFonts]::DefaultFont
}

function Add-RoundedRect {
    param($Path, [float]$X, [float]$Y, [float]$W, [float]$H, [float]$R)
    $d = $R * 2
    $Path.AddArc($X, $Y, $d, $d, 180, 90)
    $Path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $Path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $Path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $Path.CloseFigure()
}

function Draw-CenteredText {
    param($Graphics, [string]$Text, $Font, $Brush, [System.Drawing.RectangleF]$Rect)
    $format = [System.Drawing.StringFormat]::new()
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $Graphics.DrawString($Text, $Font, $Brush, $Rect, $format)
    $format.Dispose()
}

function Save-AppIcon {
    $bmp = [System.Drawing.Bitmap]::new(1024, 1024)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(15, 20, 22))

    $teal = [System.Drawing.Color]::FromArgb(31, 138, 112)
    $mint = [System.Drawing.Color]::FromArgb(96, 214, 166)
    $white = [System.Drawing.Color]::FromArgb(233, 255, 246)
    $yellow = [System.Drawing.Color]::FromArgb(255, 200, 87)

    $circleBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(23, 53, 58))
    $g.FillEllipse($circleBrush, 156, 156, 712, 712)

    $cap = [System.Drawing.Drawing2D.LineCap]::Round
    $browPen = [System.Drawing.Pen]::new($mint, 54)
    $browPen.StartCap = $cap
    $browPen.EndCap = $cap
    $g.DrawArc($browPen, 295, 276, 434, 224, 205, 130)

    $eyeBrush = [System.Drawing.SolidBrush]::new($white)
    $g.FillEllipse($eyeBrush, 367, 439, 66, 66)
    $g.FillEllipse($eyeBrush, 591, 439, 66, 66)

    $mouthPen = [System.Drawing.Pen]::new($white, 54)
    $mouthPen.StartCap = $cap
    $mouthPen.EndCap = $cap
    $g.DrawArc($mouthPen, 328, 550, 368, 188, 28, 124)

    $linePen = [System.Drawing.Pen]::new($mint, 28)
    $linePen.StartCap = $cap
    $linePen.EndCap = $cap
    $g.DrawLine($linePen, 354, 704, 670, 704)

    $alertPen = [System.Drawing.Pen]::new($yellow, 28)
    $alertPen.StartCap = $cap
    $alertPen.EndCap = $cap
    $g.DrawLine($alertPen, 770, 286, 822, 234)
    $g.DrawLine($alertPen, 772, 343, 848, 333)
    $g.DrawLine($alertPen, 720, 262, 729, 186)

    $path = Join-Path $iconDir "app-icon-1024.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

function Save-DraftScreenshot {
    param([string]$FileName, [string]$State, [string]$Score, [string]$Duration, [System.Drawing.Color]$Accent)

    $bmp = [System.Drawing.Bitmap]::new(1080, 1920)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(15, 20, 22))

    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(180, 220, 224, 226))
    $panel = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(238, 16, 23, 25))
    $camera = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(24, 44, 48))
    $accentBrush = [System.Drawing.SolidBrush]::new($Accent)

    $titleFont = New-Font 54 ([System.Drawing.FontStyle]::Bold)
    $statusFont = New-Font 46 ([System.Drawing.FontStyle]::Bold)
    $bodyFont = New-Font 30
    $metricFont = New-Font 38 ([System.Drawing.FontStyle]::Bold)

    $topPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    Add-RoundedRect $topPath 48 80 984 118 18
    $g.FillPath($panel, $topPath)
    $g.FillEllipse($accentBrush, 84, 118, 42, 42)
    $g.DrawString("Kuchi Toji Watch", $titleFont, $white, 150, 108)
    $g.DrawString("alert 0", $bodyFont, $muted, 842, 122)

    $g.FillRectangle($camera, 0, 230, 1080, 1120)
    $facePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(96, 214, 166), 16)
    $facePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $facePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawEllipse($facePen, 308, 440, 464, 544)
    $g.DrawEllipse([System.Drawing.Pens]::White, 420, 642, 44, 44)
    $g.DrawEllipse([System.Drawing.Pens]::White, 616, 642, 44, 44)
    $mouthPen = [System.Drawing.Pen]::new($Accent, 20)
    $mouthPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $mouthPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    if ($State -eq "OK") {
        $g.DrawLine($mouthPen, 438, 820, 642, 820)
    } else {
        $g.DrawEllipse($mouthPen, 478, 782, 124, 94)
    }

    $panelPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    Add-RoundedRect $panelPath 32 1390 1016 420 18
    $g.FillPath($panel, $panelPath)
    $g.FillEllipse($accentBrush, 72, 1446, 72, 72)
    $g.DrawString($State, $statusFont, $white, 174, 1444)
    $g.DrawString("score", $bodyFont, $muted, 740, 1432)
    $g.DrawString($Score, $metricFont, $white, 740, 1470)
    $g.DrawString("sec", $bodyFont, $muted, 884, 1432)
    $g.DrawString($Duration, $metricFont, $white, 884, 1470)

    $barBg = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(48, 255, 255, 255))
    $g.FillRectangle($barBg, 72, 1578, 936, 18)
    $g.FillRectangle($accentBrush, 72, 1578, 520, 18)
    $g.DrawString("threshold 0.20", $bodyFont, $muted, 72, 1640)
    $g.DrawString("1.5 sec", $bodyFont, $muted, 590, 1640)
    $g.DrawString("Pause", $bodyFont, $white, 72, 1720)

    $path = Join-Path $screenshotDir $FileName
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

Save-AppIcon
Save-DraftScreenshot "draft-android-phone-01-ok.png" "OK" "0.08" "0.0" ([System.Drawing.Color]::FromArgb(90, 211, 154))
Save-DraftScreenshot "draft-android-phone-02-alert.png" "Mouth open" "0.31" "1.7" ([System.Drawing.Color]::FromArgb(255, 107, 107))

Write-Host "Generated store icon and draft screenshots."
