$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'assets\branding\mpsc_ai_sathi_logo_source.jpg'
if (-not (Test-Path $src)) {
  throw "Missing $src"
}

$code = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class LogoPrep {
  public static void Run(string src, string root) {
    Image srcImg = Image.FromFile(src);
    Bitmap bmp = new Bitmap(srcImg);
    try {
      int minX = bmp.Width, minY = bmp.Height, maxX = 0, maxY = 0;
      for (int y = 0; y < bmp.Height; y++) {
        for (int x = 0; x < bmp.Width; x++) {
          Color c = bmp.GetPixel(x, y);
          if (c.R > 228 && c.G > 228 && c.B > 228) continue;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
      if (maxX <= minX || maxY <= minY) {
        minX = 0; minY = 0; maxX = bmp.Width - 1; maxY = bmp.Height - 1;
      }
      int pad = Math.Max(4, (int)(Math.Max(maxX - minX, maxY - minY) * 0.012));
      minX = Math.Max(0, minX - pad);
      minY = Math.Max(0, minY - pad);
      maxX = Math.Min(bmp.Width - 1, maxX + pad);
      maxY = Math.Min(bmp.Height - 1, maxY + pad);
      int w = maxX - minX + 1;
      int h = maxY - minY + 1;
      int side = Math.Max(w, h);
      Bitmap square = new Bitmap(side, side, PixelFormat.Format32bppArgb);
      Graphics g0 = Graphics.FromImage(square);
      try {
        g0.Clear(Color.FromArgb(255, 236, 236, 236));
        g0.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g0.SmoothingMode = SmoothingMode.HighQuality;
        g0.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g0.CompositingQuality = CompositingQuality.HighQuality;
        g0.DrawImage(bmp, new Rectangle((side - w) / 2, (side - h) / 2, w, h),
          new Rectangle(minX, minY, w, h), GraphicsUnit.Pixel);
        SavePng(square, Path.Combine(root, "assets", "branding", "mpsc_ai_sathi_logo.png"), 1024);
        SavePng(square, Path.Combine(root, "web", "favicon.png"), 64);
        SavePng(square, Path.Combine(root, "web", "icons", "Icon-192.png"), 192);
        SavePng(square, Path.Combine(root, "web", "icons", "Icon-512.png"), 512);
        SavePng(square, Path.Combine(root, "web", "icons", "apple-touch-icon.png"), 180);
        SaveMaskable(square, Path.Combine(root, "web", "icons", "Icon-maskable-192.png"), 192);
        SaveMaskable(square, Path.Combine(root, "web", "icons", "Icon-maskable-512.png"), 512);
        string mip = Path.Combine(root, "android", "app", "src", "main", "res");
        SavePng(square, Path.Combine(mip, "mipmap-mdpi", "ic_launcher.png"), 48);
        SavePng(square, Path.Combine(mip, "mipmap-hdpi", "ic_launcher.png"), 72);
        SavePng(square, Path.Combine(mip, "mipmap-xhdpi", "ic_launcher.png"), 96);
        SavePng(square, Path.Combine(mip, "mipmap-xxhdpi", "ic_launcher.png"), 144);
        SavePng(square, Path.Combine(mip, "mipmap-xxxhdpi", "ic_launcher.png"), 192);
      } finally {
        g0.Dispose();
        square.Dispose();
      }
    } finally {
      bmp.Dispose();
      srcImg.Dispose();
    }
  }

  static void SaveMaskable(Bitmap src, string path, int size) {
    Directory.CreateDirectory(Path.GetDirectoryName(path));
    Bitmap canvas = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    Graphics g = Graphics.FromImage(canvas);
    try {
      g.Clear(Color.FromArgb(255, 11, 42, 74));
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.SmoothingMode = SmoothingMode.HighQuality;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      int inner = (int)(size * 0.72);
      int o = (size - inner) / 2;
      g.DrawImage(src, new Rectangle(o, o, inner, inner));
      canvas.Save(path, ImageFormat.Png);
    } finally {
      g.Dispose();
      canvas.Dispose();
    }
  }

  static void SavePng(Bitmap src, string path, int size) {
    Directory.CreateDirectory(Path.GetDirectoryName(path));
    Bitmap dest = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    Graphics g = Graphics.FromImage(dest);
    try {
      g.Clear(Color.Transparent);
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.SmoothingMode = SmoothingMode.HighQuality;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.CompositingQuality = CompositingQuality.HighQuality;
      g.DrawImage(src, new Rectangle(0, 0, size, size));
      dest.Save(path, ImageFormat.Png);
    } finally {
      g.Dispose();
      dest.Dispose();
    }
  }
}
'@

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $code
[LogoPrep]::Run($src, $root)
Write-Host 'logo prep ok'
Get-ChildItem -Recurse (Join-Path $root 'assets\branding'), (Join-Path $root 'web\icons') |
  Select-Object FullName, Length | Format-Table -AutoSize
Get-Item (Join-Path $root 'web\favicon.png') | Select-Object FullName, Length
