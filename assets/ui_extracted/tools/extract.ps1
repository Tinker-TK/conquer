param([string]$Source = 'C:\Users\10059\Downloads\ChatGPT Image 2026年9月5日 11_47_48.png')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetRoot = Split-Path $PSScriptRoot -Parent
$items = Get-Content (Join-Path $assetRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceImage = [System.Drawing.Bitmap]::FromFile($Source)
try {
    foreach ($item in $items) {
        $destination = Join-Path $assetRoot $item.file
        [System.IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
        $rect = [System.Drawing.Rectangle]::new($item.x, $item.y, $item.width, $item.height)
        if ($rect.Right -gt $sourceImage.Width -or $rect.Bottom -gt $sourceImage.Height) { throw "Outside source: $($item.file)" }
        $crop = $sourceImage.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try { $crop.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $crop.Dispose() }
        $verified = [System.Drawing.Bitmap]::FromFile($destination)
        try {
            if ($verified.Width -ne $item.width -or $verified.Height -ne $item.height) { throw "Wrong size: $destination" }
            for ($py = 0; $py -lt $item.height; $py++) {
                for ($px = 0; $px -lt $item.width; $px++) {
                    if ($verified.GetPixel($px, $py).ToArgb() -ne $sourceImage.GetPixel($item.x + $px, $item.y + $py).ToArgb()) { throw "Pixel mismatch: $destination" }
                }
            }
        } finally { $verified.Dispose() }
    }
    Write-Output "Extracted and pixel-verified $($items.Count) PNG files."
} finally { $sourceImage.Dispose() }
