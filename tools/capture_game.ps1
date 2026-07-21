# Dev tool: launch the game, screenshot its window at given times, close it.
# Usage: .\capture_game.ps1 -Delays 5,8 -Prefix check [-DebugMode knock]
param(
    [int[]]$Delays = @(6),
    [string]$Prefix = "capture",
    [string]$DebugMode = ""
)

$src = @'
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public class WinCap2 {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static void Capture(IntPtr hwnd, string path) {
    SetProcessDPIAware();  // physical pixels, otherwise the capture gets cropped
    RECT r; GetWindowRect(hwnd, out r);
    int w = r.Right - r.Left, h = r.Bottom - r.Top;
    if (w <= 0 || h <= 0) throw new Exception("bad rect");
    Bitmap bmp = new Bitmap(w, h);
    Graphics g = Graphics.FromImage(bmp);
    IntPtr hdc = g.GetHdc();
    PrintWindow(hwnd, hdc, 2);
    g.ReleaseHdc(hdc);
    bmp.Save(path);
    g.Dispose();
    bmp.Dispose();
  }
}
'@
if (-not ([System.Management.Automation.PSTypeName]'WinCap2').Type) {
    Add-Type -TypeDefinition $src -ReferencedAssemblies System.Drawing
}

# Always assign so a value from a previous run in the same shell can't leak in.
$env:PROTO_DEBUG = $DebugMode
$godot = "C:\Users\lenovo\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe"
$proj = "C:\Users\lenovo\Projects\gmtk-terragen"
$p = Start-Process -FilePath $godot -ArgumentList '--path', $proj, '--resolution', '1280x720' -PassThru

$elapsed = 0
$i = 1
foreach ($d in $Delays) {
    Start-Sleep -Seconds ($d - $elapsed)
    $elapsed = $d
    $proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if ($proc) {
        [WinCap2]::Capture($proc.MainWindowHandle, "$proj\${Prefix}_$i.png")
    }
    $i++
}
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
$env:PROTO_DEBUG = ""
Write-Output "captured $($Delays.Count) frame(s)"
